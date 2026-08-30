# pitch/ — Field, Boundaries, & Scoring Zones

Physical pitch representation, boundaries, and goal detection.

## Architecture Overview

```
PitchScene.tscn (root match scene)
  ├─ Terrain (TileMap or static geometry)
  ├─ PitchBoundary (out-of-bounds detector)
  ├─ GoalZones (goal scoring detector)
  ├─ Players (parent node for 22 player instances)
  ├─ Ball (Pseudo3DBall instance)
  ├─ PitchMarkings (visual centerline, halfway, etc.)
  └─ Match setup (Practice Arena toggles, etc.)
```

## Key Scenes & Systems

### PitchScene.tscn

**Root match scene.** Instantiates all players, ball, camera, and HUD.

**Key Methods:**

**Setup Match:**
```gdscript
func _setup_match_from_teams(home_data: TeamData, away_data: TeamData) -> void
```
- Instantiate 22 player nodes from prefab
- Assign shirt numbers and colors
- Register with MatchWorldModel
- Set starting formation

**Practice Arena Mode:**
```gdscript
func _setup_practice_arena() -> void
```
- Keep only human player and one GK
- Free all other 20 players
- Add practice-specific UI (reset button, set-piece toggles)
- Freeze/unfreeze GK, enable penalty/free-kick practice

**Important:** Practice Arena frees 20 of 22 players. All cached node arrays must be `is_instance_valid()`-guarded.

**Signals:**
- Emits `GameEvents.match_phase_changed()` as match progresses

---

### PitchBoundary.gd

**Contract:** Detects out-of-bounds and routes to set-piece coordinator.

**Mechanism:**
- Area2D around pitch perimeter (Layer 1)
- Detects ball exit via Area2D overlap
- Records `ball.last_touched_by` to differentiate goal kick from corner
- Emits `GameEvents.ball_out_of_bounds(side, position, last_kicker)`

**Known Gap (Phase 1):**
- `ball_out_of_bounds` is declared but never emitted
- Once implemented, will route to `SetPieceCoordinator.handle_out_of_bounds()`

**DO NOT:**
- Modify ball velocity; it is a passive sensor
- Query scene tree for player positions; use MatchWorldModel
- Make tactical decisions based on boundary events

---

### GoalZone.gd (per goal)

**Contract:** Goal area detection and goal-scoring confirmation.

**Mechanism:**
- Area2D at goal mouth (Layer 1)
- Detects ball entry; checks z-height (must be in goal)
- Emits `GameEvents.goal_scored(team, scorer)` via `GameManager.register_goal(team, ball.last_touched_by)`

**Integration:**
- MatchReferee may add confirmation logic (offside check, etc.)
- GameManager updates score and triggers PAUSE/CELEBRATION phase

**DO NOT:**
- Modify ball state
- Query players; use last_touched_by from ball

---

### SetPieceCoordinator.gd

**Contract:** Dead-ball setup and execution (kickoff, corners, goal kicks, throw-ins, free kicks, penalties).

**Key Methods:**

```gdscript
func handle_kickoff(team: int) -> void
func handle_corner(attacking_team: int, corner_side: String) -> void
func handle_goal_kick(defending_team: int) -> void
func handle_throw_in(attacking_team: int, throw_side: String) -> void
func handle_foul(foul_team: int, location: Vector2, foul_type: String) -> void
```

**Responsibilities:**
- Position ball and players for set piece
- Mark possession owner
- Freeze non-participating players
- Manage set-piece timeout (auto-resume if no input)

**Integration:**
- Receives calls from PitchBoundary, GoalZone, MatchReferee
- Freezes/unfreezes PlayerBrain decision-making
- Locks/releases input during set pieces

---

### PitchMarkings.gd

**Visual Only.** Draws centerline, halfway, penalty boxes, corner flags.

**Current State:**
- Implemented as visual geometry
- No collision or gameplay logic

**Future (Phase 5):**
- Could animate marking changes based on match state
- Highlight penalty areas during dangerous moments

---

## Pitch Dimensions & Coordinate System

**Pitch Bounds:** Normalized to [0, 100] x [0, 100] by convention
- Actual render size determined by Camera2D zoom and viewport

**Layer Mapping:**
- Layer 1 (Terrain) — Pitch boundary, goal zones, walls
- Layer 2 (Players) — All CharacterBody2D
- Layer 3 (Ball) — Pseudo3DBall Area2D
- Layer 4 (FootSensor) — Invisible player foot contact detection
- Layer 5 (AerialHitbox) — Heading contest zones

---

## Collision Invariants

See **.claude/rules/soccer-physics.md** and **shared/README.md** for collision layer details.

**Critical:**
- CharacterBody2D masks layers 1 + 2 ONLY (never layer 3)
- Ball collision via Area2D, not physics
- Foot sensor (layer 4) is pure signal detection

---

## Notes

- Practice Arena is a full match with reduced player count; all systems remain active
- Set pieces are the only time players are positioned arbitrarily (not by AI)
- Goal detection is trigger-based (ball inside goal zone + z < threshold)
- Boundary detection uses last_touched_by to decide corner vs. goal kick
