# Mine Co. Multiplayer — Plans Index

**Spec:** [2026-05-08-multiplayer-design.md](../specs/2026-05-08-multiplayer-design.md)

This rollout is split into four phase plans. Each phase ships independently and is acceptance-tested before the next phase begins.

| # | Phase | Plan | Status | Detail level |
|---|-------|------|--------|--------------|
| 1 | MVP co-op (movement, mining, chat) | [phase-1-mvp.md](2026-05-08-multiplayer-phase-1-mvp.md) | Ready to execute | Full TDD bite-sized |
| 2 | Core economy (vendors, contracts, claims, boats) | [phase-2-economy.md](2026-05-08-multiplayer-phase-2-economy.md) | Drafted, re-detail before execution | Structural |
| 3 | Factories | [phase-3-factories.md](2026-05-08-multiplayer-phase-3-factories.md) | Drafted, re-detail before execution | Structural |
| 4 | Remaining systems (combat, builds, prestige) | [phase-4-remaining.md](2026-05-08-multiplayer-phase-4-remaining.md) | Drafted, re-detail before execution | Structural |

## Why structural plans for 2–4?

Phases 2–4 sit on top of foundations built in Phase 1 (the `Net` autoload, the bundled save schema, the request/broadcast RPC pattern). Until Phase 1 lands, exact line-number edits and code snippets for later phases would be invented. Each later plan defines:
- Tasks in execution order
- Files created vs. modified
- Acceptance criteria (lifted from spec)
- Test approach
- Risks specific to that phase

When Phase 1 ships, run the writing-plans skill again on the next phase's plan to upgrade it from structural to fully detailed before execution.

## Per-phase gating

Phase N+1 may not start until **all** of these are true for Phase N:
1. Every task in the plan is checked off.
2. All acceptance criteria from the spec pass in a 2-human playtest.
3. Single-player parity is confirmed (a solo player sees no behavior change).
4. Save-format migration from the previous version is verified with at least one real save file.

A short `MULTIPLAYER.md` lives at the project root from Phase 1 onward, tracking which phase is current and which features are guest-locked.

## Common conventions used by all phase plans

- **TDD where it pays.** GUT (Godot Unit Test) is the test framework. Pure-logic units (save serialization, RPC handler functions, validation helpers) are unit-tested. Integration paths (replication, late-join, lobby UI) use scripted manual smoke tests with two Godot instances on the same machine.
- **"Read first" steps.** Every task that modifies an existing `.gd` includes a `mcp__godot-ai__script_manage(op="read", ...)` step before editing, so the implementing agent works from current code, not assumed code.
- **Commit cadence.** One commit per logical task (test + implementation + manual-smoke pass). Commit messages follow `feat(mp): ...`, `test(mp): ...`, `refactor(mp): ...`, `fix(mp): ...`.
- **Single-player gate.** Every phase's last task is "verify single-player still loads from `res://scenes/main.tscn` with no errors and no behavior regressions."
