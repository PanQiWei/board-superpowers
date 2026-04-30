"""Canonical-bytes helper for ADR-0013 layer-2 fingerprint (target_state_hash).

This module is the **single producer** of canonical bytes for all stage
target_state hashes. Stages that bypass this helper and emit ad-hoc YAML or
JSON break hash stability silently — CI round-trip tests catch drift.

Canonicalization invariants (per design doc § "Canonicalization invariant for
hash stability" + ADR-0014 § "Canonicalization invariant for hash stability"):

  1. Deep-sort all keys alphabetically (recursively for nested dicts).
  2. Fixed indent (2 spaces), fixed flow style (block — not inline/flow).
  3. Normalize all line endings to ``\\n``; strip trailing whitespace per line.
  4. Strip the ``hash_excluded_fields`` paths before hashing (caller's
     responsibility — pass a pre-stripped object; this helper is path-agnostic).
  5. sha256 the resulting UTF-8 bytes.

``yaml.safe_dump`` arguments that lock determinism:
  - ``sort_keys=True``   — lexicographic key sort (step 1)
  - ``default_flow_style=False`` — block style throughout (step 2)
  - ``indent=2``         — fixed 2-space indent (step 2)
  - ``allow_unicode=True`` — Unicode codepoints preserved, not ASCII-escaped
  - ``width=10**9``      — no line wrapping (lines wrap non-deterministically
                           when the default 80-char width clips long values)

Bash consumers hash what Python emits; a format change here breaks the
layer-2 fingerprint for every repo. Do not modify without updating CI
round-trip tests and bumping affected stage ``generation`` values.
"""

import hashlib

import yaml


def canonicalize(obj) -> bytes:
    """Return canonical UTF-8 bytes for *obj* suitable for sha256 input.

    Applies the 5-step canonicalization invariant.  Step 4
    (``hash_excluded_fields`` stripping) is the **caller's** responsibility —
    pass in a pre-stripped object.  This function is path-agnostic.

    Invariants applied here:
    - Step 1: dict keys sorted lexicographically (recursively), via
      ``sort_keys=True``.
    - Step 2: block YAML (``default_flow_style=False``), 2-space indent.
    - Step 3: line endings normalized to ``\\n``; trailing whitespace stripped
      per line.  (``yaml.safe_dump`` already emits ``\\n`` on all platforms;
      the normalization is a defensive guard against future PyYAML changes or
      ``\\r\\n`` environments.)
    - Step 5 is performed by ``fingerprint()``.

    Lists preserve insertion order — do NOT sort lists; order may be semantic.
    Unicode strings preserved (``allow_unicode=True``).
    """
    raw: str = yaml.safe_dump(
        obj,
        default_flow_style=False,
        sort_keys=True,
        allow_unicode=True,
        width=10**9,
        indent=2,
    )
    # Step 3: normalize line endings + strip trailing whitespace per line.
    normalized = "\n".join(line.rstrip() for line in raw.replace("\r\n", "\n").replace("\r", "\n").split("\n"))
    # safe_dump always ends with '\n'; after the join the final '\n' is
    # preserved as a trailing empty element that becomes the last '\n'.
    return normalized.encode("utf-8")


def fingerprint(obj) -> str:
    """Return the sha256 hex digest of ``canonicalize(obj)`` (step 5).

    This is the layer-2 hash stored in ``target_state_hash`` entries
    (ADR-0013 § "Layer-2 fingerprint"). Returns a 64-character lowercase
    hex string.
    """
    return hashlib.sha256(canonicalize(obj)).hexdigest()
