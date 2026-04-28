# Installation

How to put board-superpowers on a host and wire it into a repo. The plugin ships two installer scripts that automate the work; this reference explains what each one does so you can also recover by hand when automation hits a wall.

## Two installer scripts

| Script | When to run | What it sets up |
|--------|-------------|-----------------|
| `${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-host.sh` | Once per machine, the first time you ever use board-superpowers there | Host-level state: creates `~/.board-superpowers/` (mode `0700`), writes the initial `manifest.yml`, records the running plugin version |
| `${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-project.sh` | Once per repo on this host, after host bootstrap | Per-repo state: standard labels, Status field validation, `<repo>/.board-superpowers/config.yml`, `.gitignore` append for the local file, BYO-RDBMS credential UX, routing-block injection into `AGENTS.md` and `CLAUDE.md`, initial host-local `state.yml` with the routing-block hashes |

Both scripts are idempotent. Re-running with the same args is safe — the host script refreshes the recorded plugin version (preserving `host_bootstrapped_at`); the project script bails on no-ops or warns on detected drift before rewriting.

## Fast path — fully automated

For a fresh setup on a clean machine:

```bash
# 1. Host bootstrap (one-time per machine).
bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-host.sh
# Add --auto-install-uv to skip the interactive prompt for installing uv
# (the Python toolchain manager the plugin uses for per-repo venvs).

# 2. Per-repo bootstrap (one-time per repo on this machine).
bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-project.sh \
  --owner <github-login> \
  --project <github-project-number> \
  --repo-root "$(pwd)"
# Optional: --audit-db-url <DSN>   # non-interactive BYO-RDBMS config;
                                   # persists to ~/.board-superpowers/credentials.yml
                                   # at mode 0600.

# 3. Verify.
bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh
bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-board.sh \
  --owner <login> --project <number> --status Ready
```

On Codex CLI, substitute `${CODEX_PLUGIN_ROOT}` for `${CLAUDE_PLUGIN_ROOT}` (or just call `bsp_plugin_root` from `scripts/lib/common.sh` which papers over the env-var split). Codex CLI also requires one extra step to wire the `SessionStart` hook, since Codex does not auto-discover `hooks/hooks.json`:

```bash
bash ${CODEX_PLUGIN_ROOT}/scripts/register-codex-hooks.sh --install-user
```

When all three verify-step commands exit `0` and the second prints a JSON list of `Ready` cards (an empty `[]` is fine if the board is empty), the installation is good.

## What the host bootstrap actually does

`bootstrap-host.sh` is a small idempotent script:

- Creates `~/.board-superpowers/` if missing (mode `0700` so other users on a shared machine cannot read your audit log fallback).
- Writes `~/.board-superpowers/manifest.yml` atomically — render to a `mktemp` scratch file in the same directory, chmod `0644`, then rename to the final path. POSIX guarantees same-filesystem rename atomicity, so a Ctrl-C or crash never leaves a half-written manifest.
- Records the plugin version. On re-run, refreshes `last_seen_version` if the on-disk value is behind the running plugin's version, preserving the original `host_bootstrapped_at` timestamp.

If host bootstrap fails: the most common cause is `~/.board-superpowers/` having weird permissions inherited from a previous user. Fix is `rm -rf ~/.board-superpowers/` and re-run; nothing irreplaceable lives there yet (the audit log fallback only appears once you start running mutating actions).

## What the per-repo bootstrap actually does

`bootstrap-project.sh` orchestrates several distinct sub-capabilities. Knowing each one lets you reproduce by hand if the script can't run end-to-end.

1. **Standard labels.** Creates the four labels the plugin's skills depend on — `wip-override`, `suspended`, `security`, `pr-contract-override` — by delegating to `${CLAUDE_PLUGIN_ROOT}/scripts/setup-labels.sh`. Manual fallback: run `gh label create` for each.
2. **Status field validation.** Reads the GitHub Project's Status single-select field and verifies it has the canonical 6 options in order: `Backlog`, `Ready`, `In Progress`, `In Review`, `Done`, `Blocked` (Blocked is intentionally last — it is a side-channel state, not a step in the linear flow). If the project ships with the GitHub default `Todo / In Progress / Done`, edit it via the Project UI to add the missing options and remove `Todo`.
3. **`<repo>/.board-superpowers/config.yml` write.** Records project coordinates as `project: <owner>/<number>`. Manual fallback is a one-line `echo` into the file.
4. **`.gitignore` append.** Adds the `*.local.*` pattern (so `config.local.yml` doesn't leak per-user fields) and the `.board-superpowers/.venv/` line. Manual fallback is editing `.gitignore` by hand.
5. **BYO-RDBMS credential UX.** Resolves the audit DB URL by priority — `--audit-db-url` flag, `$BOARD_SP_AUDIT_DB_URL` env, pre-existing `~/.board-superpowers/credentials.yml`, interactive prompt. The flag and the prompt-accept paths persist; the env-var path is ephemeral by design. Schemes accepted: Postgres, MySQL, SQLite (with the 4-slash absolute-path convention). When skipped, audit writes degrade to `~/.board-superpowers/repos/<normalized>/audit-local.jsonl` until configured.
6. **Per-repo Python venv.** Copies `pyproject.toml` and `uv.lock` templates into `<repo>/.board-superpowers/` and runs `uv sync` to materialize the venv at `<repo>/.board-superpowers/.venv/`. Manual fallback: install `uv` then `cd .board-superpowers && uv sync`.
7. **Routing-block injection.** Injects the canonical block into `AGENTS.md` and `CLAUDE.md` between the marker pair (`<!-- board-superpowers:routing -->` ... `<!-- /board-superpowers:routing -->`), computes a SHA256 over the normalized block bytes, and records each non-stub target's hash under `state.yml:routing_blocks[]` for tamper detection. A short stub-redirect target (e.g., a `CLAUDE.md` that only contains `@AGENTS.md`) records no hash so the redirect stays canonical. Manual fallback: copy the canonical block from `${CLAUDE_PLUGIN_ROOT}/skills/using-board-superpowers/references/agentsmd-routing.md` between its `<!-- routing-block:start -->` and `<!-- routing-block:end -->` fences.

## Manual end-to-end fallback

When the scripts can't run for whatever reason (no shell access, missing `gh`, locked-down CI), reproduce the same end state by hand:

1. `mkdir -m 0700 -p ~/.board-superpowers/`.
2. Write `~/.board-superpowers/manifest.yml` with `schema_version: 2`, `host_bootstrapped_at`, `last_seen_version`, and `uv_version` keys (a v1 manifest without `uv_version` triggers the v1 → v2 migration on next run).
3. Create the GitHub Project (or use an existing one) with the canonical 6-option Status field.
4. Run `gh label create` for each of the four standard labels.
5. Write `<repo>/.board-superpowers/config.yml` with the `project: <owner>/<number>` line.
6. Add `*.local.*` and `.board-superpowers/.venv/` to `.gitignore`.
7. Install `uv`, copy `pyproject.toml` and `uv.lock` from the plugin's templates, run `uv sync`.
8. Copy the routing block out of `agentsmd-routing.md` between its fence sentinels and paste it into `AGENTS.md` + `CLAUDE.md` between the target marker pair.
9. Write `~/.board-superpowers/repos/<normalized>/state.yml` with `schema_version`, `repo_bootstrapped_at`, `last_seen_version_in_repo`, `features_enabled`, and `routing_blocks[]` (one entry per non-stub target file, each carrying `block_hash` and `injected_at`).
10. (Optional, only if configuring BYO RDBMS now) Write `~/.board-superpowers/credentials.yml` at chmod `0600` with a single `audit_db_url: "<dsn>"` line. Skipping this leaves audit writes in jsonl-only mode until the file is created later.

After any manual recovery, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh` to verify the result matches what the automated path would have produced.

## Smoke test

Open a fresh agent session in the repo. Type:

```
what should I work on
```

The session should auto-trigger the entry skill, which routes to `managing-board`'s daily routine and produces a morning briefing. If nothing triggers:

- On Claude Code: run `/plugin list` to verify the plugin is enabled.
- On Codex CLI: check `~/.codex/hooks.json` for the `SessionStart` entry; if missing, run `bash ${CODEX_PLUGIN_ROOT}/scripts/register-codex-hooks.sh --install-user`.
- On either platform: re-run `${PLUGIN_ROOT}/scripts/check-deps.sh`. Output is `0` exit code with empty stdout when everything is wired correctly; non-empty stdout names what's missing.
