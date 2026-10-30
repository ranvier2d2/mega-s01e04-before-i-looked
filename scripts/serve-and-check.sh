#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p var

server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill -TERM -- "-$server_pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 20; attempt++)); do
      kill -0 -- "-$server_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL -- "-$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

port=$(node --input-type=module -e '
  import { createServer } from "node:net";
  const server = createServer();
  server.listen(0, "127.0.0.1", () => {
    console.log(server.address().port);
    server.close();
  });
  setTimeout(() => process.exit(1), 2000).unref();
')
base="http://127.0.0.1:$port"
# Give pnpm and all its descendants their own process group for reliable cleanup.
set -m
PORT="$port" pnpm start >var/serve.log 2>&1 &
server_pid=$!
set +m

ready=false
deadline=$((SECONDS + 20))
while ((SECONDS < deadline)); do
  if curl --silent --fail --connect-timeout 1 --max-time 1 "$base/health" >/dev/null; then
    ready=true
    break
  fi
  kill -0 "$server_pid" 2>/dev/null || break
  sleep 0.1
done
if [[ "$ready" != true ]]; then
  echo 'FAIL /health ready within 20 s'
  exit 1
fi

fetch() {
  curl --silent --show-error --path-as-is --connect-timeout 1 --max-time 5 "$@"
}

check_digest_status() {
  local status
  status=$(fetch --output var/digest-check.html --write-out '%{http_code}' "$base/digest/2026-10-28") || return 1
  [[ "$status" == 200 ]]
}

check_job_order() {
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const html = readFileSync("var/digest-check.html", "utf8");
    const tables = [...html.matchAll(/<table\b[^>]*>/g)];
    const body = html.match(/<tbody>([\s\S]*?)<\/tbody>/)?.[1] ?? "";
    const jobs = [...body.matchAll(/<tr\b[^>]*><td>(.*?)<\/td>/g)].map(m => m[1]);
    const expected = ["digest/render", "fixtures/refresh", "lane/sync", "notes/backup", "rig/rotate-logs"];
    process.exit(tables.length === 1 && JSON.stringify(jobs) === JSON.stringify(expected) ? 0 : 1);
  '
}

check_warn_rows() {
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const html = readFileSync("var/digest-check.html", "utf8");
    const rows = [...html.matchAll(/<tr\b([^>]*)><td>(.*?)<\/td>/g)];
    const expected = ["fixtures/refresh", "notes/backup"];
    process.exit(rows.length === 5 && rows.every(([, attrs, job]) =>
      /\bclass="warn"/.test(attrs) === expected.includes(job)) ? 0 : 1);
  '
}

check_missing_owner() {
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const html = readFileSync("var/digest-check.html", "utf8");
    process.exit(/<tr\b[^>]*><td>digest\/render<\/td><td>—<\/td>/.test(html) ? 0 : 1);
  '
}

check_not_found() {
  local missing traversal
  missing=$(fetch --output /dev/null --write-out '%{http_code}' "$base/digest/2000-01-01") || return 1
  traversal=$(fetch --output /dev/null --write-out '%{http_code}' "$base/digest/..%2Fpackage") || return 1
  [[ "$missing" == 404 && "$traversal" == 404 ]]
}

failed=0
check() {
  local label=$1
  shift
  if "$@"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label"
    failed=1
  fi
}

check '/digest/2026-10-28 is 200' check_digest_status
check 'one table with five jobs in reader order' check_job_order
check 'only fixtures/refresh and notes/backup are warn' check_warn_rows
check 'digest/render owner is —' check_missing_owner
check 'missing night and encoded traversal are 404' check_not_found
exit "$failed"
