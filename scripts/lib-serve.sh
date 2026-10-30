#!/usr/bin/env bash
# Source from the repository root, then call start_server <log>.

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

start_server() {
  local port ready deadline
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
  PORT="$port" pnpm start >"$1" 2>&1 &
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
    return 1
  fi
}

fetch() {
  curl --silent --show-error --path-as-is --connect-timeout 1 --max-time 5 "$@"
}
