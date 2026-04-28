# BOOTSTRAP_STAGES_DEVELOPMENT.md (redirect to SETUP_STAGES_DEVELOPMENT.md)

This document was renamed. The canonical guide for the
plugin-wide setup-stages system (registry, lifecycle, the
5-callable contract, agentic config-item protocol, etc.) lives
in **[`SETUP_STAGES_DEVELOPMENT.md`](./SETUP_STAGES_DEVELOPMENT.md)**.

> **Why "setup" not "bootstrap"?** The system originally only
> covered first-time setup (hence "bootstrap"). It now also
> covers plugin-upgrade reconvergence and the agentic
> config-item elicitation flow — i.e., the plugin's settings
> UX. "Setup" is the broader and accurate name; "bootstrap"
> understates the scope. Rationale and ADR citations live in
> the canonical guide § 1.

> **Make all edits in `SETUP_STAGES_DEVELOPMENT.md`, not here.**
> Codex CLI will not auto-load this redirect file; this is a
> human-readable hint for readers searching for the legacy
> name. AGENTS.md references throughout the project point at
> the canonical doc.
