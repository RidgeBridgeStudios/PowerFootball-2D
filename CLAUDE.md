## PowerFootball-2d — Project Index & Invariants

**Engine:** Godot 4.7-stable · GDScript 2.0 ONLY
**Verify:** `godot --headless -s addons/gut/gut_cmdln.gd -gexit`
(No Godot binary and no `addons/gut/` are present in the CI container — fall back
to `python3 tools/gdcheck.py`, the static GDScript consistency checker, and say so
explicitly rather than claiming an engine run happened.)

**Architecture quick-reference:**
- Signal bus: ALL inter-system events → GameEvents.gd autoload
- Spatial cache: ALL NPC position reads → MatchWorldModel.gd
- Collision contract: CharacterBody2D MUST NOT mask Layer 3 (Ball)
- Brain contract: PlayerBrain writes ONLY to player.movement_intent

**Autoload order (project.godot):**
MatchWorldModel → GameEvents → GameManager → DataLoader → RefereeLoader →
ManagerLoader → InputHelper

**Execution order (process_priority):**
MatchWorldModel (-100) → PlayerBrain (0) → HeavyPlayerController (100)

**Squad size:** 22 players total (11 per team), spawned declaratively as children
of `$Players` in `pitch/PitchScene.tscn`.

**Dynamic rule imports (always active):**
@.claude/rules/godot-47-core.md
@.claude/rules/soccer-physics.md
@.claude/rules/ai-architect.md
