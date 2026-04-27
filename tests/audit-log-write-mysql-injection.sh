#!/usr/bin/env bash
set -euo pipefail
# Skip if mysql client is not installed locally (typical CI scenario).
command -v mysql >/dev/null 2>&1 || { echo "SKIP: mysql client not installed"; exit 0; }
# Real test would need a mysql instance; locally architect runs against
# a Docker-spawned mysql or skip. Stub for PR CI:
echo "SKIP: integration test (manual run with: docker run mysql:8 + connect string)"
exit 0
