#!/usr/bin/env bash
# board-superpowers / check-deps.sh
# Shared by hooks/session-start.sh (Layer 1) and the three skills (Layers 2 & 3).
#
# Detects:
#   - whether superpowers plugin is installed
#   - whether gstack is installed (as a skill or a plugin)
#   - whether the current project's CLAUDE.md has board-superpowers routing
#
# Modes:
#   (default)   — human-readable output; exit 0 if OK, 2 if anything missing
#   --machine   — parseable key=value output; always exits 0; empty when OK
#
# Layers 2 and 3 of the "conspicuous alert" strategy call this in default
# mode and use the exit code to decide whether to stop the flow.

# Self-contained by design: this script is called from the SessionStart
# hook and by skill preflight checks. It deliberately does NOT source
# scripts/lib/common.sh so that a broken or missing lib cannot derail
# dep detection. set -e is also intentionally off — we want to run every
# check even if one sub-command fails transiently.

set -uo pipefail

MODE="${1:-human}"

# Make glob behavior deterministic regardless of caller shopt state.
shopt -s nullglob
shopt -u failglob

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
HOME_DIR="${HOME:-$(cd ~ && pwd)}"

MISSING=()
ROUTING_INJECTED="yes"

# ---- superpowers detection ----------------------------------------------
# superpowers can live in several places depending on install method:
#   1. ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/   (marketplace install)
#   2. ~/.claude/plugins/<id>/                                     (older layout)
#   3. ~/.claude/skills/superpowers/                               (symlinked / manual)
#   4. Anywhere referenced by ~/.claude/settings.json "extraKnownMarketplaces"
# With nullglob on, non-matching globs expand to nothing — we rely on that.

sp_candidates=(
  "$HOME_DIR"/.claude/plugins/cache/*/superpowers/*/skills/using-superpowers
  "$HOME_DIR"/.claude/plugins/cache/*superpowers*/skills/using-superpowers
  "$HOME_DIR"/.claude/plugins/*superpowers*/skills/using-superpowers
  "$HOME_DIR"/.claude/skills/superpowers/skills/using-superpowers
  "$HOME_DIR"/.claude/skills/using-superpowers
  "$HOME_DIR"/.agents/skills/superpowers/using-superpowers
  "$HOME_DIR"/.codex/superpowers/skills/using-superpowers
)

sp_found="no"
if [ "${#sp_candidates[@]}" -gt 0 ]; then
  for candidate in "${sp_candidates[@]}"; do
    if [ -e "$candidate" ]; then
      sp_found="yes"
      break
    fi
  done
fi

[ "$sp_found" = "yes" ] || MISSING+=("superpowers")

# ---- gstack detection ---------------------------------------------------
gs_candidates=(
  "$HOME_DIR"/.claude/skills/gstack
  "$HOME_DIR"/.claude/plugins/cache/*/gstack*
  "$HOME_DIR"/.claude/plugins/*gstack*
  "$PROJECT_DIR"/.claude/skills/gstack
)

gs_found="no"
if [ "${#gs_candidates[@]}" -gt 0 ]; then
  for candidate in "${gs_candidates[@]}"; do
    if [ -e "$candidate" ]; then
      gs_found="yes"
      break
    fi
  done
fi

[ "$gs_found" = "yes" ] || MISSING+=("gstack")

# ---- CLAUDE.md routing marker -------------------------------------------
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  # Marker string: "board-superpowers:routing" somewhere in the file.
  # Project setup writes it into a comment so accidental edits don't drop it.
  if ! grep -q "board-superpowers:routing" "$CLAUDE_MD" 2>/dev/null; then
    ROUTING_INJECTED="no"
  fi
else
  # No CLAUDE.md at all: don't nag users who don't use CLAUDE.md.
  ROUTING_INJECTED="yes"
fi

# ---- output --------------------------------------------------------------
MISSING_CSV=""
if [ "${#MISSING[@]}" -gt 0 ]; then
  MISSING_CSV="$(IFS=,; printf '%s' "${MISSING[*]}")"
fi

if [ "$MODE" = "--machine" ]; then
  # Emit nothing when all is fine so callers can test -z on stdout.
  if [ -n "$MISSING_CSV" ] || [ "$ROUTING_INJECTED" = "no" ]; then
    printf 'MISSING=%s\n' "$MISSING_CSV"
    printf 'ROUTING_INJECTED=%s\n' "$ROUTING_INJECTED"
    printf 'PROJECT=%s\n' "$PROJECT_DIR"
  fi
  exit 0
fi

# Human-readable output.
if [ -z "$MISSING_CSV" ] && [ "$ROUTING_INJECTED" = "yes" ]; then
  printf '✅ board-superpowers: all dependencies present; project routing OK.\n'
  exit 0
fi

{
  printf '╔══════════════════════════════════════════════════════════════╗\n'
  printf '║  ⚠️   board-superpowers PREFLIGHT FAILED                      ║\n'
  printf '╠══════════════════════════════════════════════════════════════╣\n'
  if [ -n "$MISSING_CSV" ]; then
    printf '║  Missing dependencies: %s\n' "$MISSING_CSV"
    printf '║\n'
    for dep in "${MISSING[@]}"; do
      case "$dep" in
        superpowers)
          printf '║  → superpowers\n'
          printf '║    Install: /plugin install superpowers@claude-plugins-official\n'
          ;;
        gstack)
          printf '║  → gstack\n'
          printf '║    Install: cd ~/.claude/skills && \\\n'
          printf '║             git clone https://github.com/garrytan/gstack && \\\n'
          printf '║             cd gstack && ./setup\n'
          ;;
      esac
      printf '║\n'
    done
  fi
  if [ "$ROUTING_INJECTED" = "no" ]; then
    printf '║  Project CLAUDE.md exists but has no board-superpowers\n'
    printf '║  routing block. Use `using-board-superpowers` to add it.\n'
    printf '║\n'
  fi
  printf '╚══════════════════════════════════════════════════════════════╝\n'
}

if [ -n "$MISSING_CSV" ]; then
  exit 2
fi
exit 0
