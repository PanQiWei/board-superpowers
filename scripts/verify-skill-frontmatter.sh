#!/usr/bin/env bash
# scripts/verify-skill-frontmatter.sh — CI gate for SKILL.md frontmatter.
#
# Validates the three-tier discipline per
# SKILL_DEVELOPMENT.md § "Three-tier frontmatter discipline":
#   1. Tier 1: name + description present
#   2. Tier 2: any used field is in the CC official spec set
#   3. Tier 3: NO custom non-spec fields (anti-pattern A4)
# Plus defensive cross-platform safety:
#   - description ≤ 1024 chars (cross-platform safe ceiling)
#   - description + when_to_use combined ≤ 1536 chars (CC absolute ceiling)
#   - argument-hint values with YAML special chars must be double-quoted
#
# Exit codes: 0 OK, 1 FAIL (details on stderr).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
# shellcheck source-path=SCRIPTDIR
. "${SCRIPT_DIR}/lib/common.sh"

PLUGIN_ROOT="$(bsp_plugin_root)"
SKILLS_DIR="${PLUGIN_ROOT}/skills"

bsp_require_cmd python3

python3 - "$SKILLS_DIR" <<'PY'
import os, re, sys

skills_dir = sys.argv[1]
errors = []

# Tier 2 — CC official spec fields (per code.claude.com/docs/en/skills.md).
TIER_2_FIELDS = {
    'when_to_use', 'argument-hint', 'arguments',
    'disable-model-invocation', 'user-invocable', 'allowed-tools',
    'model', 'effort', 'context', 'agent', 'hooks', 'paths', 'shell',
}
# Tier 1 — universally portable.
TIER_1_FIELDS = {'name', 'description'}
ALLOWED = TIER_1_FIELDS | TIER_2_FIELDS

YAML_SPECIAL_CHARS = set(":,*&!|>'\"[]{}#%@`")

def extract_frontmatter(path):
    """Return frontmatter dict + raw text. Returns (None, None) if absent."""
    with open(path) as f:
        text = f.read()
    m = re.match(r'^---\s*\n(.*?)\n---\s*\n', text, re.DOTALL)
    if not m:
        return None, None
    raw = m.group(1)
    fm = {}
    for line in raw.split('\n'):
        line_stripped = line.strip()
        if not line_stripped or line_stripped.startswith('#'):
            continue
        if ':' not in line:
            continue
        k, v = line.split(':', 1)
        fm[k.strip()] = v.strip()
    return fm, raw

for entry in sorted(os.listdir(skills_dir)):
    skill_path = os.path.join(skills_dir, entry)
    if not os.path.isdir(skill_path):
        continue
    skill_md = os.path.join(skill_path, 'SKILL.md')
    if not os.path.isfile(skill_md):
        continue  # caught by verify-skill-metadata
    fm, _ = extract_frontmatter(skill_md)
    if fm is None:
        errors.append(f"{entry}: SKILL.md has no YAML frontmatter")
        continue

    # Tier 1 mandatory.
    for f in TIER_1_FIELDS:
        if f not in fm or not fm[f]:
            errors.append(f"{entry}: missing required Tier 1 field: {f}")

    # Tier 3 forbidden — any field NOT in ALLOWED is anti-pattern A4.
    for k in fm:
        if k not in ALLOWED:
            errors.append(
                f"{entry}: Tier 3 anti-pattern A4 — '{k}' is not a "
                f"CC / Codex spec field. Project metadata goes in "
                f".skill-meta.yaml."
            )

    # description char cap.
    desc = fm.get('description', '')
    if len(desc) > 1024:
        errors.append(
            f"{entry}: description {len(desc)} chars > 1024 "
            f"(cross-platform safe ceiling)"
        )
    when = fm.get('when_to_use', '')
    if len(desc) + len(when) > 1536:
        errors.append(
            f"{entry}: description+when_to_use "
            f"{len(desc)+len(when)} chars > 1536 (CC absolute ceiling)"
        )

    # argument-hint defensive quoting.
    ah = fm.get('argument-hint', '')
    if ah and not (ah.startswith('"') and ah.endswith('"')):
        # Check if the unquoted value has a YAML special char.
        has_special = any(c in YAML_SPECIAL_CHARS for c in ah)
        if has_special:
            errors.append(
                f"{entry}: argument-hint contains YAML special chars "
                f"but is not double-quoted (root cause of CC #22161). "
                f"Wrap in double quotes."
            )

    # name should match directory name.
    name = fm.get('name', '')
    if name and name != entry:
        errors.append(f"{entry}: name='{name}' does not match directory name")

if errors:
    print("verify-skill-frontmatter: FAIL", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

print("verify-skill-frontmatter: OK")
PY
