# Observability

> **Status:** stub.

## Purpose

Define how a maintainer (or the architect using the plugin) knows
board-superpowers is healthy, not just installed. Today the plugin
offers `check-deps.sh` for install-time health and **nothing for
runtime health** — that's the gap this doc owns.

## Signals to expose (TBD)

Per Session and per Project:

- Stale claim count (with age distribution).
- Ghost worktree count (per machine — only the local Session can
  count its own).
- Re-split rate (cards split mid-flight / cards merged in window).
- Average Ready→Done duration (lead time).
- Average In Review duration (verification latency — the proxy
  for architect-as-bottleneck).
- WIP saturation rate.
- Protocol-violation rate (PRs failing Review Queue gate).
- Routing block drift (CLAUDE.md mirror vs reference).

## Mechanisms (TBD)

Candidate implementations:

- `scripts/health-check.sh` — runtime parallel of `check-deps.sh`,
  exits 0/2 with a structured report. Read by the SessionStart
  hook (already best-effort) and by Manager's Daily routine.
- A Daily routine sub-section dedicated to health (extending the
  current 4-section template with a "🩺 HEALTH" block).
- Retro signal aggregator — already partially in
  `retro-routine.md`; promote to a stable contract here.
- Optional: a `.board-superpowers/metrics/` JSON sink (gitignored)
  for time-series so retros can compare windows.

## What we explicitly don't track (TBD)

(Restate as architecture so questions like "should we add story
points" have a deterministic refusal.)

- No story points, no velocity. Cards are XS / S / M / L only.
- No per-Consumer performance metrics. Sessions are anonymous to
  the board.
- No SLA / SLO targets. Architects calibrate from retro signals,
  not from numeric thresholds.

## Observation boundaries (TBD)

- What's observable cross-machine (board state, branch state)
  vs only locally (worktree, plan brief, claim marker draft).
- What requires GitHub API quota vs filesystem-only.

## Open questions

- Should health metrics be opt-out or opt-in? Defaults matter for
  privacy (the retro report leak risk applies here too if
  metrics get committed).
- Is there a "fleet" view across multiple Projects, or always
  single-Project?
