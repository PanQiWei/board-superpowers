"""ADR-0014 4-callable contract for stage m4.repo.acquire-dsn.

Stage: M4 | agentic | repo-shared | both platforms
Purpose: Acquire BYO RDBMS DSN; write per-repo credentials.yml (chmod 0600).
         First-time agentic (prompts architect for scheme); re-use automated.
         Default: sqlite (zero-config per ADR-0019).

character: agentic (single-choice)
locality: repo-shared → HOST-side ~/.board-superpowers/repos/<repo-identity>/credentials.yml
          NOT in settings.yml family (ADR-0024 § Part A — credentials.yml
          is a SEPARATE file at mode 0600 for secret isolation).
depends_on: m1.repo.write-state-yml
target_state_schema:
  {dsn_scheme: enum[6], credentials_path: str, credentials_mode: str}

6-scheme allowlist per ADR-0009:
  postgresql, postgres, mysql, mysql+pymysql, sqlite, sqlite3

Agentic stage protocol (ADR-0023):
  executor() → {applied: False, requires_input: True, prompt: <dict>, default: 'sqlite'}
               when credentials.yml absent.
  executor() → {applied: False, message: 'already configured'} when present.
  apply_choice(ctx, dsn_value: str) → writes credentials.yml; mode 0600.

5th callable: apply_choice(ctx, dsn_value: str) -> dict

Per ADR-0015: credentials.yml lives at:
  ~/.board-superpowers/repos/<repo-identity>/credentials.yml
where repo-identity is e.g. "owner/repo" (slash allowed in normalized sub-dirs).

Per ADR-0019: fresh repo with no architect override → executor auto-sets
  sqlite default WITHOUT prompting.

ctx contract: any object with attributes home (Path), repo_root (Path),
              repo_identity (str, e.g. 'owner/repo').
"""

from __future__ import annotations

import os
import stat
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# 6-scheme allowlist — ADR-0009 § Decision (source of truth)
# ---------------------------------------------------------------------------

ALLOWED_SCHEMES: list[str] = [
    "postgresql",
    "postgres",
    "mysql",
    "mysql+pymysql",
    "sqlite",
    "sqlite3",
]

_DEFAULT_SCHEME = "sqlite"

_PROMPT = {
    "kind": "single-choice",
    "prompt": (
        "Choose the audit-log RDBMS scheme: [sqlite] (default, zero-config per "
        "ADR-0009), postgres, or mysql."
    ),
    "options": ALLOWED_SCHEMES,
    "default": _DEFAULT_SCHEME,
}


# ---------------------------------------------------------------------------
# credentials.yml helpers — separate from settings.yml family (ADR-0024 § A)
# ---------------------------------------------------------------------------


def _credentials_path(ctx: Any) -> Path:
    """Return the per-repo credentials.yml path at HOST-side.

    Path: ~/.board-superpowers/repos/<repo-identity>/credentials.yml
    repo-identity may include '/' (owner/repo) — preserved as subdirectory.
    """
    home = Path(ctx.home)
    identity: str = getattr(ctx, "repo_identity", "") or ""
    return home / ".board-superpowers" / "repos" / identity / "credentials.yml"


def _read_credentials(ctx: Any) -> dict:
    """Read credentials.yml; return empty dict if absent."""
    path = _credentials_path(ctx)
    if not path.exists():
        return {}
    try:
        import yaml  # type: ignore[import-untyped]
        text = path.read_text()
        data = yaml.safe_load(text) or {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _write_credentials(ctx: Any, data: dict) -> Path:
    """Atomic write credentials.yml with mode 0600.

    Uses write-then-chmod-then-replace to guarantee mode 0600 on the final
    file regardless of umask.
    """
    import tempfile
    import yaml  # type: ignore[import-untyped]

    path = _credentials_path(ctx)
    path.parent.mkdir(parents=True, exist_ok=True)

    content = yaml.safe_dump(data, sort_keys=True, allow_unicode=True)

    # Write to a temp file in the same directory so os.replace is atomic.
    fd, tmp_path_str = tempfile.mkstemp(dir=path.parent, prefix=".cred-tmp-")
    try:
        tmp_path = Path(tmp_path_str)
        with os.fdopen(fd, "w") as fh:
            fh.write(content)
        # Set 0600 before rename so the final path never exists with wrong perms.
        os.chmod(tmp_path, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(tmp_path, path)
    except Exception:
        try:
            Path(tmp_path_str).unlink(missing_ok=True)
        except Exception:
            pass
        raise
    return path


def _default_sqlite_dsn(ctx: Any) -> str:
    """Compute the default sqlite DSN for a fresh repo.

    Canonical path: ~/.board-superpowers/repos/<repo-identity>/audit.db
    SQLAlchemy 4-slash absolute form: sqlite:////abs/path
    Per ADR-0009 § Decision.
    """
    home = Path(ctx.home)
    identity: str = getattr(ctx, "repo_identity", "") or ""
    audit_db_path = home / ".board-superpowers" / "repos" / identity / "audit.db"
    # 4-slash form: sqlite:/// + /abs/path
    return f"sqlite:////{audit_db_path}"


def _parse_scheme(dsn: str) -> str:
    """Extract scheme from a DSN URL string."""
    if "://" in dsn:
        return dsn.split("://", 1)[0]
    return ""


# ---------------------------------------------------------------------------
# 4-callable contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return the prompt schema / current DSN state for this agentic stage.

    If credentials.yml already has audit_dsn → return its scheme + path.
    If absent → return default sqlite scheme (ADR-0019 zero-config default).

    Returns: {dsn_scheme: str, credentials_path: str, credentials_mode: str}
    These satisfy the registry target_state_schema required field dsn_scheme.
    """
    creds = _read_credentials(ctx)
    dsn = creds.get("audit_dsn", "")
    if dsn:
        scheme = _parse_scheme(dsn)
    else:
        scheme = _DEFAULT_SCHEME

    cred_path = _credentials_path(ctx)
    if cred_path.exists():
        mode_octal = oct(cred_path.stat().st_mode & 0o7777)
    else:
        mode_octal = "0o600"  # expected default

    return {
        "dsn_scheme": scheme,
        "credentials_path": str(cred_path),
        "credentials_mode": f"{(cred_path.stat().st_mode & 0o7777):04o}" if cred_path.exists() else "0600",
    }


def target_state_predicate(state: Any) -> bool:
    """Pure: validate dsn_scheme is in the 6-scheme allowlist (ADR-0009).

    Rejects any scheme not in {postgresql, postgres, mysql, mysql+pymysql,
    sqlite, sqlite3}.
    """
    if not isinstance(state, dict):
        return False
    scheme = state.get("dsn_scheme")
    if not isinstance(scheme, str):
        return False
    return scheme in ALLOWED_SCHEMES


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: check if credentials.yml has audit_dsn set.

    Returns: {present: bool, current_state: {dsn_scheme: str|None}}
    present=True means the stage has already been configured (executor no-ops).
    """
    cred_path = _credentials_path(ctx)
    if not cred_path.exists():
        return {"present": False, "current_state": {"dsn_scheme": None}}

    creds = _read_credentials(ctx)
    dsn = creds.get("audit_dsn", "")
    if not dsn:
        return {"present": False, "current_state": {"dsn_scheme": None}}

    scheme = _parse_scheme(dsn)
    if scheme not in ALLOWED_SCHEMES:
        return {"present": False, "current_state": {"dsn_scheme": scheme, "error": "scheme not in allowlist"}}

    return {"present": True, "current_state": {"dsn_scheme": scheme}}


def executor(ctx: Any) -> dict:
    """Agentic executor: auto-configure sqlite default, or signal requires_input.

    Per ADR-0019 § Decision:
    - If credentials.yml already has audit_dsn → no-op (already configured).
    - If absent → auto-write sqlite default WITHOUT prompting (zero-config).
      The agentic path (requires_input=True) only engages when the architect
      explicitly opts into a non-sqlite scheme.

    Returns: {applied, message, [requires_input, prompt, default]}
    """
    check = idempotency_check(ctx)
    if check["present"]:
        scheme = check["current_state"]["dsn_scheme"]
        return {
            "applied": False,
            "message": f"audit_dsn already configured (scheme: {scheme}) — no-op",
        }

    # ADR-0019: auto-apply sqlite default without prompting.
    default_dsn = _default_sqlite_dsn(ctx)
    result = apply_choice(ctx, default_dsn)
    return {
        "applied": result["applied"],
        "message": f"auto-configured sqlite default DSN: {default_dsn}",
        "side_effects": result.get("side_effects", []),
    }


def apply_choice(ctx: Any, dsn_value: str) -> dict:
    """5th callable: persist the architect's validated DSN choice.

    Writes audit_dsn to per-repo credentials.yml (mode 0600).
    Called by the SKILL after architect confirms, or by executor for sqlite default.

    Per ADR-0015: credentials.yml lives at HOST-side per-repo path,
    NOT in settings.yml family (ADR-0024 § Part A).

    Args:
        ctx: lifecycle context with home, repo_root, repo_identity
        dsn_value: full DSN URL (e.g. 'sqlite:////~/.../audit.db' or
                   'postgresql://user:pass@host/db')

    Returns: {applied, message, side_effects}
    """
    if not isinstance(dsn_value, str) or not dsn_value.strip():
        raise ValueError(f"dsn_value must be a non-empty string, got {dsn_value!r}")

    scheme = _parse_scheme(dsn_value)
    if scheme not in ALLOWED_SCHEMES:
        raise ValueError(
            f"DSN scheme {scheme!r} not in allowlist {ALLOWED_SCHEMES}. "
            "Per ADR-0009: allowed schemes are "
            "postgresql, postgres, mysql, mysql+pymysql, sqlite, sqlite3."
        )

    # Idempotency: if already set to same value, skip.
    creds = _read_credentials(ctx)
    if creds.get("audit_dsn") == dsn_value:
        cred_path = _credentials_path(ctx)
        return {
            "applied": False,
            "message": f"audit_dsn already set to this value — no change",
            "side_effects": [],
        }

    # Merge into existing credentials (preserve other keys like db tokens).
    creds["audit_dsn"] = dsn_value

    cred_path = _write_credentials(ctx, creds)
    return {
        "applied": True,
        "message": f"audit_dsn persisted to {cred_path} (mode 0600, scheme: {scheme})",
        "side_effects": [f"wrote {cred_path} (mode 0600)"],
    }
