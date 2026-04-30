"""Tests for stages_lib._canonical — canonicalize() and fingerprint().

Verifies the 5-step canonicalization invariant (design doc
§ "Canonicalization invariant for hash stability" + ADR-0014):

  1. Deep-sort all keys alphabetically.
  2. Fixed indent (2 spaces), block flow style (no inline/flow YAML).
  3. Line endings normalized to LF; trailing whitespace stripped per line.
  4. hash_excluded_fields stripping is caller's responsibility (not tested here).
  5. sha256 the result (tested via fingerprint()).

Run:  cd scripts && python3 -m pytest stages_lib/ -v
"""

import hashlib

import yaml
import pytest

from stages_lib._canonical import canonicalize, fingerprint


# ---------------------------------------------------------------------------
# Regression sentinel — emit is YAML, NOT JSON
# ---------------------------------------------------------------------------


def test_not_json_empty_dict():
    """canonicalize({}) must NOT return b'{}' (the JSON form).

    The JSON compact form of an empty dict is b'{}' without a trailing newline.
    PyYAML block-style empty dict is b'{}\\n' (flow-style fallback for empty
    mapping), which includes the trailing newline.  The sentinel below asserts
    that the JSON bare form is absent, confirming the implementation uses YAML.
    """
    result = canonicalize({})
    # JSON form (no trailing newline): b'{}'
    assert result != b"{}", "emit looks like JSON — expected YAML (b'{}\\n')"
    # YAML safe_dump emits b'{}\\n' for empty dict
    assert result == b"{}\n"


def test_not_json_dict():
    """A non-empty dict must NOT look like compact JSON (no '\":' colon-no-space patterns)."""
    result = canonicalize({"a": 1, "b": 2})
    # JSON compact form would contain b'"a":1'
    assert b'"a":1' not in result, f"looks like JSON: {result!r}"
    # YAML block form
    assert result == b"a: 1\nb: 2\n"


# ---------------------------------------------------------------------------
# canonicalize() — scalar edge cases
# ---------------------------------------------------------------------------


def test_empty_dict():
    """Empty dict must canonicalize to YAML block-style empty mapping (b'{}\\n')."""
    assert canonicalize({}) == b"{}\n"


def test_empty_list():
    """Empty list must canonicalize to YAML flow-style empty sequence (b'[]\\n')."""
    assert canonicalize([]) == b"[]\n"


def test_none():
    """None must canonicalize to YAML null scalar with document-end marker."""
    assert canonicalize(None) == b"null\n...\n"


def test_true():
    """True must canonicalize to YAML true scalar with document-end marker."""
    assert canonicalize(True) == b"true\n...\n"


def test_false():
    """False must canonicalize to YAML false scalar with document-end marker."""
    assert canonicalize(False) == b"false\n...\n"


def test_integer_serialization():
    """Integers must serialize as YAML bare scalars (no quotes)."""
    assert canonicalize(42) == b"42\n...\n"


def test_string_serialization():
    """Simple strings serialize as YAML bare scalars (no quotes when unambiguous)."""
    assert canonicalize("hello") == b"hello\n...\n"


# ---------------------------------------------------------------------------
# canonicalize() — key ordering (step 1)
# ---------------------------------------------------------------------------


def test_key_order_invariant():
    """Dicts with permuted key order must produce identical bytes."""
    a = canonicalize({"a": 1, "b": 2})
    b = canonicalize({"b": 2, "a": 1})
    assert a == b


def test_nested_key_order_invariant():
    """Nested dicts with permuted keys must produce identical bytes."""
    a = canonicalize({"z": 1, "a": 2, "m": {"y": 3, "x": 4}})
    b = canonicalize({"a": 2, "m": {"x": 4, "y": 3}, "z": 1})
    assert a == b


def test_deep_nested_key_order():
    """Three-level nesting with permuted keys at every level must be invariant."""
    a = canonicalize({"z": {"b": {"d": 1, "c": 2}, "a": 3}, "a": 0})
    b = canonicalize({"a": 0, "z": {"a": 3, "b": {"c": 2, "d": 1}}})
    assert a == b


def test_dict_inside_list_inside_dict_keys_sorted():
    """Dict keys inside a list inside a dict must still be sorted."""
    a = canonicalize({"items": [{"b": 2, "a": 1}]})
    b = canonicalize({"items": [{"a": 1, "b": 2}]})
    assert a == b


# ---------------------------------------------------------------------------
# canonicalize() — list ordering (lists preserve insertion order)
# ---------------------------------------------------------------------------


def test_lists_preserve_order():
    """Lists must preserve order — [3,1,2] != [1,2,3]."""
    a = canonicalize([3, 1, 2])
    b = canonicalize([1, 2, 3])
    assert a != b


def test_list_in_dict_preserves_order():
    """A list nested inside a dict must preserve its order."""
    a = canonicalize({"entries": ["z", "a", "m"]})
    b = canonicalize({"entries": ["a", "m", "z"]})
    assert a != b


# ---------------------------------------------------------------------------
# canonicalize() — Unicode (step 2 allow_unicode; step 3 LF)
# ---------------------------------------------------------------------------


def test_unicode_key_preserved():
    """Unicode keys must be preserved as UTF-8, not ASCII-escaped."""
    result = canonicalize({"中": 1})
    # UTF-8 bytes for '中' are 0xe4 0xb8 0xad
    assert b"\xe4\xb8\xad" in result


def test_unicode_value_preserved():
    """Unicode in values must also be preserved as UTF-8."""
    result = canonicalize({"key": "日本語"})
    assert b"\xe6\x97\xa5" in result  # first byte of '日'


# ---------------------------------------------------------------------------
# canonicalize() — line endings (step 3)
# ---------------------------------------------------------------------------


def test_line_endings_are_lf():
    """Emit must end with LF (\\n), not CRLF (\\r\\n)."""
    result = canonicalize({"a": 1, "b": 2})
    assert b"\r\n" not in result
    assert result.endswith(b"\n")


def test_multikey_emit_ends_with_lf():
    """Every line in a multi-key block dict ends with LF only."""
    result = canonicalize({"z": 1, "a": 2, "m": {"y": 3, "x": 4}})
    assert b"\r" not in result


# ---------------------------------------------------------------------------
# canonicalize() — type precision
# ---------------------------------------------------------------------------


def test_float_vs_int_distinguishable():
    """canonicalize({'a': 1.0}) must differ from canonicalize({'a': 1})."""
    assert canonicalize({"a": 1.0}) != canonicalize({"a": 1})


def test_float_serialization():
    """Floats must serialize with decimal notation."""
    result = canonicalize({"x": 1.5})
    assert b"1.5" in result


# ---------------------------------------------------------------------------
# canonicalize() — round-trip determinism
# ---------------------------------------------------------------------------


def test_round_trip_determinism():
    """canonicalize(yaml.safe_load(canonicalize(obj))) is a fixed point."""
    obj = {"b": [1, 2, 3], "a": {"nested": True, "count": 42}}
    first = canonicalize(obj)
    reloaded = yaml.safe_load(first)
    second = canonicalize(reloaded)
    assert first == second


def test_stability_across_calls():
    """canonicalize(obj) called twice must return identical bytes."""
    obj = {"中": 1, "日": 2, "a": [3, 1, 2], "b": {"y": None, "x": True}}
    assert canonicalize(obj) == canonicalize(obj)


# ---------------------------------------------------------------------------
# fingerprint()
# ---------------------------------------------------------------------------


def test_fingerprint_is_sha256_hex():
    """fingerprint() must return the sha256 hex digest of canonicalize()."""
    obj = {"a": 1, "b": [3, 1, 2]}
    expected = hashlib.sha256(canonicalize(obj)).hexdigest()
    assert fingerprint(obj) == expected


def test_fingerprint_key_order_invariant():
    """fingerprint() must be identical for dicts with permuted keys."""
    a = fingerprint({"z": 1, "a": 2, "m": {"y": 3, "x": 4}})
    b = fingerprint({"a": 2, "m": {"x": 4, "y": 3}, "z": 1})
    assert a == b


def test_fingerprint_returns_string():
    """fingerprint() must return a str (hex digest), not bytes."""
    result = fingerprint({"k": "v"})
    assert isinstance(result, str)
    assert len(result) == 64  # sha256 hex is always 64 chars
