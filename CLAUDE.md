# CLAUDE.md — Agent Entry Point

**Engine:** Godot 4.7-stable · GDScript 2.0 ONLY · Strictly Typed  
**Core Invariants:** See @./docs/CORE_INVARIANTS.md (Canonical single source of truth)  
**Verify:** `python3 tools/verify_gate.py --fast` (10 checks; 0 errors required)  
`gdcheck.py` alone is NOT sufficient — it treats autoloads as opaque types and cannot
see a call to a method that does not exist. `tools/lint_xref.py` in the gate catches that.  

## READ FIRST

Before implementing any feature:
1. @./POWERFOOTBALL_MASTER_VISION.md — Vision, roadmap, deep systems, agent protocol
2. @./docs/CORE_INVARIANTS.md — Canonical engine lock, simulation stack, and critical file contracts
3. @./docs/course_implementation_specification.md — Course-derived build phases, FSM blueprints, physics formulas, data models, gotchas & agent protocol (READ-ONLY)
4. @./ROADMAP.md — Tactical `[ ]`/`[x]` checklist
5. @.claude/rules/godot-47-core.md — Engine contracts
6. @.claude/rules/soccer-physics.md — Physics invariants
7. @.claude/rules/ai-architect.md — AI & spatial invariants
8. @.claude/rules/career-mode.md — Career layer (Layer 4) contracts

## Architectural Choke Points

- **Canonical Invariants:** All engine, spatial, and simulation laws are consolidated in `docs/CORE_INVARIANTS.md`.
- **Signal Bus:** ALL inter-system events → `GameEvents.gd` autoload.
- **Spatial Cache:** ALL NPC position reads → `MatchWorldModel.gd`.
- **Collision:** `CharacterBody2D` MUST NOT mask Layer 3 (Ball).
- **Brain Contract:** `PlayerBrain` writes ONLY to `player.movement_intent` and `player.wants_sprint`. Never touches velocity or acceleration.
- **Career State:** `CareerManager` owns the ONLY live `CareerSaveData`; the league itself stays owned by `DataLoader`. See @.claude/rules/career-mode.md.
- **Career → Match Bridge:** `PlayerFactory.apply()` is the single choke point where career morale seeds `MoodSystem` and career trust seeds `TrustSystem`.

## Boot Order (project.godot)

MatchWorldModel → GameEvents → GameManager → MatchStatsTracker → MatchTelemetryLogger → DataLoader → RefereeLoader → ManagerLoader → StaffLoader → WorldEventLog → CareerManager → InputHelper

`WorldEventLog` and `CareerManager` must stay AFTER the loaders they read
(`DataLoader`, `ManagerLoader`, `StaffLoader`, `RefereeLoader`), and
`WorldEventLog` before `CareerManager`, which binds it on career start.

## Process Priority

MatchWorldModel (-100) → PlayerBrain (0) → HeavyPlayerController (100)

## Squad Config

22 players total (11 per team), spawned declaratively as children of `$Players` in `pitch/PitchScene.tscn`.

## Shared Agent Memory

- Record runtime discoveries, edge cases, and proposed rules in `AGENTS_ERRATA.md`.
- `AGENTS_ERRATA.md` takes priority on recent decisions and is promoted to `.claude/rules/` and `docs/CORE_INVARIANTS.md` via `/sync-rules`.

## Context Budget — Claude Code Sessions

| Range | State | Action |
|-------|-------|--------|
| 0–50% | OPTIMAL | Full architecture work. Multi-layer features. Reference files inline. |
| 50–70% | MONITOR | Verify outputs against `docs/CORE_INVARIANTS.md` and `.claude/rules/`. Use grep for spot checks. |
| 70–85% | DANGER | Run `/compact` to compress prior messages. Do not start new features. |
| 85%+ | CRITICAL | Run `/compact` or `/clear` before next task. Major subsystem switches only. |

Switch major subsystems (physics ↔ AI, match ↔ career) with `/clear`. CLAUDE.md, CORE_INVARIANTS.md, and `.claude/rules/` survive both compaction and clear.
