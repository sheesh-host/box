<!--
Sync Impact Report
==================
Version change: (template) → 1.0.0
Bump rationale: Initial ratification of the project constitution (MAJOR baseline).

Principles defined (5):
  I.   Simplicity (YAGNI)
  II.  Test-First Discipline
  III. Modular Library Boundaries
  IV.  Issue-Tracked Workflow
  V.   Observability by Default

Added sections:
  - Engineering Constraints
  - Development Workflow & Quality Gates
  - Agent Preferences
  - Governance

Removed sections: none (template placeholders replaced).

Templates / docs reviewed for alignment:
  ✅ .specledger/templates/plan-template.md  — Constitution Check aligns (gate references present)
  ✅ .specledger/templates/spec-template.md  — no mandatory-section changes required
  ✅ .specledger/templates/tasks-template.md — testing/observability task types covered
  ✅ AGENTS.md / README.md                    — issue-tracking & workflow references consistent

Deferred TODOs: none.
-->

# Sheesh Box Constitution
<!-- Project: github.com/sheesh-host/box — the `sheesh` bootstrap CLI -->

## Core Principles

### I. Simplicity (YAGNI)
The box is a disposable, single-node projection of git — it MUST stay small and
obvious. Build the simplest solution that works; do NOT add abstractions,
configuration knobs, or features for hypothetical future needs. Complexity MUST
be justified by a present, demonstrated requirement. When two designs work,
prefer the one with fewer moving parts.
<!-- Rationale: a disposable box is only valuable if it is cheap to understand and rebuild. -->

### II. Test-First Discipline
Every package ships with co-located tests; new behavior MUST arrive with tests.
Prefer table-driven Go tests. Tests SHOULD be written or updated before or
alongside the implementation, and MUST fail before the fix/feature makes them
pass. `make test` MUST be green before a change is considered done.
<!-- Rationale: tests are the executable contract for a CLI that provisions real infrastructure. -->

### III. Modular Library Boundaries
`cmd/` MUST remain a thin shell: flag parsing, prompting, and wiring only.
Reusable logic lives in `pkg/*` so it can be shared by the CLI today and a
future `cmd/sheesh-server` tomorrow. Business logic MUST NOT live in command
handlers. Each `pkg/*` package owns one concern and exposes a small, testable
surface; cross-package coupling MUST be explicit and minimal.
<!-- Rationale: clean boundaries keep the CLI thin and the libraries reusable and unit-testable. -->

### IV. Issue-Tracked Workflow
All work MUST be tracked with `sl issue` (per AGENTS.md) — never markdown TODO
lists or external trackers. Commits MUST follow conventional prefixes
(`feat:`, `fix:`, `chore:`, `docs:`), stay imperative, and reference related
issues. Code changes and their `specledger/<spec>/issues.jsonl` updates MUST be
committed together.
<!-- Rationale: a single, git-native source of work keeps history auditable and avoids drift. -->

### V. Observability by Default
Anything that runs unattended on the box (boot scripts, git-sync, Caddy
integration, the future server) MUST be observable from the start: structured
logging, a health signal, and clear error surfaces are part of the design, not
an afterthought. The CLI MUST fail loudly with actionable messages rather than
silently.
<!-- Rationale: a remote, disposable box is only trustworthy if its state is visible. -->

## Engineering Constraints

- Go is the implementation language for the CLI and libraries; code MUST pass
  `golangci-lint run` (`make lint`) and `gofmt` (`make fmt`).
- The CLI supports both interactive (prompted) and `--non-interactive` flows;
  every prompt MUST have a corresponding flag so automation never blocks on a
  prompt.
- Infrastructure (Packer AMI, Terraform module) MUST stay declarative and
  reproducible; prefer rebuilding a box over patching one in place.
- Secrets (deploy keys, ACME data) MUST NOT be committed; handle them through
  the established channels (SSM Parameter Store, minted ed25519 keys).

## Development Workflow & Quality Gates

- Before a change is "done": `make test` passes, `make lint` is clean, and the
  related `sl issue` is updated/closed in the same commit.
- PRs include a concise summary, testing evidence (`make test`), and a CLI
  transcript or screenshots when behavior changes.
- Generated artifacts, docs, and `CHANGELOG`s MUST stay in sync with code
  (release-please / goreleaser drive releases).

## Agent Preferences

- **Preferred Agent**: Claude Code

## Governance

This constitution supersedes ad-hoc practice for the `sheesh-host/box` project.
Amendments require a PR that documents the change, its rationale, and a version
bump per the policy below; reviewers MUST verify the change complies with these
principles. Complexity that violates Principle I MUST be justified in the PR or
rejected.

Versioning policy (semantic):
- **MAJOR**: backward-incompatible principle removal or redefinition.
- **MINOR**: a new principle/section or materially expanded guidance.
- **PATCH**: clarifications, wording, or non-semantic refinements.

Compliance is reviewed at PR time and during `/specledger.verify` and
`/specledger.checkpoint` runs. Runtime development guidance lives in
[AGENTS.md](../../AGENTS.md) and [README.md](../../README.md).

**Version**: 1.0.0 | **Ratified**: 2026-05-26 | **Last Amended**: 2026-05-26
