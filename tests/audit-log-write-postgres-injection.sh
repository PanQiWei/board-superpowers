#!/usr/bin/env bash
set -euo pipefail
command -v psql >/dev/null 2>&1 || { echo "SKIP: psql client not installed"; exit 0; }
echo "SKIP: integration test (manual run with: docker run postgres + connect string)"
exit 0
