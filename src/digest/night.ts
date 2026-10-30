import { readNight } from './read.js';
import type { ReadNight } from './types.js';

// Both routes share the night boundary and missing-file behavior.
export const readDigest: ReadNight = (runsDir, night) => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(night)) return null;
  return readNight(runsDir, night);
};
