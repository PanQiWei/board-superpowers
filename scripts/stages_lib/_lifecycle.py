# NOTE: ADR-0013 § Decision (line 46) defines SEVEN states including `deprecated`.
# The `deprecated` state (for stages removed from the registry) is DEFERRED to v0.6.0
# alongside the first stage removal. No v0.5.0 stage carries `deprecated_in_version`,
# and no historical entries from a prior release exist, so the auto-prune sweep
# has zero consumers at v0.5.0. See ADR-0013 § Negative for the deferral rationale.
"""6-state lifecycle engine — ADR-0013 K8s-style 3-layer fingerprint diff.

States: not-applicable | pending | applied | drifted | failed | blocked
# `deprecated` state per ADR-0013 § Decision deferred to v0.6.0 (auto-prune of
# removed-from-registry stages); no v0.5.0 stage carries `deprecated_in_version`.
ADR refs: ADR-0013 (lifecycle), ADR-0020 (applicable_when), ADR-0027 § 2 (Form B).

Lifecycle invariant: append-merge-only. Persisted lifecycle state under
`modules.lifecycle.<stage_id>` is never bulk-overwritten — see
SETUP_STAGES_DEVELOPMENT.md § "Lifecycle invariant: append-merge-only".
locality:external stages with declared `external_ttl_seconds` are
cache-coherent: an applied verdict is provisional until TTL elapses,
after which live IO re-runs to validate.
"""

from __future__ import annotations

import datetime as _dt
import importlib
import subprocess
from pathlib import Path
from typing import Literal

from ._canonical import fingerprint
from ._partitioned_settings import read_settings, update_module_section

LifecycleState = Literal[
    "not-applicable", "pending", "applied", "drifted", "failed", "blocked",
]

# ---------------------------------------------------------------------------
# applicable_when predicate (ADR-0020, 3 forms)
# ---------------------------------------------------------------------------

def evaluate_applicability(
    stage: dict, *, home: Path, repo_root: Path, repo_identity: str,
) -> bool:
    """Return False if stage is not-applicable per ADR-0020 applicable_when.

    Form A: {setting_path, equals|one_of} — read merged settings, compare.
    Form B: {kanban_projection_capability} — SHELL OUT to bsp_resolve_active_projection
            (awk-based, in scripts/lib/common.sh). MUST NOT re-implement awk parser.
    Form C: {python: "module.callable"} — escape hatch.
    Absent applicable_when → always applicable.
    """
    when = stage.get("applicable_when")
    if not when or not isinstance(when, dict):
        return True
    if "setting_path" in when:
        return _eval_form_a(when, home=home, repo_root=repo_root, repo_identity=repo_identity)
    if "kanban_projection_capability" in when:
        return _eval_form_b(when, repo_root=repo_root)
    if "python" in when:
        return _eval_form_c(when, home=home, repo_root=repo_root, repo_identity=repo_identity)
    return True  # unknown form — fail open


def _eval_form_a(when: dict, *, home: Path, repo_root: Path, repo_identity: str) -> bool:
    """Form A: setting_path + one_of | equals — layer-merged settings lookup."""
    path_str: str = when.get("setting_path", "")
    expected = when.get("one_of") or ([when["equals"]] if "equals" in when else [])
    if not path_str or not expected:
        return True
    merged: dict = {}
    for loc in ("host-shared", "repo-shared", "repo-git", "repo-clone"):
        try:
            d = read_settings(loc, home=home, repo_root=repo_root, repo_identity=repo_identity)  # type: ignore
            if isinstance(d, dict):
                merged = _deep_merge(merged, d)
        except Exception:
            pass
    node = merged
    for part in path_str.split("."):
        if not isinstance(node, dict):
            return False
        node = node.get(part)
        if node is None:
            return False
    return node in expected


def _eval_form_b(when: dict, *, repo_root: Path) -> bool:
    """Form B: kanban_projection_capability (ADR-0027 § 2).

    Shells out to bsp_resolve_active_projection (bash awk-based helper in
    scripts/lib/common.sh). Parses "OK <projection> <ref>" / "EMPTY".
    Loads projection reference file and checks capability presence.

    Fallback: if bsp_resolve_active_projection returns EMPTY (e.g. project_ref
    not yet configured), attempt a direct settings.yml read for the flat shorthand
    modules.m10_kanban.projection key. This lets M3 stages become applicable as
    soon as M10 records the projection type — the project_ref is a separate
    concern (which specific GitHub Project to use) orthogonal to the capability
    predicate (which projection type is active).
    """
    capability = when.get("kanban_projection_capability", "")
    if not capability:
        return True
    plugin_root = Path(__file__).parent.parent.parent
    common_sh = plugin_root / "scripts" / "lib" / "common.sh"
    if not common_sh.exists():
        return True  # pre-bootstrap — fail open

    projection_id: str = ""
    try:
        result = subprocess.run(
            ["bash", "-c", f'source "{common_sh}" && bsp_resolve_active_projection "{repo_root}"'],
            capture_output=True, text=True, timeout=10,
        )
        output = result.stdout.strip()
        if result.returncode == 0 and output and not output.startswith("EMPTY"):
            # bsp_resolve_active_projection outputs "<projection> <ref>" on success
            # (the awk produces "OK <proj> <ref>" internally; the bash wrapper
            # strips the "OK " prefix with ${parsed#OK } before printing).
            # Some callers/mocks pass "OK <proj> <ref>" directly — handle both.
            if output.startswith("OK "):
                parts = output.split(None, 2)  # ["OK", "<projection>", "<ref>"]
                if len(parts) >= 2:
                    projection_id = parts[1]
            else:
                parts = output.split(None, 1)  # ["<projection>", "<ref>"]
                if parts:
                    projection_id = parts[0]
    except (subprocess.TimeoutExpired, OSError):
        return True  # fail open on subprocess error

    # Fallback: awk returned EMPTY or non-zero (likely project_ref not yet set).
    # Read the shorthand projection directly from settings.yml.
    if not projection_id:
        projection_id = _read_projection_from_settings(repo_root)

    if not projection_id:
        return False

    ref_file = plugin_root / "skills" / "operating-kanban" / "references" / f"{projection_id}.md"
    if not ref_file.exists():
        return False
    ref_text = ref_file.read_text(encoding="utf-8")
    return _capability_in_ref(capability, ref_text)


def _read_projection_from_settings(repo_root: Path) -> str:
    """Direct settings.yml read fallback for Form B when awk returns EMPTY.

    Reads modules.m10_kanban.projection (flat shorthand form, written by M10
    apply_choice). Used when project_ref is not yet configured so
    bsp_resolve_active_projection returns EMPTY rather than OK.
    """
    import yaml  # local import — only used in fallback path
    settings_file = repo_root / ".board-superpowers" / "settings.yml"
    if not settings_file.exists():
        return ""
    try:
        data = yaml.safe_load(settings_file.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return ""
        m10 = (data.get("modules") or {}).get("m10_kanban") or {}
        if not isinstance(m10, dict):
            return ""
        proj = m10.get("projection", "")
        return proj if isinstance(proj, str) else ""
    except Exception:
        return ""


def _capability_in_ref(capability: str, ref_text: str) -> bool:
    """Return True if capability appears in the reference file's Setup capabilities section."""
    in_section = False
    for line in ref_text.splitlines():
        s = line.strip()
        if "setup capabilities" in s.lower() and s.startswith("#"):
            in_section = True
            continue
        if in_section and s.startswith("#") and "setup capabilities" not in s.lower():
            in_section = False
        if in_section and capability in s:
            return True
    lower = ref_text.lower()
    cap = capability.lower()
    return f"`{cap}`" in lower or f"- {cap}" in lower or f"### {cap}" in lower


def _eval_form_c(when: dict, *, home: Path, repo_root: Path, repo_identity: str) -> bool:
    """Form C: python escape hatch — import module, call callable(ctx)."""
    ref: str = when.get("python", "")
    parts = ref.rsplit(".", 1)
    if len(parts) != 2:
        return True
    try:
        from types import SimpleNamespace
        mod = importlib.import_module(parts[0])
        fn = getattr(mod, parts[1])
        ctx = SimpleNamespace(home=home, repo_root=repo_root, repo_identity=repo_identity)
        return bool(fn(ctx))
    except Exception:
        return True


def _deep_merge(base: dict, override: dict) -> dict:
    result = dict(base)
    for k, v in override.items():
        if k in result and isinstance(result[k], dict) and isinstance(v, dict):
            result[k] = _deep_merge(result[k], v)
        else:
            result[k] = v
    return result


# ---------------------------------------------------------------------------
# 3-layer diff (ADR-0013)
# ---------------------------------------------------------------------------

def diff_layer1(stage_id: str, persisted: dict, registry_generation: int) -> str:
    """Layer 1: O(1) generation int compare. Returns 'fast-path-applied' or 'fast-path-pending'."""
    if not persisted:
        return "fast-path-pending"
    gen = persisted.get("generation")
    if gen is None:
        return "fast-path-pending"
    return "fast-path-applied" if int(gen) == int(registry_generation) else "fast-path-pending"


def diff_layer2(stage_id: str, persisted: dict, registry_target_state_hash: str) -> str:
    """Layer 2: sha256 compare. Returns 'matched' or 'drifted'.

    Backstop for forgotten generation bumps. Uses _canonical.fingerprint (single producer).
    """
    recorded = persisted.get("target_state_hash")
    if not recorded:
        return "drifted"
    return "matched" if recorded == registry_target_state_hash else "drifted"


def diff_layer3(stage_id: str, persisted: dict, registry_target_state: dict) -> tuple[bool, dict]:
    """Layer 3: structured field diff. O(state size). Returns (matches, diff_dict).

    Never read by the hook; used by SKILL for human-readable migration diagnostics.
    """
    recorded = persisted.get("target_state") or {}
    diff = _structural_diff(recorded, registry_target_state)
    return (len(diff) == 0, diff)


def _structural_diff(recorded: dict, target: dict, prefix: str = "") -> dict:
    result = {}
    for k in sorted(set(recorded) | set(target)):
        fk = f"{prefix}.{k}" if prefix else k
        rv, tv = recorded.get(k), target.get(k)
        if isinstance(rv, dict) and isinstance(tv, dict):
            result.update(_structural_diff(rv, tv, fk))
        elif rv != tv:
            result[fk] = {"recorded": rv, "target": tv}
    return result


# ---------------------------------------------------------------------------
# Per-stage evaluation
# ---------------------------------------------------------------------------

def evaluate_stage(
    stage: dict, *, home: Path, repo_root: Path, repo_identity: str, helper_module: object,
) -> dict:
    """Full per-stage evaluation: applicability → 3-layer diff → state.

    Algorithm (ADR-0013):
    1. applicable_when predicate → not-applicable if False.
    2. Load persisted entry → pending if absent.
    3. Check persisted status for failed/blocked transient states.
    4. compute_target_state() → registry hash.
    5. Layer 1 diff: generation mismatch → drifted.
    6. Layer 2 diff: hash mismatch → drifted.
    7. Both match → applied.
    """
    stage_id: str = stage["stage_id"]
    reg_gen: int = int(stage.get("generation", 0))

    if not evaluate_applicability(stage, home=home, repo_root=repo_root, repo_identity=repo_identity):
        return _result(stage_id, "not-applicable", "applicable_when predicate false",
                       None, reg_gen, None, None, None)

    persisted = _load_persisted(stage_id, home=home, repo_root=repo_root, repo_identity=repo_identity)
    if not persisted:
        return _result(stage_id, "pending", "no persisted entry - stage never run",
                       None, reg_gen, None, None, None)

    ps = persisted.get("status", "")
    if ps in ("failed", "blocked"):
        return _result(stage_id, ps,  # type: ignore
                       f"persisted status={ps}: {persisted.get('last_error', '')}",
                       persisted.get("generation"), reg_gen,
                       persisted.get("target_state_hash"), None, None)

    try:
        from types import SimpleNamespace
        ctx = SimpleNamespace(home=home, repo_root=repo_root, repo_identity=repo_identity)
        target_state: dict = helper_module.compute_target_state(ctx)  # type: ignore
    except Exception as exc:
        return _result(stage_id, "pending", f"compute_target_state raised: {exc}",
                       persisted.get("generation"), reg_gen, None, None, None)

    excluded: list = stage.get("hash_excluded_fields") or []
    hashable = {k: v for k, v in target_state.items() if k not in excluded}
    reg_hash = fingerprint(hashable)

    l1 = diff_layer1(stage_id, persisted, reg_gen)
    if l1 == "fast-path-pending":
        _, sd = diff_layer3(stage_id, persisted, target_state)
        return _result(stage_id, "drifted",
                       f"generation mismatch: recorded={persisted.get('generation')} registry={reg_gen}",
                       persisted.get("generation"), reg_gen,
                       persisted.get("target_state_hash"), reg_hash, sd)

    l2 = diff_layer2(stage_id, persisted, reg_hash)
    if l2 == "drifted":
        _, sd = diff_layer3(stage_id, persisted, target_state)
        return _result(stage_id, "drifted",
                       "target_state_hash mismatch (semantic drift without generation bump)",
                       persisted.get("generation"), reg_gen,
                       persisted.get("target_state_hash"), reg_hash, sd)

    # Layer 2.5 — locality:external TTL re-validation (audit A2 fix).
    # When a stage with locality:external has matched both Layer 1 and
    # Layer 2 (i.e., would otherwise be `applied`), check whether its
    # external_validated_at cache marker is still inside the declared
    # external_ttl_seconds window. If expired (or missing) we re-run live
    # IO via helper_module.idempotency_check; success refreshes the cache,
    # failure flips the verdict to `drifted`. See
    # SETUP_STAGES_DEVELOPMENT.md § "Lifecycle invariant: append-merge-only".
    if stage.get("locality") == "external" and stage.get("external_ttl_seconds"):
        verdict = _evaluate_external_ttl(
            stage, persisted=persisted, helper_module=helper_module,
            home=home, repo_root=repo_root, repo_identity=repo_identity,
        )
        if verdict is not None:
            state, reason = verdict
            return _result(stage_id, state, reason,
                           persisted.get("generation"), reg_gen,
                           persisted.get("target_state_hash"), reg_hash, None)

    return _result(stage_id, "applied", "generation and target_state_hash match",
                   persisted.get("generation"), reg_gen,
                   persisted.get("target_state_hash"), reg_hash, None)


# ---------------------------------------------------------------------------
# Layer 2.5 — locality:external TTL re-validation (audit A2)
# ---------------------------------------------------------------------------


def _evaluate_external_ttl(
    stage: dict,
    *,
    persisted: dict,
    helper_module: object,
    home: Path,
    repo_root: Path,
    repo_identity: str,
) -> tuple[str, str] | None:
    """Return (state, reason) override when external TTL handling applies.

    Returns None when the cache is hot (no override — caller returns the
    default `applied` verdict). Otherwise returns one of:
      ("applied", "<reason>")  — live IO succeeded; cache refreshed.
      ("drifted", "<reason>")  — live IO observed missing target.
      ("applied", "<reason>")  — helper has no idempotency_check; fail open.

    The function is the single locus of TTL-cache writes; it MUST update
    `external_validated_at` via update_module_section() (load-merge), never
    via a bulk write. See SETUP_STAGES_DEVELOPMENT.md § Lifecycle invariant.
    """
    stage_id: str = stage["stage_id"]
    ttl: int = int(stage.get("external_ttl_seconds") or 0)
    if ttl <= 0:
        return None

    last_validated = persisted.get("external_validated_at")
    now = _dt.datetime.now(_dt.timezone.utc)

    # PyYAML auto-parses ISO timestamps into datetime objects on load; the
    # raw string form survives only when the source emitter quoted the value.
    # Accept both shapes so the cache check works regardless of write path.
    expired = True
    parsed: _dt.datetime | None = None
    if isinstance(last_validated, _dt.datetime):
        parsed = last_validated
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=_dt.timezone.utc)
    elif isinstance(last_validated, str) and last_validated:
        parsed = _parse_iso_timestamp(last_validated)
    if parsed is not None:
        expires_at = parsed + _dt.timedelta(seconds=ttl)
        expired = now >= expires_at

    if not expired:
        return None  # cache still hot — caller returns applied

    idem = getattr(helper_module, "idempotency_check", None)
    if not callable(idem):
        # Helper does not expose idempotency_check; fail open and refresh
        # the cache marker so we do not loop on every hook tick.
        _refresh_external_validated_at(
            stage_id, now=now,
            home=home, repo_root=repo_root, repo_identity=repo_identity,
        )
        return ("applied", "external TTL expired but helper exposes no idempotency_check; cache refreshed")

    try:
        from types import SimpleNamespace
        ctx = SimpleNamespace(home=home, repo_root=repo_root, repo_identity=repo_identity)
        result = idem(ctx)
    except Exception as exc:  # noqa: BLE001 — fail open on live-IO error
        return ("applied", f"external TTL expired but live IO raised: {exc}; deferring to next tick")

    if isinstance(result, dict) and result.get("present") is True:
        _refresh_external_validated_at(
            stage_id, now=now,
            home=home, repo_root=repo_root, repo_identity=repo_identity,
        )
        return ("applied", "external TTL expired; live IO confirmed target present; cache refreshed")

    return ("drifted", "external TTL expired; live IO observed target missing")


def _parse_iso_timestamp(value: str) -> _dt.datetime | None:
    """Parse an ISO 8601 / RFC-3339 timestamp; tolerate trailing Z and naive forms."""
    s = value.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        parsed = _dt.datetime.fromisoformat(s)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=_dt.timezone.utc)
    return parsed


def _refresh_external_validated_at(
    stage_id: str,
    *,
    now: _dt.datetime,
    home: Path,
    repo_root: Path,
    repo_identity: str,
) -> None:
    """Append-merge external_validated_at into modules.lifecycle.<stage_id>.

    Uses update_module_section's read-modify-write semantics so peer stages'
    lifecycle entries (and any other module sections) are preserved. This is
    the lifecycle invariant: append-merge-only, never bulk-overwrite.
    """
    iso = now.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    try:
        # update_module_section preserves all sibling lifecycle entries; we
        # merge ONLY the single stage_id key by doing a focused dict.
        existing = read_settings("repo-shared", home=home, repo_root=repo_root, repo_identity=repo_identity)
        modules = existing.setdefault("modules", {}) if isinstance(existing, dict) else {}
        if not isinstance(modules, dict):
            return
        lifecycle = modules.setdefault("lifecycle", {})
        if not isinstance(lifecycle, dict):
            return
        entry = lifecycle.get(stage_id)
        if not isinstance(entry, dict):
            return
        entry["external_validated_at"] = iso
        # Re-write via update_module_section so the merge is centralised.
        update_module_section(
            "repo-shared", "lifecycle", lifecycle,
            home=home, repo_root=repo_root, repo_identity=repo_identity,
        )
    except Exception:
        # Cache refresh is best-effort; an IO failure here must not flip the
        # caller's verdict. The next hook tick will re-evaluate.
        return


def _result(stage_id, state, reason, p_gen, r_gen, p_hash, r_hash, s_diff) -> dict:
    return {
        "stage_id": stage_id, "state": state, "reason": reason,
        "persisted_generation": p_gen, "registry_generation": r_gen,
        "persisted_target_state_hash": p_hash, "registry_target_state_hash": r_hash,
        "structured_diff": s_diff,
    }


def _load_persisted(stage_id: str, *, home: Path, repo_root: Path, repo_identity: str) -> dict:
    """Load lifecycle entry for stage_id from repo-shared settings.modules.lifecycle.<id>."""
    try:
        data = read_settings("repo-shared", home=home, repo_root=repo_root, repo_identity=repo_identity)
    except Exception:
        return {}
    entry = (data.get("modules") or {}).get("lifecycle", {}).get(stage_id) or {}
    return entry if isinstance(entry, dict) else {}


# ---------------------------------------------------------------------------
# evaluate_all_stages — topological sort + cascade
# ---------------------------------------------------------------------------

def evaluate_all_stages(
    registry: dict, *, home: Path, repo_root: Path, repo_identity: str,
) -> list[dict]:
    """Topologically sort stages by depends_on; evaluate each.

    Cascade rule (ADR-0013): stages whose dependency is pending/failed/blocked
    are cascaded to not-applicable. drifted dependencies do NOT block.
    not-applicable dependencies also do NOT block (stage was simply skipped).
    """
    stages: list[dict] = registry.get("stages", [])
    ordered = _topological_sort(stages)

    _BLOCKING = {"pending", "failed", "blocked"}
    state_by_id: dict[str, str] = {}
    results: list[dict] = []

    for stage in ordered:
        sid = stage["stage_id"]
        dep_block = next(
            (f"dependency {d!r} is {state_by_id.get(d)!r}"
             for d in (stage.get("depends_on") or [])
             if state_by_id.get(d) in _BLOCKING), ""
        )
        if dep_block:
            r = _result(sid, "not-applicable", f"cascaded: {dep_block}",
                        None, int(stage.get("generation", 0)), None, None, None)
            state_by_id[sid] = "not-applicable"
            results.append(r)
            continue

        helper = _load_helper(sid)
        r = evaluate_stage(stage, home=home, repo_root=repo_root,
                           repo_identity=repo_identity, helper_module=helper)
        state_by_id[sid] = r["state"]
        results.append(r)

    return results


def _load_helper(stage_id: str) -> object:
    """Import stages_lib.<slug> module or return a no-op stub."""
    slug = stage_id.replace(".", "_").replace("-", "_")
    try:
        return importlib.import_module(f"stages_lib.{slug}")
    except ImportError:
        from types import SimpleNamespace
        return SimpleNamespace(compute_target_state=lambda ctx: {})


def _topological_sort(stages: list[dict]) -> list[dict]:
    """Kahn's algorithm — stable (preserves registry order within a level)."""
    by_id = {s["stage_id"]: s for s in stages}
    in_deg: dict[str, int] = {s["stage_id"]: 0 for s in stages}
    deps: dict[str, list[str]] = {s["stage_id"]: [] for s in stages}

    for stage in stages:
        for dep in stage.get("depends_on") or []:
            if dep in by_id:
                in_deg[stage["stage_id"]] += 1
                deps[dep].append(stage["stage_id"])

    queue = [s["stage_id"] for s in stages if in_deg[s["stage_id"]] == 0]
    result = []
    while queue:
        sid = queue.pop(0)
        result.append(by_id[sid])
        for child in deps.get(sid, []):
            in_deg[child] -= 1
            if in_deg[child] == 0:
                queue.append(child)

    if len(result) != len(stages):
        raise ValueError("Cycle detected in stage dependency graph")
    return result
