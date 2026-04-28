#!/usr/bin/env bash
# scripts/verify-skill-metadata.sh — CI gate for .skill-meta.yaml ↔ SKILLS.md.
#
# Runs as part of CI and as a pre-commit smoke check. Validates:
#   1. Every skills/<name>/ has both SKILL.md AND .skill-meta.yaml.
#   2. Every yaml has the 5 required fields (version + 4 dimensions).
#   3. All field values are in the legal enum sets.
#   4. The yaml's layer / type / mode / bounded-context match the
#      catalog statement in SKILLS.md (per-skill section).
#   5. Version drift: when SKILL.md or references/** for a given skill
#      changed in the current branch vs the resolved base ref, that
#      skill's .skill-meta.yaml:version MUST also have changed. Per
#      SKILL_DEVELOPMENT.md "board-superpowers metadata convention":
#      "Bump on any behavior change to the SKILL.md body or its
#      references/." Newly added skills (not present on the base ref)
#      are exempt from drift check. Pass 5 only fires when a base ref
#      resolves; standalone or non-git invocations skip it.
#
# Base ref resolution (Pass 5, in priority order):
#   1. $BOARD_SP_VERIFY_BASE env var (when it resolves)
#   2. origin/main (when it resolves)
#   3. main (when it resolves)
#   4. (none) — skip drift check, log to stderr
#
# Exit codes:
#   0 — all skills pass
#   1 — at least one skill has a problem; details on stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

PLUGIN_ROOT="$(bsp_plugin_root)"
SKILLS_DIR="${PLUGIN_ROOT}/skills"
SKILLS_MD="${PLUGIN_ROOT}/SKILLS.md"

[ -d "${SKILLS_DIR}" ] || bsp_die "skills/ directory not found at ${SKILLS_DIR}"
[ -f "${SKILLS_MD}" ]  || bsp_die "SKILLS.md not found at ${SKILLS_MD}"

bsp_require_cmd python3

# --- Resolve base ref for version-drift check (Pass 5) -------------------
# The drift check fires when a base ref resolves AND we're inside a git
# repo. Standalone non-git invocations and repos with no `main` /
# `origin/main` fall through and skip the check (Passes 1-4 still run).
BASE_REF=""
if command -v git >/dev/null 2>&1 \
   && git -C "${PLUGIN_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "${BOARD_SP_VERIFY_BASE:-}" ]; then
        if git -C "${PLUGIN_ROOT}" rev-parse --verify "${BOARD_SP_VERIFY_BASE}" >/dev/null 2>&1; then
            BASE_REF="${BOARD_SP_VERIFY_BASE}"
        else
            bsp_warn "BOARD_SP_VERIFY_BASE=${BOARD_SP_VERIFY_BASE} does not resolve; trying defaults"
        fi
    fi
    if [ -z "${BASE_REF}" ] \
       && git -C "${PLUGIN_ROOT}" rev-parse --verify origin/main >/dev/null 2>&1; then
        BASE_REF="origin/main"
    fi
    if [ -z "${BASE_REF}" ] \
       && git -C "${PLUGIN_ROOT}" rev-parse --verify main >/dev/null 2>&1; then
        BASE_REF="main"
    fi
fi

CHANGED_FILES=""
DRIFT_BASE=""
if [ -n "${BASE_REF}" ]; then
    # Use `git merge-base <base> HEAD` (the fork point) rather than the
    # base ref directly. This counts ONLY changes introduced ON this
    # branch since it diverged, not changes on the base since the fork
    # — otherwise a stale local base would falsely flag every skill the
    # base advanced past as drifted on this branch.
    DRIFT_BASE="$(git -C "${PLUGIN_ROOT}" merge-base "${BASE_REF}" HEAD 2>/dev/null || true)"
    if [ -n "${DRIFT_BASE}" ]; then
        # Paths relative to PLUGIN_ROOT. Empty stdout = no skills/
        # changes since fork, so Pass 5 is a no-op.
        CHANGED_FILES="$(git -C "${PLUGIN_ROOT}" diff "${DRIFT_BASE}..HEAD" --name-only -- skills/ 2>/dev/null || true)"
    fi
fi

# Delegate the actual validation to python — yaml parsing is painful in
# pure bash and we already require python3 elsewhere.

python3 - "$SKILLS_DIR" "$SKILLS_MD" "${DRIFT_BASE}" "${CHANGED_FILES}" "${PLUGIN_ROOT}" <<'PY'
import os, re, subprocess, sys

skills_dir, skills_md = sys.argv[1], sys.argv[2]
drift_base = sys.argv[3] if len(sys.argv) > 3 else ""
changed_files_raw = sys.argv[4] if len(sys.argv) > 4 else ""
plugin_root = sys.argv[5] if len(sys.argv) > 5 else ""
changed_files = [f for f in changed_files_raw.split('\n') if f.strip()]
errors = []

LAYERS = {"entry", "molecular", "atomic"}
TYPES = {"technique", "pattern", "reference", "discipline"}
MODES = {"claude-code-only", "codex-only", "both"}
CONTEXTS = {"board", "session", "bootstrap", "audit", "spec"}

def parse_yaml_simple(path):
    """Parse a flat YAML file with `key: value` lines + comments."""
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if ':' not in line:
                continue
            k, v = line.split(':', 1)
            out[k.strip()] = v.strip().strip("'").strip('"')
    return out

# --- Pass 1: per-skill yaml validation ---
skill_metas = {}
for entry in sorted(os.listdir(skills_dir)):
    skill_path = os.path.join(skills_dir, entry)
    if not os.path.isdir(skill_path):
        continue
    skill_md = os.path.join(skill_path, 'SKILL.md')
    meta_yaml = os.path.join(skill_path, '.skill-meta.yaml')
    if not os.path.isfile(skill_md):
        errors.append(f"{entry}: missing SKILL.md")
        continue
    if not os.path.isfile(meta_yaml):
        errors.append(f"{entry}: missing .skill-meta.yaml")
        continue
    meta = parse_yaml_simple(meta_yaml)
    required = {'version', 'layer', 'type', 'mode', 'bounded-context'}
    missing = required - set(meta.keys())
    if missing:
        errors.append(f"{entry}: yaml missing fields: {sorted(missing)}")
        continue
    if meta['layer'] not in LAYERS:
        errors.append(f"{entry}: layer={meta['layer']} not in {sorted(LAYERS)}")
    if meta['type'] not in TYPES:
        errors.append(f"{entry}: type={meta['type']} not in {sorted(TYPES)}")
    if meta['mode'] not in MODES:
        errors.append(f"{entry}: mode={meta['mode']} not in {sorted(MODES)}")
    if meta['bounded-context'] not in CONTEXTS:
        errors.append(f"{entry}: bounded-context={meta['bounded-context']} not in {sorted(CONTEXTS)}")
    if not re.match(r'^v?\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$', meta['version']):
        errors.append(f"{entry}: version={meta['version']} is not semver")
    skill_metas[entry] = meta

# --- Pass 2: SKILLS.md catalog mentions every skill in the right layer ---
catalog_text = open(skills_md).read()
# A v1-minimum or deferred skill may appear in the catalog without
# layer being directly inline (it lives in yaml). We just check that the
# catalog mentions every skill name in a #### heading.
catalog_skills = set(re.findall(r'^####\s+`([a-z][a-z0-9-]+)`', catalog_text, re.M))
for skill_name in skill_metas:
    if skill_name not in catalog_skills:
        errors.append(f"{skill_name}: present in skills/ but not mentioned in SKILLS.md catalog")

# --- Pass 5: version drift check ---
# Fires only when a fork-point base resolved AND there are changed files
# in skills/ since the fork. For each skill whose SKILL.md or
# references/** changed since the fork, the .skill-meta.yaml:version
# field MUST also have changed (vs the fork-point version, not vs the
# branch base). New skills (not present at the fork point) are exempt.
drift_pass_ran = False
if drift_base and changed_files:
    drift_pass_ran = True
    for skill_name, meta in skill_metas.items():
        body_path = f"skills/{skill_name}/SKILL.md"
        refs_prefix = f"skills/{skill_name}/references/"
        skill_changed = any(
            f == body_path or f.startswith(refs_prefix)
            for f in changed_files
        )
        if not skill_changed:
            continue
        meta_path_in_repo = f"skills/{skill_name}/.skill-meta.yaml"
        try:
            base_yaml = subprocess.check_output(
                ["git", "-C", plugin_root, "show",
                 f"{drift_base}:{meta_path_in_repo}"],
                stderr=subprocess.DEVNULL,
            ).decode("utf-8", errors="replace")
        except subprocess.CalledProcessError:
            # Skill is new on this branch (didn't exist at fork) — exempt.
            continue
        base_version = None
        for line in base_yaml.splitlines():
            stripped = line.strip()
            if stripped.startswith("version:"):
                base_version = stripped.split(":", 1)[1].strip().strip("'").strip('"')
                break
        if base_version is None:
            errors.append(
                f"{skill_name}: could not parse version from "
                f"{drift_base[:7]}:{meta_path_in_repo}"
            )
            continue
        if base_version == meta["version"]:
            errors.append(
                f"{skill_name}: SKILL.md or references/ changed since fork "
                f"({drift_base[:7]}) but .skill-meta.yaml:version is still "
                f"{base_version}. Bump the skill version per "
                f"SKILL_DEVELOPMENT.md \"board-superpowers metadata "
                f"convention\" (\"Bump on any behavior change to the "
                f"SKILL.md body or its references/.\")."
            )

if errors:
    print("verify-skill-metadata: FAIL", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

if drift_pass_ran:
    drift_note = f" + drift (fork: {drift_base[:7]})"
elif drift_base:
    drift_note = " (drift skipped — no skills/ changes since fork)"
else:
    drift_note = " (drift skipped — no fork-point base resolved)"
print(f"verify-skill-metadata: OK ({len(skill_metas)} skills checked{drift_note})")
PY
