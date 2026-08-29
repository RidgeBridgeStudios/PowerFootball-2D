## PowerFootball-2D — Agent Entry Point

**Engine:** Godot 4.7-stable · GDScript 2.0 ONLY
**Verify:** `python3 tools/gdcheck.py`
(Static GDScript checker; no engine binary in CI.)

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
