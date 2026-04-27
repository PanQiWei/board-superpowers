#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPREPO="$(mktemp -d)"
trap 'rm -rf "${TMPREPO}"' EXIT
mkdir -p "${TMPREPO}/.board-superpowers/.venv/bin"
# Stub a python3 executable.
cat > "${TMPREPO}/.board-superpowers/.venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMPREPO}/.board-superpowers/.venv/bin/python3"

source "${SCRIPT_DIR}/scripts/lib/common.sh"
out="$(bsp_ensure_venv "${TMPREPO}")"
[ "${out}" = "${TMPREPO}/.board-superpowers/.venv/bin/python3" ] || { echo "FAIL: wrong path: ${out}"; exit 1; }
echo "PASS"
