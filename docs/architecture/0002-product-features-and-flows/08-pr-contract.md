### 1.8 PR contract

Every Consumer PR ships with a fixed body shape. The base
sections (Summary / Test Plan) come from whichever PR-creation
skill ran (`superpowers:finishing-a-development-branch` or
`gstack:/ship`); Consumer **appends** the protocol-required
sections + a trailing marker. Per `board-protocol/SKILL.md`:

```
## Summary             (from delegated skill)
## Test Plan           (from delegated skill)
## Automated Verification     (Consumer writes; required)
## Human Verification TODO    (Consumer writes; OPTIONAL)
## Retro Notes                (Consumer writes; required when reusable lessons exist)

Closes #<card>.

<!-- board-superpowers:pr -->
```

The marker `<!-- board-superpowers:pr -->` is what lets
managing-board's Review Queue routine find board-superpowers
PRs among ordinary ones. Per ADR-0006 / I-2, the PR is the
contract between Consumer and the rest of the system; its
structure is rigid by design.

#### 1.8.1 `## Automated Verification`

**Required on every PR.** Source: F-C9 verification chain
output, augmented by F-C10 (cross-platform adversarial review)
and conditionally F-C11 (UI / security passes). Lists what
ran, what passed, what concerns surfaced, with concrete
evidence: commit ranges, command outputs, link to CI runs.
Reviewer checks for two things: (a) the verification chain
actually ran (not just a "tests pass" assertion), and
(b) F-C10's cross-platform pass result is named explicitly with
attribution to the platform that ran it (CC → Codex via
`gstack:/codex`, or the reverse). Maps to canonical: McConnell
2004 *Code Complete* multi-pass review discipline; Forsgren
et al. 2018 *Accelerate* — pre-merge verification as a
deployment-quality signal. Original framing: the **explicit
cross-platform attribution line** is board-superpowers
operationalization of P4b (composition is permanent) applied to
model diversity.

#### 1.8.2 `## Human Verification TODO`

**OPTIONAL** — not every PR. Source: Producer's plan (carried
over from the card body's Acceptance Criteria during F-02 and
the F-08 / F-09 design pass) plus Consumer's
implementation-time additions discovered during F-C4. Lists
end-to-end steps the architect needs to do that aren't
automatable: visual checks, real-environment smoke tests,
data-shape sanity checks the test suite can't reproduce.

Low-risk cards omit the section cleanly when no end-to-end
human check is needed — `type:docs`, `type:chore`, small bug
fixes without UI surface area. **Omitting the section is
allowed; writing filler is not.** The contract is that *if* a
section is present, every item in it is a real check the
architect should perform. Producer's F-02 review-queue routine
flags PRs that have a Human Verification TODO whose items look
like filler ("verify it works", "make sure tests pass") as
contract violations. Maps to canonical: Cockburn 2001
*Agile Software Development* — the human-loop verification
discipline. Original framing per P6: making this section a
first-class output (when present) is the operationalization
of architect-attention-as-bottleneck.

#### 1.8.3 `## Retro Notes`

**Required when reusable lessons exist.** **Knowledge
harvesting only** — captures reusable patterns, pitfalls,
decisions worth carrying forward. Explicitly NOT
estimate-vs-actual; NOT velocity; NOT throughput / KPI
metrics. The "I learned X about this codebase / this pattern /
this tool" half of the work, written so the next Consumer
session reading the same area benefits.

Two-pass authorship:
- **Initial pass at PR-submit (F-C12)** — implementation-phase
  insights that are fresh in Consumer's context.
- **Supplemented post-merge** — review-cycle insights from
  F-C13 (reviewer comments that surfaced patterns or
  anti-patterns) added before final merge so the merged PR
  body is the complete record.

Feeds Producer's F-12 (Retro routine) via card-thread
aggregation: F-12 walks Retro Notes from the trigger window
(milestone close, N-cards-completed, or detected drift) and
synthesizes a structured retro per Derby & Larsen 2006 5-stage
format. Maps to canonical: Derby & Larsen 2006
*Agile Retrospectives* — the format. Original framing:
**knowledge-harvesting framing instead of metric-aggregation
framing** — board-superpowers explicitly drops the Sprint
retrospective's velocity-tracking half (per §1.1's
"calendar cadence is incoherent at AI throughput") and keeps
only the qualitative-learning half.

---

