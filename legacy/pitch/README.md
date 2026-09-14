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
- StaticBody2D with Area2D perimeter sensors on `CollisionLayers.LAYER_BOUNDARY_SENSOR` (Layer 6).
- Detects ball exit via Area2D body entered signals.
- Checks `ball.last_touched_by` to differentiate goal kick from corner on end lines.
- Emits `GameEvents.ball_out_of_bounds(side)` with values:
  - `"touchline_top"` / `"touchline_bottom"` (throw-in)
  - `"end_line_goal_kick"` / `"end_line_corner"`
- `PitchScene.gd` intercepts and routes to `SetPieceCoordinator.handle_out_of_bounds()`.

**DO NOT:**
- Modify ball velocity; it is a passive sensor
- Query scene tree for player positions; use MatchWorldModel
- Make tactical decisions based on boundary events

---

### GoalZone.gd (per goal)

**Contract:** Goal area detection and goal-scoring confirmation.

**Mechanism:**
- Area2D at goal mouth (`CollisionLayers.LAYER_PITCH_WORLD`, Layer 1).
- Detects ball entry; checks z-height (must be in goal, `z <= 120.0`).
- Emits `GameEvents.goal_scored(team, scorer)` via `GameManager.register_goal(team, ball.last_touched_by)`.

**Integration:**
- MatchReferee tracks per-match score context and temperature.
- GameManager updates score and triggers `GOAL_SCORED` phase.

**DO NOT:**
- Modify ball state
- Query players; use `last_touched_by` from ball

---

### SetPieceCoordinator.gd

**Contract:** Dead-ball setup and execution (kickoff, corners, goal kicks, throw-ins, free kicks, penalties).

**Key Methods:**

```gdscript
func bind(ball: Pseudo3DBall, boundary: PitchBoundary, players: Node2D) -> void
func handle_out_of_bounds(side: String, exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void
func handle_foul(fouler: HeavyPlayerController, victim: HeavyPlayerController, foul_pos: Vector2) -> void
func handle_indirect_offside(defending_team: int, offside_pos: Vector2) -> void
func start_kickoff(team: int) -> void
func start_penalty_for_practice(attacking_team: int, defending_team: int) -> void
func start_penalty_with_taker(attacking_team: int, defending_team: int, designated_taker: HeavyPlayerController) -> void
func get_taker() -> HeavyPlayerController
```

**Responsibilities:**
- Position ball and players for set piece
- Mark possession owner and enforce taker anti-double-touch constraints via `ball.mark_set_piece_restart()`
- Freeze non-participating players
- Position defensive wall at legal distance (`wall_distance = 176.0`)
- Manage set-piece timeout (auto-resume if no input)

**Integration:**
- Receives calls from PitchBoundary, PitchScene, OffsideDetector, and MatchReferee
- Freezes/unfreezes PlayerBrain decision-making
- Locks/releases input during set pieces

---

### PitchMarkings.gd

**Visual Only.** Draws centerline, halfway, penalty boxes, corner flags.

**Current State:**
- Implemented as custom Node2D drawing geometry (`_draw()`).
- No collision or gameplay logic.

---

### Minimap.gd

**Real-Time Radar HUD Component.**
- Renders top-down 2D radar of pitch with player dots and ball position.
- Queries `MatchWorldModel.player_positions` and `MatchWorldModel.ball_position`.

---

## Pitch Dimensions & Coordinate System

**Pitch Bounds:** Configurable via `PitchBoundary.pitch_size` (default `1600.0 x 900.0` pixels).
- Centre spot at `(0, 0)` or `PitchBoundary.get_centre_spot()`.
- Goals at $x = \pm 800.0$ (`goal_mouth_height = 200.0`).

**Layer Mapping (6-Layer Matrix):**
- Layer 1 (`PitchWorld`) — Pitch boundary posts, goal zones, walls
- Layer 2 (`PlayerBodies`) — Player CharacterBody2D
- Layer 3 (`BallPhysicsBody`) — Ball CharacterBody2D
- Layer 4 (`FootSensorArea`) — Area2D at player feet
- Layer 5 (`AerialHitboxZone`) — Area2D above player shoulders for aerial duels
- Layer 6 (`BoundarySensor`) — Area2D out-of-bounds sensors

---

## Collision Invariants

See **.claude/rules/soccer-physics.md** and **shared/README.md** for collision layer details.

**Critical:**
- `CharacterBody2D` masks Layer 1 + 2 ONLY (never Layer 3).
- Ball is a `CharacterBody2D` on Layer 3 masking Layer 1 only.
- Foot sensor (Layer 4) senses Layer 3 (Ball) only.
- Boundary sensors (Layer 6) monitor Layer 3 (Ball) only.

---

## Notes

- Practice Arena is a full match with reduced player count (2 players); all systems remain active.
- Set pieces are the only time players are positioned programmatically (not by AI).
- Goal detection is trigger-based (`ball inside goal zone` + `z < threshold`).
- Boundary detection uses `last_touched_by` to decide corner vs. goal kick.
