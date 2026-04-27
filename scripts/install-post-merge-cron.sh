#!/usr/bin/env bash
# scripts/install-post-merge-cron.sh — install a recurring post-merge
# cleanup job for a board-superpowers claim card.
#
# On macOS: writes a LaunchAgent plist and loads it via launchctl.
# On Linux: appends a crontab entry wrapped in marker comments.
#
# The installed job calls post-merge-cleanup.sh periodically until the
# PR reaches a terminal state (MERGED or CLOSED), then uninstalls itself.
#
# Args:
#   --card <N>                      required  card number
#   --owner <owner>                 required  GitHub org / user
#   --poll-interval-minutes <N>     optional  default 15
#   --timeout-hours <N>             optional  default 48
#
# Exit codes:
#   0 — installed (or already installed + replaced)
#   1 — bad args / unsupported platform / installation failure

set -euo pipefail

# Re-derive PATH defensively (called from skill, not necessarily a login shell).
# Caller PATH is preserved first so test PATH-shims take precedence.
PATH="${PATH:+${PATH}:}/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

# --- macOS launchd installation --------------------------------------------

_install_launchd() {
    local card="$1"
    local owner="$2"
    local poll_minutes="$3"
    local timeout_hours="$4"
    local cleanup_script="$5"

    bsp_require_cmd launchctl "Install via Xcode Command Line Tools (macOS built-in)"

    local label="com.board-superpowers.post-merge-${owner}-${card}"
    local plist_dir="${HOME}/Library/LaunchAgents"
    local plist_path="${plist_dir}/${label}.plist"
    local start_interval=$(( poll_minutes * 60 ))
    local install_ts
    install_ts="$(date +%s)"
    local timeout_seconds=$(( timeout_hours * 3600 ))

    mkdir -p "${plist_dir}"

    # Unload existing entry idempotently (ignore errors — may not be loaded).
    launchctl unload "${plist_path}" 2>/dev/null || true

    # Ensure log dir exists.
    mkdir -p "${HOME}/.board-superpowers/logs"

    # Write plist. The ProgramArguments shell command self-uninstalls the
    # plist on terminal-state exit (0=MERGED cleanup done, 3=CLOSED no-merge)
    # and when the timeout has elapsed.
    cat > "${plist_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>now=\$(date +%s); if [ \$(( now - ${install_ts} )) -gt ${timeout_seconds} ]; then launchctl unload '${plist_path}' 2>/dev/null; exit 0; fi; PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:\${PATH:-}" bash '${cleanup_script}' --card '${card}' --owner '${owner}'; rc=\$?; if [ \$rc -eq 0 ] || [ \$rc -eq 3 ]; then launchctl unload '${plist_path}' 2>/dev/null; fi</string>
    </array>
    <key>StartInterval</key>
    <integer>${start_interval}</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${HOME}/.board-superpowers/logs/post-merge-${owner}-${card}.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.board-superpowers/logs/post-merge-${owner}-${card}.err</string>
</dict>
</plist>
PLIST

    # Load the new plist.
    launchctl load "${plist_path}"

    bsp_log "installed launchd job: ${label}"
    bsp_log "plist: ${plist_path}"
    bsp_log "poll interval: ${poll_minutes} minutes"
    bsp_log "timeout: ${timeout_hours} hours"
    bsp_log ""
    bsp_log "To manually uninstall:"
    bsp_log "  launchctl unload '${plist_path}'"
    bsp_log "  rm '${plist_path}'"
}

# --- Linux cron installation -----------------------------------------------

_install_cron() {
    local card="$1"
    local owner="$2"
    local poll_minutes="$3"
    local timeout_hours="$4"
    local cleanup_script="$5"

    bsp_require_cmd crontab "install via your package manager (e.g. 'apt install cron')"

    local marker_start="# board-superpowers post-merge card-${card} START"
    local marker_end="# board-superpowers post-merge card-${card} END"
    local install_ts
    install_ts="$(date +%s)"
    local timeout_seconds=$(( timeout_hours * 3600 ))

    # The cron entry wraps the cleanup call with self-removal logic on
    # terminal exit codes (0=done, 3=closed-no-merge) and timeout.
    # Escape single quotes are not needed because we embed via heredoc
    # expansion; the crontab entry itself uses only double-quoted strings.
    local cron_cmd
    cron_cmd="now=\$(date +%s); if [ \$(( now - ${install_ts} )) -gt ${timeout_seconds} ]; then (crontab -l 2>/dev/null | grep -v '${marker_start}' | grep -v '${marker_end}' | crontab -); exit 0; fi; PATH=\"/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:\${PATH:-}\" bash '${cleanup_script}' --card '${card}' --owner '${owner}'; rc=\$?; if [ \$rc -eq 0 ] || [ \$rc -eq 3 ]; then (crontab -l 2>/dev/null | grep -v '${marker_start}' | grep -v '${marker_end}' | crontab -); fi"
    local cron_entry="*/${poll_minutes} * * * * ${cron_cmd}"

    # Strip existing marker block if present (idempotent replacement).
    local existing_crontab
    existing_crontab="$(crontab -l 2>/dev/null || true)"

    local stripped_crontab=""
    local in_block=0
    while IFS= read -r line || [ -n "${line}" ]; do
        case "${line}" in
            "${marker_start}") in_block=1 ;;
            "${marker_end}")   in_block=0 ;;
            *)
                if [ "${in_block}" -eq 0 ]; then
                    stripped_crontab="${stripped_crontab}${line}
"
                fi
                ;;
        esac
    done <<EOF
${existing_crontab}
EOF

    # Append new entry with markers.
    local new_crontab="${stripped_crontab}${marker_start}
${cron_entry}
${marker_end}
"

    printf '%s' "${new_crontab}" | crontab -

    bsp_log "installed cron entry for card #${card} (owner ${owner})"
    bsp_log "poll interval: ${poll_minutes} minutes"
    bsp_log "timeout: ${timeout_hours} hours"
    bsp_log ""
    bsp_log "To manually uninstall:"
    bsp_log "  (crontab -l 2>/dev/null | grep -v '${marker_start}' | grep -v '${marker_end}' | crontab -)"
}

# --- Argument parsing -------------------------------------------------------

CARD=""
OWNER=""
POLL_INTERVAL_MINUTES="15"
TIMEOUT_HOURS="48"

while [ $# -gt 0 ]; do
    case "$1" in
        --card)                   CARD="$2";                  shift 2 ;;
        --owner)                  OWNER="$2";                 shift 2 ;;
        --poll-interval-minutes)  POLL_INTERVAL_MINUTES="$2"; shift 2 ;;
        --timeout-hours)          TIMEOUT_HOURS="$2";         shift 2 ;;
        *) bsp_die "unknown argument: $1" ;;
    esac
done

[ -n "${CARD}" ]  || bsp_die "missing required --card <N>"
[ -n "${OWNER}" ] || bsp_die "missing required --owner <github-owner>"

# Validate numeric args.
case "${POLL_INTERVAL_MINUTES}" in
    *[!0-9]*) bsp_die "--poll-interval-minutes must be a positive integer" ;;
esac
case "${TIMEOUT_HOURS}" in
    *[!0-9]*) bsp_die "--timeout-hours must be a positive integer" ;;
esac

PLUGIN_ROOT="$(bsp_plugin_root)"
CLEANUP_SCRIPT="${PLUGIN_ROOT}/scripts/post-merge-cleanup.sh"

[ -f "${CLEANUP_SCRIPT}" ] || bsp_die "cleanup script not found: ${CLEANUP_SCRIPT}"

# --- Platform dispatch ------------------------------------------------------

PLATFORM="$(uname -s)"

case "${PLATFORM}" in
    Darwin)
        _install_launchd \
            "${CARD}" "${OWNER}" \
            "${POLL_INTERVAL_MINUTES}" "${TIMEOUT_HOURS}" \
            "${CLEANUP_SCRIPT}"
        ;;
    Linux)
        _install_cron \
            "${CARD}" "${OWNER}" \
            "${POLL_INTERVAL_MINUTES}" "${TIMEOUT_HOURS}" \
            "${CLEANUP_SCRIPT}"
        ;;
    *)
        bsp_die "unsupported platform: ${PLATFORM}. Only Darwin (macOS) and Linux are supported."
        ;;
esac

exit 0
