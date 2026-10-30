#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

no_marker=false
if [[ ${1-} == --no-marker ]]; then
  no_marker=true
  shift
fi
if [[ $# != 2 || ! "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "usage: $0 [--no-marker] <YYYY-MM-DD> <var/out-file>" >&2
  exit 1
fi
night=$1
# Resolve existing ancestors too: neither .. nor a symlink may escape var/.
out_file=$(node --input-type=module - "$2" <<'NODE'
import { existsSync, realpathSync, lstatSync } from 'node:fs';
import { resolve, dirname, relative, isAbsolute } from 'node:path';
const root = resolve('var');
const output = resolve(process.argv[2]);
const inside = (path) => {
  const rel = relative(root, path);
  return rel !== '' && rel !== '..' && !rel.startsWith('../') && !isAbsolute(rel);
};
try {
  if (!inside(output)) throw new Error();
  let ancestor = output;
  while (!existsSync(ancestor)) {
    // Reject dangling symlinks rather than following them on write.
    try { if (lstatSync(ancestor).isSymbolicLink()) throw new Error(); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    ancestor = dirname(ancestor);
  }
  const actual = realpathSync(ancestor);
  if (actual !== ancestor && actual !== root && !inside(actual)) throw new Error();
  if (existsSync(root) && realpathSync(root) !== root) throw new Error();
  console.log(output);
} catch {
  console.error('FAIL output file must stay under var/ (no escaping symlinks)');
  process.exit(1);
}
NODE
)
mkdir -p "$(dirname "$out_file")"
source scripts/lib-serve.sh
if [[ "$no_marker" == true ]]; then
  # An explicitly empty environment value overrides Node's .env loading.
  export LANE_MARKER=''
fi
start_server var/save-preview-serve.log
http_status=000
curl_status=0
http_status=$(fetch --output "$out_file" --write-out '%{http_code}' "$base/digest/$night") || curl_status=$?
cleanup
server_pid=''

node --input-type=module - "$out_file" "$http_status" "$curl_status" "$no_marker" <<'NODE'
import { readFileSync } from 'node:fs';
const [file, status, curlStatus, noMarker] = process.argv.slice(2);
let failed = false;
function check(label, ok) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label}`);
  if (!ok) failed = true;
}
check('HTTP 200', status === '200' && curlStatus === '0');
let html = '';
try { html = readFileSync(file, 'utf8'); }
catch { failed = true; }
const banner = html.match(/<([a-z][\w:-]*)\b[^>]*\bclass="marker"[^>]*>([\s\S]*?)<\/\1\s*>/i);
check('lane banner (class="marker")', Boolean(banner));
const scripts = (html.match(/<script/gi) ?? []).length;
check(`<script count: ${scripts}`, scripts === 0);
// Inspect attributes only inside tags, including quoted and unquoted values.
const external = [...html.matchAll(/<[a-z][^>]*>/gi)].flatMap(([tag]) =>
  [...tag.matchAll(/\s(?:src|href)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi)]
    .filter((m) => /^(?:https?:|\/)/i.test((m[1] ?? m[2] ?? m[3]).trim())));
check(`external asset references: ${external.length}`, external.length === 0);
const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const marker = (banner?.[2] ?? '').replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi,
  (whole, entity) => {
    if (entity[0] !== '#') return entities[entity.toLowerCase()];
    const code = entity[1].toLowerCase() === 'x'
      ? parseInt(entity.slice(2), 16) : Number(entity.slice(1));
    return code <= 0x10ffff ? String.fromCodePoint(code) : whole;
  });
console.log(`marker: ${marker}`);
if (noMarker === 'true') check('banner reads "no marker set"', marker === 'no marker set');
process.exitCode = failed ? 1 : 0;
NODE
