#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p var

source scripts/lib-serve.sh
start_server var/serve.log

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

check_board_links() {
  fetch --fail --output var/board-links-check.html "$base/" || return 1
  node --input-type=module -e '
    import { readFileSync } from "node:fs";
    const html = readFileSync("var/board-links-check.html", "utf8");
    const items = [...html.matchAll(/<li>([\s\S]*?)<\/li>/g)].map(m => m[1]);
    const expected = [
      ["2026-10-28", "ok 10 / retry 4 / fail 1"],
      ["2026-10-27", "ok 7 / retry 0 / fail 0"],
    ];
    const positions = expected.map(([night, counts]) => items.indexOf(
      `<a href="/digest/${night}">${night}</a> · ${counts}`));
    process.exit(positions.every(i => i >= 0) && positions[0] < positions[1] ? 0 : 1);
  ' || return 1
  local night status
  for night in 2026-10-28 2026-10-27; do
    status=$(fetch --output /dev/null --write-out '%{http_code}' "$base/digest/$night") || return 1
    [[ "$status" == 200 ]] || return 1
  done
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
check 'board links both nights newest first with counts; both digests are 200' check_board_links
exit "$failed"
