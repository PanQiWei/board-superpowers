#!/usr/bin/env bash
# board-superpowers / SessionStart hook
# Purpose: early-warning layer for missing dependencies and first-time
# project setup.
#
# This is Layer 1 of 3 ("conspicuous missing-dep alert"). Layer 2 (the
# using-board-superpowers skill) and Layer 3 (just-in-time checks in each
# skill) are the actual safety net — this hook is best-effort only, because
# Claude Code's SessionStart hooks have several known delivery bugs.
#
# Strategy: emit a JSON object on stdout whose hookSpecificOutput.additionalContext
# field contains <board-superpowers-*> tagged instructions. The model is told
# to reproduce a fenced banner verbatim on its first reply — that is how we
# achieve "conspicuous" given that additionalContext is invisible to the user.
#
# Self-contained by design: this hook does NOT source scripts/lib/common.sh
# so that a broken or missing lib cannot prevent Claude Code startup.

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# check-deps.sh reads CLAUDE_PROJECT_DIR directly — we don't need to propagate.

CHECK_SCRIPT=""
if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/scripts/check-deps.sh" ]; then
  CHECK_SCRIPT="$PLUGIN_ROOT/scripts/check-deps.sh"
fi

# Can't locate our own scripts — silently no-op. Skill-level checks cover.
[ -n "$CHECK_SCRIPT" ] || exit 0

# Run the check and capture machine-readable output.
CHECK_OUTPUT="$(bash "$CHECK_SCRIPT" --machine 2>/dev/null || true)"
[ -n "$CHECK_OUTPUT" ] || exit 0

MISSING=""
ROUTING_INJECTED=""
while IFS= read -r line; do
  case "$line" in
    MISSING=*)          MISSING="${line#MISSING=}" ;;
    ROUTING_INJECTED=*) ROUTING_INJECTED="${line#ROUTING_INJECTED=}" ;;
  esac
done <<< "$CHECK_OUTPUT"

# Sanitize dep names before interpolation. Unknown names still pass through
# but the character set is clamped so a rogue check-deps output cannot
# inject markup/prompt content into the model's context. A name that has
# zero alphanumeric content after clamping is dropped entirely.
sanitize_dep_name() {
  local s
  s="$(printf '%s' "$1" | LC_ALL=C tr -c 'a-zA-Z0-9_-' '-' | cut -c1-32)"
  case "$s" in
    *[a-zA-Z0-9]*) printf '%s' "$s" ;;
    *)             printf '' ;;
  esac
}

PAYLOAD=""

# Sanitize every known dep up-front, then rebuild MISSING from the cleaned
# values. All downstream interpolation — title line, bullets, install cmds —
# is guaranteed to see the sanitized form.
SANITIZED_DEPS=()
if [ -n "$MISSING" ]; then
  IFS=',' read -ra RAW_DEPS <<< "$MISSING"
  for dep in "${RAW_DEPS[@]}"; do
    [ -n "$dep" ] || continue
    dep_clean="$(sanitize_dep_name "$dep")"
    [ -n "$dep_clean" ] || continue
    SANITIZED_DEPS+=("$dep_clean")
  done
  if [ "${#SANITIZED_DEPS[@]}" -gt 0 ]; then
    MISSING="$(IFS=,; printf '%s' "${SANITIZED_DEPS[*]}")"
  else
    MISSING=""
  fi
fi

if [ -n "$MISSING" ]; then
  BULLETS=""
  INSTALL_CMDS=""
  for dep_clean in "${SANITIZED_DEPS[@]}"; do
    case "$dep_clean" in
      superpowers)
        BULLETS="${BULLETS}    • superpowers"$'\n'
        INSTALL_CMDS="${INSTALL_CMDS}    /plugin install superpowers@claude-plugins-official"$'\n'
        ;;
      gstack)
        BULLETS="${BULLETS}    • gstack"$'\n'
        INSTALL_CMDS="${INSTALL_CMDS}    cd ~/.claude/skills && git clone https://github.com/garrytan/gstack && cd gstack && ./setup"$'\n'
        ;;
      *)
        BULLETS="${BULLETS}    • ${dep_clean}"$'\n'
        ;;
    esac
  done

  BULLETS_TRIMMED="${BULLETS%$'\n'}"
  INSTALL_CMDS_TRIMMED="${INSTALL_CMDS%$'\n'}"

  PAYLOAD="${PAYLOAD}<board-superpowers-dep-alert priority=\"CRITICAL\">
⚠️ board-superpowers DEPENDENCY MISSING: ${MISSING}

Your VERY FIRST response to the user in this session MUST begin with the
banner below, reproduced VERBATIM inside a fenced code block so it renders
conspicuously. Do this BEFORE answering any question, BEFORE invoking any
skill, BEFORE any other text.

\`\`\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚠️   board-superpowers — MISSING DEPENDENCIES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  The following required plugins are NOT installed:

${BULLETS_TRIMMED}

  Install them first:

${INSTALL_CMDS_TRIMMED}

  Without them, board-superpowers workflows will break mid-flow:
  it delegates design work to superpowers:brainstorming /
  gstack:/office-hours, execution to
  superpowers:subagent-driven-development, and PR creation to
  superpowers:finishing-a-development-branch / gstack:/ship.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
\`\`\`

After the banner, you may still answer the user's current question, but
if fulfilling their request would require the missing plugin(s), stop
and ask them to install first. Do NOT invoke any board-superpowers skill
until dependencies are resolved — those skills will refuse to run anyway.

Do not silently skip the banner. Do not paraphrase it. Do not explain
your way out of displaying it. The user has opted into this alert by
installing board-superpowers.
</board-superpowers-dep-alert>
"
fi

if [ "$ROUTING_INJECTED" = "no" ]; then
  PAYLOAD="${PAYLOAD}<board-superpowers-setup-nudge>
This project's CLAUDE.md does not yet contain board-superpowers routing
rules. On your FIRST opportunity (e.g., when the user's request is
board-related, or at the end of your first response if the request was
unrelated), ask the user:

    \"I notice board-superpowers isn't wired into this project's
    CLAUDE.md yet. Want me to add the routing block (~15 lines)? This
    lets any future session know whether it's a Board Manager or a
    Board Consumer. One-time setup.\"

If the user says yes, invoke the skill \`using-board-superpowers\` and
follow its \"Project setup\" section. Do not add the block without
explicit consent.
</board-superpowers-setup-nudge>
"
fi

[ -n "$PAYLOAD" ] || exit 0

# Pure-bash JSON string escaper (RFC 8259 §7). No external dependency.
# Order matters — backslash must be substituted FIRST, otherwise the
# escapes we introduce below get double-escaped.
json_escape_string() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
  # Strip any remaining ASCII control chars (U+0000–U+001F, except HT/LF/CR
  # which were already replaced). Our templates don't produce them; this is
  # defense-in-depth against a rogue check-deps output.
  s="$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\016-\037')"
  printf '"%s"' "$s"
}

ESCAPED="$(json_escape_string "$PAYLOAD")"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
  "$ESCAPED"
exit 0
