import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { readNight } from '../src/digest/read.js';

let runsDir: string;
const normalNight = [
  '{"at":"2026-10-28T01:00:00+01:00","job":"zebra","status":"retry","owner":"rook","error":"lock held"}',
  '{"at":"2026-10-28T01:01:00+01:00","job":"alpha","status":"fail","owner":null,"error":"quota exceeded"}',
  '{"at":"2026-10-28T01:02:00+01:00","job":"zebra","status":"ok","owner":"rook"}',
].join('\n');
const badNight = [
  '{"at":"2026-10-30T01:00:00+01:00","job":"backup","status":"ok","owner":"rook"}',
  'not json',
].join('\n');

beforeAll(() => {
  const varDir = fileURLToPath(new URL('../var/', import.meta.url));
  mkdirSync(varDir, { recursive: true });
  runsDir = mkdtempSync(join(varDir, 'test-runs-'));
  writeFileSync(join(runsDir, 'latest.jsonl'), normalNight.split('\n')[0]);
  writeFileSync(join(runsDir, '2026-10-28.jsonl'), normalNight);
  writeFileSync(join(runsDir, '2026-10-29.jsonl'), '');
  writeFileSync(join(runsDir, '2026-10-30.jsonl'), badNight);
});

afterAll(() => {
  if (runsDir) rmSync(runsDir, { recursive: true, force: true });
});

function app() {
  return createApp({
    adapter: 'shim',
    installed: '2026-10-28T00:00:00+01:00',
    beatEverySeconds: 60,
    runsDir,
  });
}

describe('digest page routes', () => {
  it('returns 200 with one table and exact rows in job order', async () => {
    const res = await app().request('/digest/2026-10-28');
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('text/html');
    const html = await res.text();
    expect(html).toContain('<h1>digest · 2026-10-28</h1>');
    expect(html.match(/<table>/g)).toHaveLength(1);
    const body = html.match(/<tbody>(.*?)<\/tbody>/s)?.[1] ?? '';
    const rows = [...body.matchAll(/<tr[^>]*>(.*?)<\/tr>/gs)].map((row) =>
      [...row[1].matchAll(/<td>(.*?)<\/td>/gs)].map((cell) => cell[1]),
    );
    expect(rows).toEqual([
      ['alpha', '—', '1', '0', 'fail', 'quota exceeded',
        '2026-10-28T01:01:00+01:00', '2026-10-28T01:01:00+01:00'],
      ['zebra', 'rook', '2', '1', 'ok', 'lock held',
        '2026-10-28T01:00:00+01:00', '2026-10-28T01:02:00+01:00'],
    ]);
  });

  it('returns 404 for a night with no file', async () => {
    const res = await app().request('/digest/2026-10-31');
    expect(res.status).toBe(404);
    expect(await res.text()).toBe('404 Not Found');
  });

  it('returns 404 for a non-date night even when its file exists', async () => {
    const res = await app().request('/digest/latest');
    expect(res.status).toBe(404);
    expect(await res.text()).toBe('404 Not Found');
  });

  it('returns 200 and says nothing ran for an empty night', async () => {
    const res = await app().request('/digest/2026-10-29');
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain('<p class="mute">nothing ran</p>');
    expect(html).toContain('<tbody></tbody>');
    expect(html).not.toContain('could not be read');
  });

  it('returns 200 with the readable row and exact bad-line note', async () => {
    const res = await app().request('/digest/2026-10-30');
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain('<td>backup</td><td>rook</td><td>1</td><td>0</td><td>ok</td><td>—</td><td>2026-10-30T01:00:00+01:00</td><td>2026-10-30T01:00:00+01:00</td>');
    expect(html).toContain('<p class="mute">1 line could not be read</p>');
    expect(html).not.toContain('nothing ran');
  });
});

describe('digest JSON routes', () => {
  it('returns 200 with every row field, badLines and counts equal to readNight', async () => {
    const res = await app().request('/api/digest/2026-10-28');
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('application/json');
    const digest = await res.json();
    const expected = readNight(runsDir, '2026-10-28');
    expect(expected).not.toBeNull();
    expect(digest.night).toBe('2026-10-28');
    expect(digest.rows).toEqual(expected?.rows);
    expect(digest.rows.map((row: { job: string }) => row.job)).toEqual(['alpha', 'zebra']);
    expect(digest.badLines).toBe(expected?.badLines);
    expect(digest.badLines).toBe(0);
    expect(digest.counts).toEqual(expected?.counts);
    expect(digest.counts).toEqual({ ok: 1, retry: 1, fail: 1 });
  });

  it('returns JSON 404 for a night with no file', async () => {
    const res = await app().request('/api/digest/2026-10-31');
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: 'not found' });
  });

  it('returns JSON 404 for a non-date night even when its file exists', async () => {
    const res = await app().request('/api/digest/latest');
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: 'not found' });
  });

  it('returns 200 with no rows and badLines 0 for an empty night', async () => {
    const res = await app().request('/api/digest/2026-10-29');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      night: '2026-10-29',
      rows: [],
      badLines: 0,
      counts: { ok: 0, retry: 0, fail: 0 },
    });
  });

  it('returns 200 with the readable row and badLines 1', async () => {
    const res = await app().request('/api/digest/2026-10-30');
    expect(res.status).toBe(200);
    const digest = await res.json();
    expect(digest).toEqual({ night: '2026-10-30', ...readNight(runsDir, '2026-10-30') });
    expect(digest.rows).toEqual([{
      job: 'backup', owner: 'rook', runs: 1, retries: 0, lastStatus: 'ok', lastError: null,
      firstTime: '2026-10-30T01:00:00+01:00', lastTime: '2026-10-30T01:00:00+01:00',
    }]);
    expect(digest.badLines).toBe(1);
    expect(digest.counts).toEqual({ ok: 1, retry: 0, fail: 0 });
  });
});
