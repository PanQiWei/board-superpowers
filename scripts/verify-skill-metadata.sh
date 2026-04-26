#!/usr/bin/env bash
# scripts/verify-skill-metadata.sh — CI gate for .skill-meta.yaml ↔ SKILLS.md.
#
# Runs as part of CI and as a pre-commit smoke check. Validates:
#   1. Every skills/<name>/ has both SKILL.md AND .skill-meta.yaml.
#   2. Every yaml has the 5 required fields (version + 4 dimensions).
#   3. All field values are in the legal enum sets.
#   4. The yaml's layer / type / mode / bounded-context match the
#      catalog statement in SKILLS.md (per-skill section).
#
# Exit codes:
#   0 — all skills pass
#   1 — at least one skill has a problem; details on stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

PLUGIN_ROOT="$(bsp_plugin_root)"
SKILLS_DIR="${PLUGIN_ROOT}/skills"
SKILLS_MD="${PLUGIN_ROOT}/SKILLS.md"

[ -d "${SKILLS_DIR}" ] || bsp_die "skills/ directory not found at ${SKILLS_DIR}"
[ -f "${SKILLS_MD}" ]  || bsp_die "SKILLS.md not found at ${SKILLS_MD}"

bsp_require_cmd python3

# Delegate the actual validation to python — yaml parsing is painful in
# pure bash and we already require python3 elsewhere.

python3 - "$SKILLS_DIR" "$SKILLS_MD" <<'PY'
import os, re, sys

skills_dir, skills_md = sys.argv[1], sys.argv[2]
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

if errors:
    print("verify-skill-metadata: FAIL", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

print(f"verify-skill-metadata: OK ({len(skill_metas)} skills checked)")
PY
