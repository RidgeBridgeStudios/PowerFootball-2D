## PowerFootball-2D — Agent Entry Point

**Engine:** Godot 4.7-stable · GDScript 2.0 ONLY
**Verify:** `python3 tools/gdcheck.py`
(Static GDScript checker; no engine binary in CI.)

## Multi-Agent Sync

AGENTS.md at the repo root is the flattened, self-contained mirror of this file
for non-Claude agents (DeepSeek, opencode-go models, etc.) that do not auto-load
.claude/rules/.

Sync contract:
- Any new architectural law added here MUST also be added to AGENTS.md Section 3
  in the same session.
- Any new .claude/rules/*.md file MUST have its key prohibitions mirrored in
  AGENTS.md Section 3 or Section 9.
- ROADMAP.md checkbox changes MUST be mirrored in AGENTS.md Section 5 tables.
- Non-Claude agents write rule proposals to AGENTS_ERRATA.md. Reconcile
  AGENTS_ERRATA.md into .claude/rules/ at the start of the next Claude Code session.

## READ FIRST

**Before implementing any feature:**
1. @./POWERFOOTBALL_MASTER_VISION.md — Vision, roadmap, deep systems, agent protocol
2. @./ROADMAP.md — Tactical [ ]/[x] checklist
3. @.claude/rules/godot-47-core.md — Engine contracts
4. @.claude/rules/soccer-physics.md — Physics invariants
5. @.claude/rules/ai-architect.md — AI & spatial invariants

## Architecture Quick-Reference

- **Signal bus:** ALL inter-system events → GameEvents.gd autoload
- **Spatial cache:** ALL NPC position reads → MatchWorldModel.gd
- **Collision:** CharacterBody2D MUST NOT mask Layer 3 (Ball)
- **Brain contract:** PlayerBrain writes ONLY to player.movement_intent

## Boot Order (project.godot)

MatchWorldModel → GameEvents → GameManager → DataLoader → RefereeLoader →
ManagerLoader → InputHelper

## Process Priority

MatchWorldModel (-100) → PlayerBrain (0) → HeavyPlayerController (100)

## Squad Config

22 players total (11 per team), spawned declaratively as children
of `$Players` in `pitch/PitchScene.tscn`.

## Multi-Agent Sync

AGENTS.md is the onboarding file for non-Claude agents. Keep in sync with this file.

**Sync contract:**
- Any new architectural law added here MUST also be added to AGENTS.md Section 3 in the same session.
- Any new `.claude/rules/*.md` file MUST have its key prohibitions mirrored in AGENTS.md Engine Lock or as a new subsection.
- ROADMAP.md checkbox changes MUST be mirrored in AGENTS.md if coverage is required.
- Non-Claude agents write rule proposals to AGENTS_ERRATA.md. Reconcile AGENTS_ERRATA.md into `.claude/rules/` at the start of the next Claude Code session.

AGENTS_ERRATA.md takes priority over this file on any specific recent decision.

## Context Budget — Claude Code Sessions

All Claude Code sessions track context usage against the same thresholds:

| Range | State | Action |
|-------|-------|--------|
| 0–50% | OPTIMAL | Full architecture work. Multi-layer features. Reference files inline. |
| 50–70% | MONITOR | Verify outputs against `.claude/rules/` files. Use grep for spot checks. |
| 70–85% | DANGER | Run `/compact` to compress prior messages. Do not start new features. |
| 85%+ | CRITICAL | Run `/compact` or `/clear` before next task. Major subsystem switches only. |

Switch major subsystems (physics ↔ AI, match ↔ career) with `/clear`. CLAUDE.md and `.claude/rules/` survive both compaction and clear.
