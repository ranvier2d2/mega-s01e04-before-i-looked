import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { DigestResult, DigestRow, ReadNight } from './types.js';

type RunLine = {
  at: string;
  job: string;
  status: DigestRow['lastStatus'];
  owner: string | null;
  error?: string;
};

function isRunLine(value: unknown): value is RunLine {
  return typeof value === 'object' && value !== null
    && 'at' in value && typeof value.at === 'string'
    && 'job' in value && typeof value.job === 'string'
    && 'status' in value && (value.status === 'ok' || value.status === 'retry' || value.status === 'fail')
    && 'owner' in value && (typeof value.owner === 'string' || value.owner === null)
    && (!('error' in value) || typeof value.error === 'string');
}

export const readNight: ReadNight = (runsDir, night) => {
  let content: string;
  try {
    content = readFileSync(join(runsDir, `${night}.jsonl`), 'utf8');
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'ENOENT') return null;
    throw error;
  }

  const result: DigestResult = { rows: [], badLines: 0, counts: { ok: 0, retry: 0, fail: 0 } };
  const jobs = new Map<string, DigestRow>();

  for (const text of content.split('\n')) {
    if (!text.trim()) continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      result.badLines++;
      continue;
    }
    if (!isRunLine(parsed)) {
      result.badLines++;
      continue;
    }

    result.counts[parsed.status]++;
    const row = jobs.get(parsed.job);
    if (row) {
      row.owner = parsed.owner;
      row.runs++;
      row.retries += parsed.status === 'retry' ? 1 : 0;
      row.lastStatus = parsed.status;
      if (parsed.error !== undefined) row.lastError = parsed.error;
      row.lastTime = parsed.at;
    } else {
      jobs.set(parsed.job, {
        job: parsed.job,
        owner: parsed.owner,
        runs: 1,
        retries: parsed.status === 'retry' ? 1 : 0,
        lastStatus: parsed.status,
        lastError: parsed.error ?? null,
        firstTime: parsed.at,
        lastTime: parsed.at,
      });
    }
  }

  result.rows = [...jobs.values()].sort((a, b) => a.job < b.job ? -1 : a.job > b.job ? 1 : 0);
  return result;
};
