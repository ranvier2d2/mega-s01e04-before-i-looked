export type DigestRow = {
  job: string;
  // Keep rows whose owner is missing.
  owner: string | null;
  runs: number;
  retries: number;
  lastStatus: 'ok' | 'retry' | 'fail';
  lastError: string | null;
  // Preserve the log's original offset; do not convert these times.
  firstTime: string;
  lastTime: string;
};

export type DigestResult = {
  rows: DigestRow[];
  badLines: number;
};

// readNight returns null for a missing file; an empty file has no rows or bad lines.
export type ReadNight = (runsDir: string, night: string) => DigestResult | null;
