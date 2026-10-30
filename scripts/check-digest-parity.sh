#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 || ! "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "usage: $0 <YYYY-MM-DD>" >&2
  exit 1
fi
night=$1
mkdir -p var
source scripts/lib-serve.sh
start_server var/digest-parity-serve.log

fetch --fail "$base/digest/$night" --output var/digest-parity.html
fetch --fail "$base/api/digest/$night" --output var/digest-parity.json
node --input-type=module -e '
  import { readFileSync } from "node:fs";
  const html = readFileSync("var/digest-parity.html", "utf8");
  const body = html.match(/<tbody>([\s\S]*?)<\/tbody>/)?.[1];
  if (body === undefined) throw new Error("digest table body not found");
  const entities = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "\u0027" };
  const decode = (text) => text.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi,
    (_, entity) => entity[0] === "#"
      ? String.fromCodePoint(entity[1].toLowerCase() === "x"
        ? parseInt(entity.slice(2), 16) : Number(entity.slice(1)))
      : entities[entity.toLowerCase()]);
  const pageJobs = [...body.matchAll(/<tr\b[^>]*><td>(.*?)<\/td>/g)].map(m => decode(m[1]));
  const digest = JSON.parse(readFileSync("var/digest-parity.json", "utf8"));
  const jsonJobs = digest.rows.map(row => row.job);
  console.log("page jobs:");
  for (const job of pageJobs) console.log(`  ${job}`);
  console.log("JSON jobs:");
  for (const job of jsonJobs) console.log(`  ${job}`);
  const match = JSON.stringify(pageJobs) === JSON.stringify(jsonJobs);
  console.log(match ? "MATCH" : "MISMATCH");
  process.exitCode = match ? 0 : 1;
'
