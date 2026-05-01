# bootstrapping-repo — config-item protocol

Reference for the SKILL body's agentic stage dispatch. Read this when implementing or debugging an agentic stage: prompt kinds, validation rules, persistence mechanics, and re-prompt triggers.

## What is an agentic stage

An agentic stage is a setup-stages stage where the architect's input is required to determine the stage's target_state. The SKILL halts at every agentic stage and waits for a response before continuing.

Agentic stages are the sole mechanism for architect configuration in board-superpowers. They replace ad-hoc prompting inside SKILL bodies — the config-item protocol ensures each stage's interactive prompt, validation, and persistence are declared in one place (the registry) rather than scattered across SKILL prose.

## The five-element protocol

Every agentic stage in the registry declares:

1. **`interactive_prompt`** — the exact string surface to the architect. Written once in the stage's registry entry; the SKILL reads and surfaces it verbatim.
2. **`target_state_schema`** — JSON Schema (or its yaml equivalent) describing valid architect input. Used by the validation step.
3. **`prompt_kind`** — one of the five kinds below; determines how the SKILL renders the prompt and parses the response.
4. **`locality`** — where the accepted config item is persisted (one of the four settings files).
5. **`executor`** — the callable that takes the validated input and writes it to the locality settings file.

The SKILL body implements the protocol dispatch; the stage registry provides the per-stage content.

## Five prompt kinds

### 1. `single-choice`

Architect picks one option from a list. The SKILL renders the options as a numbered list.

```
Registry fields:
  prompt_kind: single-choice
  options: [opt_a, opt_b, opt_c]

Interaction:
  SKILL shows: "Choose one:\n  1. opt_a\n  2. opt_b\n  3. opt_c"
  Architect types: "1" or "opt_a" (both accepted)
  Validation: answer must resolve to one declared option
  Parse: extract the option string (not the number)
```

**Example** — M10 kanban projection choice:

```
prompt: |
  Which kanban backend should this repo use?
  1. github-project-v2  (GitHub Project V2 — default, no extra config)
  2. linear             (Linear — requires API token; available in v1.1)
  3. none               (No kanban — audit-log-only mode)
prompt_kind: single-choice
options: [github-project-v2, linear, none]
```

### 2. `multi-choice`

Architect picks one or more options. Returns a list.

```
Registry fields:
  prompt_kind: multi-choice
  options: [opt_a, opt_b, opt_c]
  min_choices: 1  (optional, default 0)

Interaction:
  SKILL shows: "Choose one or more (comma-separated):\n  1. opt_a\n  ..."
  Architect types: "1, 3" or "opt_a, opt_c"
  Validation: each selection resolves to a declared option; min_choices satisfied
  Parse: list of option strings
```

### 3. `free-text`

Architect types a free-form string. Regex validation optional.

```
Registry fields:
  prompt_kind: free-text
  validation_regex: "^[a-zA-Z0-9/._-]+$"  (optional)
  min_length: 1  (optional)
  max_length: 255  (optional)

Interaction:
  SKILL shows the prompt verbatim.
  Validation: regex match (if declared), length bounds
  Parse: stripped string value
```

**Example** — BYO-RDBMS DSN entry (M4 credential-setup):

```
prompt: |
  Enter your audit DB connection string (DSN).
  Allowed schemes: postgresql:// | postgres:// | mysql:// | mysql+pymysql:// | sqlite:// | sqlite3://
  Leave blank to decline (will use jsonl fallback; all A-class actions become R-class).
prompt_kind: free-text
validation_regex: "^(postgresql?://|mysql(\\+pymysql)?://|sqlite3?://|$)"
```

### 4. `boolean`

Architect confirms or declines a choice.

```
Registry fields:
  prompt_kind: boolean
  default: true  (optional)

Interaction:
  SKILL shows: "{prompt}\n[y/N]" (lowercase = default)
  Architect types: "y", "yes", "n", "no" (case-insensitive); Enter = default
  Validation: resolves to boolean
  Parse: true / false
```

### 5. `numeric-range`

Architect enters an integer within bounds.

```
Registry fields:
  prompt_kind: numeric-range
  min: 1
  max: 100
  default: 10  (optional)

Interaction:
  SKILL shows: "{prompt}\n[{min}–{max}, default {default}]:"
  Architect types: an integer, or Enter = default
  Validation: integer, within [min, max]
  Parse: int value
```

## Validation rules

For all prompt kinds:

- **Re-prompt once** on invalid input. Show the validation error message clearly.
- **HALT after two failed attempts**. Record `pending-architect-input` with `last_error` = the second validation error message. Do not substitute defaults — the architect's explicit choice is the point.
- **CI / scripted env**: if no response arrives within `session_lifetime`, treat as zero attempts and record `pending-architect-input` immediately. This is not an error — it is the correct behavior for non-interactive runs.

## Persistence rules

After accepting a valid response, the SKILL:

1. Calls `stage.executor(validated_input, repo_path, settings)` — the executor writes to the locality settings file via `bsp_settings_yml_write`.
2. Calls `stage.compute_target_state(repo_path)` — reads back what was just written.
3. Computes `target_state_hash = canonical_sha256(target_state, hash_excluded_fields)`.
4. Writes the `stages_completed` entry to the locality settings file.
5. Calls `bsp_classify_action` + `bsp_audit_write` with the completed state.

The executor is responsible for writing exactly one conceptual change. Multi-field config items use a single executor that writes all fields atomically.

## Re-prompt trigger

An agentic stage re-prompts on the next session if its `stages_completed` entry has:

- `status: pending-architect-input` (explicit HALT from a prior session), OR
- `status: failed` (executor returned non-zero after a valid input was accepted), OR
- `status: drifted` (generation bump detected by lifecycle diff — a new version may have changed the option set or default).

On `drifted`, the re-prompt preamble should acknowledge the prior value:

```
The {stage.name} configuration has changed in this plugin version.
Your previous answer was: {prior_target_state.value}
Please confirm or update:
{stage.interactive_prompt}
```

This prevents silent overwrite of architect configuration on plugin upgrade.

## Anti-patterns for agentic stage authoring

- **Do not provide defaults that bypass the architect.** An agentic stage MUST wait for architect input. Falling back to a default is the same as not prompting — the architect's session will surprise them when behavior differs from what they expect.
- **Do not split related config items into separate stages just to parallelize.** Dependent config items (e.g., projection choice → project URL) belong in a single stage with a multi-field executor.
- **Do not embed the prompt text in the SKILL body.** The `interactive_prompt` field in the registry is the single source of truth. The SKILL reads and surfaces it; it does not restate it.
- **Do not skip validation on "obvious" inputs.** Users who type "postgres://..." with a typo in the scheme will hit the jsonl fallback silently. Validate every input against the declared schema.
