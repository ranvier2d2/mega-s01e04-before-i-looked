import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { readNight } from '../src/digest/read.js';

describe('run log reader', () => {
  it('summarizes 2026-10-28 in job order, preserving offsets and errors', () => {
    const digest = readNight('runs', '2026-10-28');
    expect(digest).not.toBeNull();
    expect(digest?.rows.map((row) => row.job)).toEqual([
      'digest/render',
      'fixtures/refresh',
      'lane/sync',
      'notes/backup',
      'rig/rotate-logs',
    ]);
    expect(digest?.badLines).toBe(1);
    expect(digest?.counts).toEqual({ ok: 10, retry: 4, fail: 1 });
    expect(digest?.rows[0].owner).toBeNull();
    expect(digest?.rows[1]).toMatchObject({
      runs: 4,
      retries: 3,
      lastStatus: 'ok',
      firstTime: '2026-10-29T01:30:00+01:00',
      lastTime: '2026-10-29T01:37:00+01:00',
    });
    expect(digest?.rows[2]).toMatchObject({
      runs: 8,
      retries: 1,
      lastStatus: 'ok',
      lastError: 'lock held',
    });
    expect(digest?.rows[3]).toMatchObject({
      lastStatus: 'fail',
      lastError: 'quota exceeded',
    });
  });

  it('returns null for a missing night', () => {
    expect(readNight('runs', 'missing-night')).toBeNull();
  });

  it('returns no rows or bad lines for an empty file', () => {
    const dir = mkdtempSync(join(process.cwd(), '.digest-reader-'));
    try {
      writeFileSync(join(dir, 'empty.jsonl'), '');
      expect(readNight(dir, 'empty')).toEqual({
        rows: [], badLines: 0, counts: { ok: 0, retry: 0, fail: 0 },
      });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('counts malformed shapes, skips blanks, and retains the most recent error string', () => {
    const dir = mkdtempSync(join(process.cwd(), '.digest-reader-'));
    const line = { at: '2026-10-29T01:00:00+01:00', job: 'job', status: 'retry', owner: null };
    try {
      writeFileSync(join(dir, 'mixed.jsonl'), [
        '', '  ', '{', 'null', '[]', '{}',
        JSON.stringify({ ...line, at: 1 }),
        JSON.stringify({ ...line, job: null }),
        JSON.stringify({ ...line, status: 'unknown' }),
        JSON.stringify({ ...line, owner: 1 }),
        JSON.stringify({ at: line.at, job: line.job, status: line.status }),
        JSON.stringify({ ...line, error: null }),
        JSON.stringify({ ...line, error: 'old error' }),
        JSON.stringify({ ...line, error: '' }),
        JSON.stringify({ ...line, at: '2026-10-29T02:00:00+01:00', status: 'ok' }),
        JSON.stringify({ ...line, job: 'no-error', status: 'ok' }),
        '',
      ].join('\n'));
      expect(readNight(dir, 'mixed')).toEqual({
        rows: [
          { job: 'job', owner: null, runs: 3, retries: 2, lastStatus: 'ok', lastError: '',
            firstTime: line.at, lastTime: '2026-10-29T02:00:00+01:00' },
          { job: 'no-error', owner: null, runs: 1, retries: 0, lastStatus: 'ok', lastError: null,
            firstTime: line.at, lastTime: line.at },
        ],
        badLines: 10,
        counts: { ok: 2, retry: 2, fail: 0 },
      });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
