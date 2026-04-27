#!/usr/bin/env bash
# tests/manifest-migration-v1-to-v2.sh — verify bootstrap-host.sh migrates
# a v1 manifest (schema_version: 1) to v2 (schema_version: 2 + uv_version).
#
# Test isolation: uses TMPHOME so the real ~/.board-superpowers/manifest.yml
# is never touched. trap cleanup removes TMPHOME on exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPHOME="$(mktemp -d)"
trap 'rm -rf "${TMPHOME}"' EXIT

# Pre-existing v1 manifest (legacy format).
mkdir -p "${TMPHOME}/.board-superpowers"
cat > "${TMPHOME}/.board-superpowers/manifest.yml" <<'EOF'
schema_version: 1
host_bootstrapped_at: "2026-04-26T10:30:00Z"
last_seen_version: "0.2.0"
EOF

env HOME="${TMPHOME}" CLAUDE_PLUGIN_ROOT="${SCRIPT_DIR}" \
    bash "${SCRIPT_DIR}/scripts/bootstrap-host.sh"

# Verify migrated.
SCHEMA_VER=$(grep '^schema_version:' "${TMPHOME}/.board-superpowers/manifest.yml" | sed -E 's/^schema_version:[[:space:]]*//')
[ "${SCHEMA_VER}" = "2" ] || { echo "FAIL: schema_version=${SCHEMA_VER}"; exit 1; }

UV_VER=$(grep '^uv_version:' "${TMPHOME}/.board-superpowers/manifest.yml" | sed -E 's/^uv_version:[[:space:]]*"?([^"]+)"?.*/\1/')
[ -n "${UV_VER}" ] || { echo "FAIL: uv_version not recorded"; exit 1; }

echo "PASS: schema_version=2, uv_version=${UV_VER}"
