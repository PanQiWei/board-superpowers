### 1.4 Consumer surface

The capabilities a Consumer-role session exposes. Consumer is
the kanban-relative role from §1.2 — its purpose is to take
exactly one card from the board to terminal state (merged PR,
or a clean Blocked / Ready release with the failure context
captured back onto the board). Concrete Consumer sessions take
on **specific roles** that bundle related capabilities. v1 ships
one such specific role — **Implementer** — whose 14 features
are documented in §1.4.1. Future Consumer specific roles (e.g.,
a dedicated Reviewer that only handles review-cycle responses,
a dedicated Bisector that only handles regression-hunting cards)
become sibling subsections under §1.4.

This section is a **catalog of Implementer's capabilities
(features)** — the time-ordered combinations of these features
that an architect actually walks through are documented as
**flows in Part 2**, not here. Capability vs flow separation
parallels §1.3: capability = "what Consumer can do, time-
independent"; flow = "how the architect uses these capabilities
in order, over time." See §2.6 (Card consumption flow) for the
canonical implementation flow that composes F-C1–F-C14 into a
single end-to-end delivery.

**Cross-cutting principles applied throughout this section**
(every feature spec MUST honor):

- **D-AUTONOMY-1** (`adr/0006-producer-autonomy-boundary.md`):
  the matrix was authored from Producer's vantage but its row
  semantics apply symmetrically to Consumer where the action
  intersects a Consumer-side surface. Three rows are
  load-bearing for Consumer: row 8 (cancel claim — Consumer-
  initiated abandonment is R-class), row 12 (auto-merge — N for
  Consumer, hard floor), row 13 (Dispatch Consumer — relevant
  in Mode-2 wake-up). Audit-log entries from Consumer carry
  `actor_role: consumer` per §5 of ADR-0006.
- **C-PLUGIN-1 / -2 / -3**
  (`adr/0007-plugin-runtime-derived-constraints.md`): no
  in-memory cross-session IPC; no daemon thread; controlled
  Consumer-dispatch concurrency. Consumer surfaces all
  cross-session signals through GitHub artifacts (workaround
  (a)) or session-id reachback (workaround (b)). Consumer
  cannot push to Producer either — heartbeat is read by
  Producer from on-disk session-log mtime, never written by
  Consumer.
- **Multi-agent contracts** (`MULTI_AGENT_DEVELOPMENT.md`): the
  `max_depth=1` invariant (CC explicit, Codex documented as no
  nested spawn) means Consumer-spawned subagents are flat —
  Consumer cannot itself spawn a sub-Consumer. Skill invocation
  is in-process (current-agent context) and does NOT count as
  a spawn; this is what lets Consumer compose
  `superpowers:subagent-driven-development` while staying
  one-deep from the Producer that spawned it.
- **Mode topology** — Consumer runs in one of two modes:
  - **Mode-1** (architect-spawned interactive): the architect
    pastes a `[board-card:#N]` kick-off into a fresh CC or
    Codex CLI session. Both platforms supported. Mode-1 is the
    superset — any feature in this catalog works here.
  - **Mode-2** (Producer-spawned subagent): a Producer session
    spawns Consumer via the CC `Agent` tool. **Claude Code
    only at v1.** Codex Mode-2 is out of scope — Codex's own
    subagent ecosystem will handle Producer-spawn-Consumer
    natively in that platform's idiom; board-superpowers does
    not own that path.
  - Each feature below carries a **Mode compatibility** field
    (`Mode-1`, `Mode-2`, `both`). Features marked Mode-2-only
    or both-with-caveats name the constraint inline.
- **Governance pattern — default + override + accountability**:
  every governance dimension in board-superpowers (TDD
  exemption, permission boundary, board-mutation gradient,
  cross-card touch, stakeholder routing, etc.) follows the
  same shape — a sane default executes automatically;
  exceptions are allowed with friction (an explicit override
  or written justification); exceptions leave an audit trail
  (PR description, audit-log row, card thread comment). Now
  codified as **P8 in `0001-positioning.md`** (Default +
  override + accountability) — every governance feature in
  this section cites P8 as the root rationale.
- **One-card-one-worktree invariant**: every Consumer session
  binds to exactly one card and runs all post-claim work
  inside one worktree (`claim-card.sh`'s creation, default at
  `$HOME/.config/superpowers/worktrees/<project>/claim/<N>-<slug>`).
  N parallel Consumers therefore never share HEAD. The
  worktree persists across Mode-2 terminate-and-resume cycles
  and across Mode-2 wake-up.
- **Thin-pointer card**: the Card body (per
  `decomposing-into-milestones/references/card-schema.md`) is
  the Producer's contract surface, but for cards that need
  spec / plan / design depth beyond what fits inline, the body
  is a **thin pointer** — a link to the spec doc (in-repo
  under `docs/` or in third-party storage configured at
  bootstrap). Consumer self-fetches; Consumer never tries to
  re-derive a missing spec. Producer's input-completeness gate
  (Backlog → Ready transition, ADR-0006 row 5) is what
  guarantees the spec exists when Consumer arrives.

#### 1.4.1 Implementer (specific role)

An **Implementer** session is a Consumer-role session whose
specific role is **end-to-end card delivery** — claiming a
single Ready card, fetching its spec / plan / TDD acceptance
criteria, executing implementation through delegated skills,
running self-check + adversarial review, opening a PR, handling
review-cycle feedback, and terminating cleanly (success → self-
clean worktree; failure → Blocked with worktree preserved for
human takeover).

**Cardinality**: at most one Implementer per card (atomic claim
enforces this — `claim-card.sh` exit 10 on race-loss). Multiple
Implementer sessions across different cards is the normal
parallel-execution pattern, bounded by the WIP limit
(`config.yml:wip_limit`, default 5; counted as `In Progress` +
suspended + `In Review`; `Blocked` does NOT count).

**Session shape**: short-to-medium-lived (one card's worth of
work, claim through merge). Single-card scope (one master agent
= one kanban-relative role for the lifetime of the session, per
§1.2). The Consumer stays alive through PR merge — review-cycle
responses are handled by the same Consumer instance, NOT by a
re-spawned session. Per C-PLUGIN-2 there is no daemon between
moments of activity; the Consumer's lifecycle is paced by
either (a) the architect's interactive prompts (Mode-1), or
(b) Producer's preflight piggyback wake-ups (Mode-2).

**Trigger phrases** (route via the `consuming-card` skill
description matching, per `PLUGIN_DEVELOPMENT.md`):

| Architect (or Producer) says | Implementer activates (features) | Flow it composes (Part 2) |
|------------------------------|----------------------------------|---------------------------|
| `[board-card:#N]` (kick-off prompt, first message) | F-C1, F-C2, F-C3 → F-C5, F-C6 → F-C9, F-C10 → F-C12, F-C13 | §2.6 Card consumption flow (Manager-dispatched) |
| "claim card N" / "work on card N" / "pick up #N" | same as above | §2.6 |
| "pull a card from the board" (no number given) | F-C0 → F-C1 → … (full lifecycle) | §2.7 Card consumption flow (manual pull) |
| (review comment lands on Consumer's open PR) | F-C13 (review-cycle response) | §2.6 sub-flow |
| (Producer preflight wakes a Mode-2 Consumer) | F-C14 (resume from suspend) → continue lifecycle | §2.6 Mode-2 sub-flow |
| "abandon card N" / "release the claim" | F-C14 failure path (Blocked + release claim + keep worktree) | §2.6 escalation sub-flow |
| (architect responds to a surfaced question on a suspended Consumer) | F-C8 (surface protocol resume) | §2.6 surface sub-flow |

The 15 features below (F-C0 through F-C14) are Implementer's
complete capability surface at v1, grouped into 5 thematic
clusters for readability. Group-letter scheme parallels §1.3.1
but indices are independent — Producer F-04 and Consumer F-C4
are unrelated.

##### Group A — Bootstrapping

These features bracket the Consumer's birth: from kick-off
prompt to "the implementation environment is ready and
isolated."

###### F-C1. Atomic claim primitive

> The lowest-level write primitive on the Consumer side.
> Every other Consumer feature presupposes a successful claim
> exists; nothing below F-C1 calls `git push` directly.

- **Capability**: claim a Ready card atomically by pushing a
  remote `claim/<N>-<slug>` branch. First push wins; race
  losers exit cleanly with code 10 and never retry. Side
  effect: a marker file (`.board-superpowers/claims/<N>.claim`)
  is force-added to the claim branch as on-origin proof of
  claim. The branch is simultaneously (a) the atomic lock,
  (b) the feature branch the PR will target, and
  (c) a debugging aid (`git branch -r | grep claim/`).
- **Inputs**: card number `N`, short slug derived from card
  title (≤ 40 chars per `board-protocol`), optional
  `BOARD_SP_WORKTREE_DIR` / `.worktrees/` overrides, optional
  `BOARD_SP_SESSION_SLUG` for session tagging.
- **Outputs**: structured stdout — exactly two lines,
  `branch=claim/<N>-<slug>` then `worktree=<absolute path>`.
  Side effect: claim branch on origin with marker file;
  isolated worktree at the resolved path.
- **Composes**: `scripts/claim-card.sh` (the public-contract
  script) wrapping `git push --force-with-lease=<ref>:` for
  the lock + `git worktree add` for isolation, in one atomic
  step.
- **Maps to (canonical)**: Anderson 2010 *Kanban*, ch. 8 —
  pull-system claim semantics. The atomicity-via-git-push
  mechanism itself is board-superpowers original (no canonical
  agile/Kanban equivalent for distributed-lock-via-VCS).
- **Mode compatibility**: both. Identical behavior under Mode-1
  and Mode-2 — the script reads no mode-specific state.
- **Autonomy**: A for the claim itself (Consumer's defining
  action; no architect approval required since claim is the
  precondition for being a Consumer). Audit log entry written
  at claim time with `actor_role: consumer`,
  `payload: {card_number, branch, worktree, session_slug}`.

###### F-C2. Spec / plan / acceptance-criteria fetch

- **Capability**: read the Card body, follow the thin-pointer
  links to spec docs (in-repo `docs/` or third-party storage
  configured at bootstrap), and load TDD acceptance criteria
  Producer authored during Backlog → Ready (per ADR-0006 row 5
  precondition). Validate that the input bundle is complete
  before delegating implementation.
- **Inputs**: card number `N` (already bound from kick-off or
  F-C0 selection); the card body's section schema (Context /
  Acceptance Criteria / Out of Scope / Size / optional
  Execution Hints) per `board-protocol`.
- **Outputs**: a synthesized **plan brief** at
  `docs/board-superpowers/plans/card-<N>.md` (gitignored;
  Consumer-session scratch). The card body on GitHub remains
  the source of truth; the plan brief is the input shape
  `superpowers:subagent-driven-development` expects.
- **Composes**: `gh issue view <N>` for body fetch +
  `board-protocol` skill for schema validation + (where
  configured) the third-party-storage adapter for spec-doc
  fetch.
- **Maps to (canonical)**: Cohn 2009 — story refinement's
  "ready-to-pull" criterion (the Definition of Ready half).
  Synthesizing a plan brief from a card body is board-
  superpowers original — canonical agile assumes the team
  reads the card directly.
- **Mode compatibility**: both. In Mode-2, the plan brief is
  written to disk in the worktree where Producer's `Agent`
  tool spawned the Consumer; persistence across Mode-2
  terminate-and-resume cycles is a free benefit (worktree
  invariant).
- **Autonomy**: A (read + scratch-write only; no GitHub
  state mutation). No audit log entry needed.

###### F-C3. Worktree entry + In Progress transition

- **Capability**: enter the isolated worktree (`cd $WORKTREE`)
  and transition the card from `Ready` to `In Progress`. After
  this step, every further action runs inside the worktree
  (so parallel sessions cannot trample each other's HEAD); and
  the board reflects that this card is being actively worked.
  The transition + first claim comment together make the
  Consumer visible to Producer's preflight read.
- **Inputs**: `$WORKTREE` from F-C1 stdout; project ref from
  `.board-superpowers/config.yml`.
- **Outputs**: process cwd is now `$WORKTREE`; card status is
  `In Progress`; first card comment posted with session slug,
  branch name, and worktree path.
- **Composes**: `cd` (process state) + `scripts/transition-
  card.sh` (Project v2 status mutation) + `gh issue comment`
  (audit-trail comment).
- **Maps to (canonical)**: Anderson 2010 — kanban "pull"
  visualization (the pulled card visibly moves to In Progress).
- **Mode compatibility**: both.
- **Autonomy**: A (per ADR-0006 row 13's symmetric Consumer-
  side action — Consumer transitioning its own claimed card to
  `In Progress` is the trivial follow-on to F-C1's claim).
  Audit log entry written.

###### F-C0. Self-selection from Ready (manual-pull entry)

> Optional bootstrap step that fires when the kick-off prompt
> did NOT name a card (`pull a card from the board` /
> `start on the board card` / similar). Listed last in
> Group A because it is conditional on kick-off shape.

- **Capability**: query the Ready column, filter (deps
  satisfied, optional size hint, oldest-first among ties),
  surface the top 3 candidates, and **wait for one-shot
  architect confirmation** before proceeding to F-C1. The
  hard rule: do not silently pick a card.
- **Inputs**: project ref + optional kick-off hints ("pick a
  small one" / "warm-up" → prefer `size:XS` / `size:S`).
- **Outputs**: a numbered candidate list (3 entries max) +
  blocking wait for architect's reply. On `none`, session
  ends cleanly with no side effects.
- **Composes**: F-01 (atomic kanban query primitive from §1.3)
  + dependency-satisfaction parsing of `Depends on #D, #E`
  lines from candidates' Context section.
- **Maps to (canonical)**: Anderson 2010 — pull-system
  voluntary-take semantics. The "ask before pulling" gate is
  board-superpowers original (canonical Kanban assumes the
  worker is trusted to pull; here the worker is an AI agent
  with non-zero risk of mis-claim).
- **Mode compatibility**: Mode-1 only. Mode-2 always carries
  `[board-card:#N]` from Producer's dispatch — F-C0 is
  unreachable in Mode-2 by construction.
- **Autonomy**: N/A for the query (read-only). The downstream
  claim (F-C1) carries its own autonomy mapping.

##### Group B — Implementation

These features cover the active-work phase: from "worktree
ready" to "implementation done, ready to PR". The shared
discipline: Consumer **delegates** real implementation work to
existing skills via in-process Skill invocation, never re-
implements TDD / debugging / parallel-task orchestration.

###### F-C4. TDD-driven implementation delegation

- **Capability**: invoke the appropriate execution skill (per
  the handoff matrix in
  `consuming-card/references/handoff-to-superpowers.md`) with
  the F-C2 plan brief as input. Default path is
  `superpowers:subagent-driven-development` (~80% of cards);
  alternates are `superpowers:executing-plans` (subagent-
  unavailable fallback) and `gstack:/qa` after `gstack:/review`
  (UI-heavy / visual cards). The execution skill owns
  RED-GREEN-REFACTOR; Consumer **strictly executes** what the
  Producer's TDD plan dictated, never re-plans the test
  decomposition mid-flight.
- **Inputs**: plan brief from F-C2; `$BRANCH` and `$WORKTREE`
  from F-C1; project test commands (discoverable from
  `CLAUDE.md` / `package.json` / `Makefile`).
- **Outputs**: implementation diff on the claim branch + status
  signal from the execution skill (DONE / DONE_WITH_CONCERNS /
  NEEDS_CONTEXT / BLOCKED).
- **Composes**: `superpowers:subagent-driven-development`
  (default) / `superpowers:executing-plans` /
  `superpowers:test-driven-development` (when invoked
  directly) / `gstack:/review` + `gstack:/qa` (UI path).
  All called via in-process Skill invocation — Consumer's
  skill stack does NOT spawn additional subagents (the
  delegated skill may, but `max_depth=1` from
  `MULTI_AGENT_DEVELOPMENT.md` constrains the topology to one
  level total when Consumer is itself a Mode-2 subagent).
- **Maps to (canonical)**: Beck 2002 *Test-Driven Development*
  (RED-GREEN-REFACTOR); *eXtreme Programming Explained*
  (Beck 1999) — pair-programming-style two-stage review
  (`subagent-driven-development`'s spec-compliance + code-
  quality reviewers).
- **Mode compatibility**: both, with caveat. In Mode-2 (CC
  Consumer-as-subagent), `superpowers:subagent-driven-
  development`'s ability to spawn its own internal subagents
  must be empirically verified against `max_depth=1` (see
  Notes). If it spawns subagents, Mode-2 falls back to
  `superpowers:executing-plans` (procedural, no further spawn).
- **Autonomy**: A for the delegation choice and for
  implementation actions inside the claimed worktree (engineer-
  norm "soft default" of the permission gradient — see F-C7).
  Audit log entry written for the delegation choice (which
  skill was picked and why).

###### F-C5. TDD-skip mechanism (default-by-category + override)

- **Capability**: govern when TDD red-green is skipped via the
  recurring **default + override + accountability** pattern.
  Defaults are by `type:*` label:
  `type:docs` / `type:chore` → exempt; `type:feat` /
  `type:fix` → required. Consumer may override the default
  (skip a required-by-default card, or test a default-exempt
  card) — but every override **MUST** be justified in the PR
  description. Plugin-layer enforcement: a missing
  justification line for a TDD-skip is a structural PR
  violation flagged by Producer's Review Queue routine
  (F-02).
- **Inputs**: card's `type:*` label; Consumer's judgment that
  a card is "untestable / not worth testing" (override
  trigger).
- **Outputs**: either TDD red-green ran (default path) or a
  PR-description line under Automated Verification:
  `TDD skipped because: <one-line reason>`.
- **Composes**: F-C4 (the execution skill that would run TDD)
  + F-C9 (PR description writing — where the override
  justification lands).
- **Maps to (canonical)**: Beck 2002 — TDD's own author
  acknowledges contexts where TDD is suspended (spike
  solutions, throwaway exploratory code). The skip-with-
  written-justification protocol is board-superpowers original.
- **Mode compatibility**: both.
- **Autonomy**: A for the default behavior (no architect
  approval needed to follow the per-`type:*` default); A for
  the override itself (Consumer's judgment), provided the
  written justification lands in the PR. No separate audit-log
  entry — the PR description IS the audit trail for this
  override.

###### F-C6. Cross-card touch hard refuse

- **Capability**: detect when in-flight work would mutate a
  file owned by another card (whether that card is in
  Backlog, Ready, In Progress, In Review, or Done) and
  **hard-refuse the touch**. The Consumer never silently
  edits across cards — instead it surfaces (via F-C8) and
  transitions to Blocked (F-C13). This is the Consumer-side
  mirror of D-AUTONOMY-1 row 12's R-class principle: "never
  silently extend scope across the boundary the architect
  drew."
- **Inputs**: file paths the execution skill is about to write;
  card-to-file ownership inferred from (a) the current card's
  Acceptance Criteria + Out of Scope sections, and (b) other
  cards' acceptance criteria where overlap is suspected.
- **Outputs**: refusal at the file-write moment + surfaced
  message via F-C8 ("touched X which appears to belong to
  card #M; need architect arbitration").
- **Composes**: F-C8 (surface protocol) + F-C13 (Blocked
  transition) + the in-worktree file-watching that the
  execution skill exposes.
- **Maps to (canonical)**: no direct canonical-agile
  equivalent. Closest precedent: the "Definition of Done"
  per-Card scope discipline from Scrum Guide 2020. The
  hard-refuse-then-surface mechanism is board-superpowers
  original.
- **Mode compatibility**: both.
- **Autonomy**: R (matrix row 4 / row 8 analog — cross-card
  structural change is exactly the "cross-card structural
  change" triage rule entry). Audit log entry on detection +
  on resolution.

###### F-C7. Permission boundary (three-layer)

- **Capability**: govern what Consumer is allowed to do inside
  its worktree without further approval. Three layers, in
  decreasing autonomy:
  - **Soft default** (engineer-norm mindset): read/write
    code, install dependencies via the project's own package
    manager, modify CI files when in scope of the card's
    Acceptance Criteria, call test-environment APIs.
  - **Ambiguity fallback**: when uncertain whether an action
    falls inside the soft default, surface (F-C8) — never
    pre-refuse, never self-grant.
  - **Hard floor** (regardless of model judgment): no
    committing real secrets, no `rm -rf` outside the
    worktree, no force-push to `main` or any shared branch,
    no deletion of remote branches owned by other claims.
    Plugin-layer enforced via hooks + tool whitelists; the
    specific list is TBD (see Notes).
- **Inputs**: every prospective tool call from the execution
  skill (the Soft default and Hard floor are evaluated
  per-call); all surfaces visible to the Consumer (the
  ambiguity check is a continuous judgment).
- **Outputs**: tool call proceeds (Soft default), surfaces
  (ambiguity fallback), or is hard-blocked (Hard floor with
  audit-log entry of the blocked call).
- **Composes**: hooks (`hooks/hooks.json` + future
  `PreToolUse` registration) + tool-allowlist machinery from
  the host platform (CC `allowed-tools` frontmatter / Codex
  `sandbox_mode` per-role TOML).
- **Maps to (canonical)**: software-engineering professional
  norms broadly (the Soft default reflects "what a
  reasonable engineer would do without asking"). The
  three-layer formalization with explicit Hard floor is
  board-superpowers original.
- **Mode compatibility**: both.
- **Autonomy**: A for Soft-default actions; R for ambiguity-
  fallback escalations (handled by F-C8); N (effectively) for
  Hard-floor actions — they are blocked at the plugin layer
  and cannot be promoted via `autonomy_overrides:` until a
  future security ADR specifies which floor entries are
  promotable. Audit log mandatory for every Hard-floor block.

###### F-C8. Surface protocol (suspend on uncertainty)

- **Capability**: when an extensible set of triggers fires,
  Consumer **surfaces once** and enters a logical-suspend
  state instead of guessing or self-filling. Triggers (open-
  ended; new triggers can be added without changing this
  feature's contract):
  - Card spec / plan insufficient (artifact missing despite
    Producer's Ready gate).
  - Design decision point with multiple legitimate approaches.
  - Debug stuck after self-attempting a fix N times red.
  - Cross-card touch realization (per F-C6).
  - Acceptance criteria contradicts itself or is unreachable.
- **Inputs**: the trigger event (one of the above);
  Consumer's current Mode (1 or 2).
- **Outputs**: under both Modes, a card-thread comment is
  posted (the **primary** channel — board-mediated, closes
  under C-PLUGIN-1 workaround (a)). Under Mode-1, also
  written to stdout (architect responds interactively in the
  same terminal). Under Mode-2, the CC `SendMessage` tool MAY
  be used as an optional latency-optimization signal to the
  Producer, but is **never load-bearing** — the card-thread
  comment is the contract.
- **Composes**: `gh issue comment` for the card-thread post +
  (Mode-1) terminal stdout + (Mode-2 optional)
  `SendMessage` per `MULTI_AGENT_DEVELOPMENT.md` §1.
- **Maps to (canonical)**: Toyota *jidoka* (stop-the-line on
  detected defect, *Toyota Production System*, Ohno 1988
  ch. 2). The "surface once then suspend" form (vs continuous
  retry) is board-superpowers original — required because
  the Consumer is an AI agent whose continuous retries burn
  tokens with low marginal information.
- **Mode compatibility**: both, channel-divergent (see
  Outputs).
- **Autonomy**: R-class (the surface IS the propose-and-await
  mechanism). Audit log entry on surface; second entry when
  the architect's response is received and the Consumer
  resumes (F-C14).

##### Group C — Self-check & adversarial review

These features run after implementation completes and before
PR submission. The shared discipline: evidence-first (per
`superpowers:verification-before-completion`) and adversarial-
by-construction (multiple independent reviewers, including
cross-platform).

###### F-C9. Pre-submit verification chain

- **Capability**: before opening the PR, run the canonical
  verification chain in order: (1)
  `superpowers:verification-before-completion` — evidence
  gathering, no claim of "done" without it; (2)
  `superpowers:requesting-code-review` — independent code
  review pass; (3) `gstack:/review` — production-bug
  viewpoint. Each step must produce a recorded outcome that
  feeds into PR section F-C10's Automated Verification body.
- **Inputs**: implementation diff on the claim branch; the
  card's Acceptance Criteria for spec-compliance check.
- **Outputs**: a verification record (commands run, outcomes,
  any concerns flagged) that becomes the seed for PR section
  `## Automated Verification`.
- **Composes**: `superpowers:verification-before-completion`
  + `superpowers:requesting-code-review` + `gstack:/review`,
  all via in-process Skill invocation.
- **Maps to (canonical)**: *Code Complete* (McConnell 2004) —
  the multi-pass review discipline; *Accelerate* (Forsgren et
  al. 2018) — pre-merge verification as a deployment-quality
  signal.
- **Mode compatibility**: both.
- **Autonomy**: A (pre-submit checks are a Consumer
  responsibility, no architect approval needed). Audit log
  entry per skill invocation outcome.

###### F-C10. Cross-platform adversarial review

- **Capability**: invoke a review pass on **a different
  platform than the Consumer is running on**. From a CC
  Consumer session, call `gstack:/codex` so OpenAI's Codex
  evaluates the same diff. From a Codex Consumer session,
  the reverse path (CC review) is honored where platform
  availability allows. The economic point: independent-
  evaluator-class review catches model-shaped blindspots that
  same-platform review misses by construction.
- **Inputs**: the implementation diff (committed on the
  claim branch); the card's spec / acceptance criteria.
- **Outputs**: cross-platform review verdict + concerns
  list, folded into PR section F-C10 (`## Automated
  Verification` notes the cross-platform pass).
- **Composes**: `gstack:/codex` (CC → Codex direction); the
  reverse direction is the cross-platform-symmetric analog
  per platform availability.
- **Maps to (canonical)**: no direct canonical-agile
  equivalent. The closest software-engineering precedent is
  multi-vendor dependency analysis; the cross-platform-AI-
  review framing is board-superpowers original (and is itself
  a downstream consequence of P4b — composition is permanent
  — applied to model diversity).
- **Mode compatibility**: both. Mode-2 must additionally
  verify the cross-platform skill is reachable from the
  spawn context (the Producer that spawned the Mode-2
  Consumer must have made `gstack:/codex` available).
- **Autonomy**: A. Audit log entry per cross-platform
  invocation.

###### F-C11. Conditional QA / security passes

- **Capability**: invoke conditional review skills based on
  the card's surface area:
  - `gstack:/qa <url>` — UI cards only (presence of
    `## Execution Hints: ui` / `type:ui` label / explicit
    architect direction). Real-browser QA via gstack's
    Playwright integration.
  - `gstack:/cso` — security audit. **Not mandatory per
    card.** Triage-driven: invoked when the card's risk
    class warrants it (Producer's triage routine F-10 may
    add a `risk:security` label, or the architect requests
    explicitly). Whether `gstack:/cso` should be triage-
    driven for some specific subset of cards by default is
    flagged TBD (Notes).
- **Inputs**: card labels (`type:ui`, `risk:security`); card
  body's Execution Hints; for `/qa`, a runnable URL (staging
  or local dev server).
- **Outputs**: pass/fail + concerns folded into PR section
  F-C10.
- **Composes**: `gstack:/qa` + `gstack:/cso`, conditionally.
- **Maps to (canonical)**: OWASP Top 10 (`/cso` covers the
  catalog); STRIDE threat modeling (`/cso` invokes); end-
  user usability testing (`/qa`).
- **Mode compatibility**: both. Mode-2 caveat: `/qa` requires
  a running browser instance — when Mode-2 runs in CI / non-
  interactive contexts (CC `--bare` mode etc.), `/qa` may
  not be reachable; the Consumer surfaces (F-C8) rather than
  silently skipping.
- **Autonomy**: A for invocation; the conditional skip when
  the card is non-UI / non-security is itself default
  behavior (no override needed). Audit log entry per
  invocation.

##### Group D — PR submission & review-cycle response

These features cover PR creation through merge. The shared
discipline: the PR is the contract between Consumer and the
rest of the system (architect, Producer, future Consumers
reading retro notes); its structure is rigid by design.

###### F-C12. PR submission with mandatory sections

- **Capability**: open the PR via the appropriate skill
  (`superpowers:finishing-a-development-branch` default;
  `gstack:/ship` for projects with VERSION/CHANGELOG
  conventions). Then **append** the protocol-required
  sections to the generated PR body. Recommended title shape:
  `[card:#N] <verb> <area>`. Strong-recommend MUST: link to
  the card and to the spec doc(s) in the PR description.
  Required sections (per §1.8):
  - `## Automated Verification` — required: what tests ran,
    what passed.
  - `## Human Verification TODO` — **OPTIONAL** for low-risk
    cards (omit cleanly when no end-to-end human check is
    needed; do not write filler). Source: Producer's plan +
    Consumer's implementation-time additions.
  - `## Retro Notes` — required when reusable lessons exist;
    **knowledge-harvesting only**, NOT estimate-vs-actual /
    KPI / throughput metrics. Initially written at PR
    submit; supplemented after merge with review-cycle
    insights.
- **Inputs**: implementation diff; F-C9 / F-C10 / F-C11
  outputs (for Automated Verification body); card body (for
  link); spec docs (for link).
- **Outputs**: open PR with the protocol-compliant body and
  trailing `<!-- board-superpowers:pr -->` marker (per
  `board-protocol`); card transitioned to In Review (handled
  by F-C12's caller-side glue).
- **Composes**: `superpowers:finishing-a-development-branch`
  / `gstack:/ship` (for the base body) +
  `consuming-card/references/pr-template.md` (for the
  appended sections).
- **Maps to (canonical)**: Scrum Guide 2020 — Definition of
  Done per-increment; *The Phoenix Project* (Kim 2013) —
  hand-off contracts between work stations.
- **Mode compatibility**: both.
- **Autonomy**: A for the PR opening (Consumer's defining
  output). Audit log entry written at PR submit with PR
  number, branch, card-link.

###### F-C13. Review-cycle response

- **Capability**: when review feedback lands on the open PR
  (architect comments, non-architect comments, automated
  reviewer comments — all treated comment-source-agnostic),
  the **same Consumer instance** stays alive to respond.
  Re-PR mechanism: new commit + push (history preserved by
  default); force-push to own branch is allowed for explicit
  fixup / rebase work. Multiple review cycles are normal;
  each cycle may invoke F-C9 / F-C10 / F-C11 again as
  appropriate. Stakeholder routing (PM / designer / customer
  comments on the PR thread): default integrate-as-context;
  surface (F-C8) when the comment has scope / semantic
  implications beyond the original card.
- **Inputs**: PR review comments (from any GitHub user);
  current implementation state.
- **Outputs**: new commits on the claim branch + reply
  comments on the PR thread + (when a structural change is
  needed) updated PR description.
- **Composes**: `gh pr view --comments` (poll on prompt) +
  F-C4 (re-delegation for non-trivial fixes — small one-line
  fixes can be made directly per `handoff-to-superpowers.md`)
  + F-C9 / F-C10 / F-C11 for re-verification.
- **Maps to (canonical)**: the iterative review loop in
  *Continuous Delivery* (Humble & Farley 2010); *Accelerate*
  (Forsgren et al. 2018) — short review-cycle time as a
  velocity multiplier.
- **Mode compatibility**: both. Mode-2 critical caveat:
  Consumer alive **from claim through merge**, NOT just
  through PR-submit. Producer's preflight piggyback is what
  detects "review comment landed; wake the Consumer if it
  was suspended" — see F-C14.
- **Autonomy**: A for direct one-line fix responses (per
  handoff guide); A for re-running F-C9 / F-C10 / F-C11; R
  when the review comment implies cross-card scope
  expansion (surfaces via F-C8). Audit log entry per
  response cycle.

##### Group E — Termination & handoff

These features cover the Consumer's exit. The shared
discipline: terminate cleanly under both success and failure;
preserve enough state for human takeover when failure happens;
write retro notes that aggregate into Producer's F-12 retro
routine.

###### F-C14. Termination + heartbeat

- **Capability**: terminate cleanly along one of three paths:
  - **Success path**: PR merged → write retro note (the
    "knowledge harvesting" half of `## Retro Notes`,
    supplemented post-merge with review-cycle insights) →
    self-delete worktree (`git worktree remove --force`) →
    process exits.
  - **Failure path** (debug-limit hit, irrecoverable
    NEEDS_CONTEXT, or hard-refuse from F-C6): mark card
    `Blocked` + write failure-context note in card thread +
    **release the claim** (logical exclusivity returned) +
    **KEEP the worktree** (physical sandbox preserved for
    human takeover) → process exits.
  - **Crash path** (process died without clean exit):
    Producer detects via on-disk session-log mtime — for CC,
    `~/.claude/projects/<dir>/<session-id>.jsonl`; for
    Codex, `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
    **Zero new infrastructure** — Consumer writes nothing
    extra; the heartbeat IS Producer reading the platform's
    session-log file mtime.
  Mode-2 wake-up (Consumer suspended via F-C8, then resumed
  by Producer): respects D-AUTONOMY-1 row 13 (Dispatch
  Consumer = A); architect can override to R via
  `autonomy_overrides:` if they want manual approval before
  every Mode-2 wake-up.
- **Inputs**: terminal state from F-C12 (PR opened) + later
  signal of merge (success path) OR escalation signal (F-C6 /
  F-C8 / unrecoverable BLOCKED from F-C4).
- **Outputs** (per path):
  - Success: card `Done` (via GitHub auto-close on merge),
    worktree absent, retro note in PR description.
  - Failure: card `Blocked`, claim released (the claim
    branch may stay for forensic value or be cleaned by
    architect), worktree present at the original path,
    failure-context comment on card.
  - Crash: nothing written by Consumer; Producer's preflight
    piggyback infers staleness from session-log mtime + GH
    timestamps.
- **Composes**: `git worktree remove --force` (success) +
  `transition-card.sh` to `Blocked` (failure) + `gh issue
  comment` (failure note) + Producer-side reads of
  `~/.claude/projects/...` / `~/.codex/sessions/...` (crash
  detection, written by the platform; nothing for Consumer
  to do).
- **Maps to (canonical)**: TPS *poka-yoke* (fail-safe design
  on the failure path — preserving the worktree when
  terminating is exactly "make the next operator's job
  easy"). The mtime-based heartbeat is board-superpowers
  original, derived from C-PLUGIN-2 (no daemon).
- **Mode compatibility**: both. Mode-2-specific addition:
  card stores Consumer's session-id (in body or comment, as
  an existing artifact) so Producer's preflight can stat()
  the right session-log file.
- **Autonomy**: A for success-path termination (the trivial
  follow-on to merge); R for failure-path Blocked
  transition (per ADR-0006 row 6 — "interrupts in-flight
  work"); N/A for crash (Consumer is dead).

#### 1.4.2 (reserved for additional Consumer specific roles)

Future Consumer specific roles (e.g., a dedicated Reviewer
that only handles review-cycle responses, a dedicated Bisector
for regression cards, a dedicated Migration runner) become
subsections here. v1 ships only Implementer.

**Notes on TBD values** (deferred to first lived-data
calibration or to a downstream ADR):

- **F-C7 Hard-floor enumeration**: the specific list of
  forbidden secrets-detection patterns, forbidden paths
  (`rm -rf` exclusion zones), and forbidden git operations
  (which branches count as "shared"). Deferred to a future
  security-focused ADR; until that lands, the
  `consuming-card` skill ships a conservative starting list
  and surfaces F-C8 on edge cases.
- **F-C4 Mode-2 + `superpowers:subagent-driven-development`
  empirical verification**: the `max_depth=1` invariant
  forbids a Mode-2 Consumer from spawning subagents. Whether
  `superpowers:subagent-driven-development` itself spawns
  subagents (and therefore is unusable in Mode-2) needs
  empirical verification during implementation. If
  unusable, Mode-2 falls back to
  `superpowers:executing-plans` automatically; this fallback
  rule must be wired into `consuming-card/SKILL.md` Step 3
  before Mode-2 ships.
- **F-C11 `gstack:/cso` triage policy**: whether `/cso`
  should be triage-driven for some subset of cards (e.g.,
  every card touching `auth/` paths, every card with a
  `risk:security` label) by default — vs. always-on-demand —
  needs lived-data calibration. Initial behavior: on-
  demand only.
- **Promotion of "default + override + accountability" to
  positioning P8**: this pattern (sane default + explicit
  override + audit-trail) is now codified as **P8 in
  `0001-positioning.md`** (Default + override + accountability).
  Every Consumer governance feature here (F-C5 TDD-skip, F-C6
  cross-card touch refuse, F-C7 permission boundary, F-C13
  stakeholder routing) is an instance of P8; cite P8 as root
  rationale rather than re-deriving the pattern per feature.

These are deliberately left TBD per D-META-1 (P7) — defaults
are starting points; the architect (and the implementation
process itself) captures the project-specific values during
real use.

