# Architecture Hub: MatchWorldModel

**Canonical Location:** [`docs/architecture/hubs/match-world-model.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/architecture/hubs/match-world-model.md)  
**Source Script:** [`autoloads/MatchWorldModel.gd`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/MatchWorldModel.gd)  
**Simulation Layer:** Layer 2 — Match AI & Spatial Navigation  
**Node Type:** Autoload Singleton (`Node`, registered in `project.godot`)  

---

## 1. Purpose and Non-Responsibilities

### Purpose
`MatchWorldModel` is the match's central spatial cache and high-performance tactical indexing layer. Instead of allowing 22 independent player brains to execute expensive `get_tree().get_nodes_in_group()` scans, this singleton collects the world-space positions and velocities of all 22 players and the ball into contiguous packed arrays once per physics frame. It acts as the single source of truth for all spatial queries, computes shared per-team defensive line depths (`defensive_line_x`), evaluates a 12x8 pitch control dominance grid, derives macro pressing triggers, and tracks ball possessor residency.

### Non-Responsibilities
- **No Kinematic Movement:** It never modifies player velocity, never resolves collision geometry, and never calls `move_and_slide()`. That responsibility belongs strictly to [`HeavyPlayerController`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/HeavyPlayerController.gd).
- **No Tactical Decision Making:** It evaluates spatial conditions (distances, lane openness, pitch control, pressing triggers), but never chooses actions for individual players. Action selection is the sole responsibility of [`PlayerBrain`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/PlayerBrain.gd).
- **No Match Lifecycle Ownership:** It does not manage match clock, game phases, scores, or set-piece lifecycles. That responsibility belongs strictly to [`GameManager`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/GameManager.gd).
- **No Scene Tree Scanning:** It never scans groups or scene trees at runtime; player registration is push-based in player `_ready()`.
- **No `class_name` Declaration:** Godot 4.7+ rejects a `class_name` that collides with an autoload singleton's injected global name.

---

## 2. Public API, Signals, Events, Contracts & Dependencies

### Process Priority & Boot Order
- **Boot Order (`project.godot`):** Initialized 1st, ahead of all other singletons (`MatchWorldModel` -> `GameEvents` -> `GameManager` -> `MatchStatsTracker`...).
- **Process Priority:** Runs at `process_priority = -100`. The cache is fully updated before any [`PlayerBrain`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/PlayerBrain.gd) (`0`) evaluates tactics or any [`HeavyPlayerController`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/HeavyPlayerController.gd) (`100`) executes physics.

### Constants & Enums
- `const TOTAL_PLAYERS: int = 22` — Exactly 11 per team (10 outfield + 1 goalkeeper).
- `const NO_INDEX: int = -1` — Sentinel for empty slot or unpossessed ball.
- `const DEFAULT_PASS_LANE_CLEARANCE: float = 45.0` — Default safety corridor width for passing raycasts.
- `const TACTICAL_GRID_WIDTH: int = 12`, `const TACTICAL_GRID_HEIGHT: int = 8`, `const TACTICAL_GRID_CELLS: int = 96` — Dimensions of the spatial control grid.
- `enum PressTrigger { NONE = 0, BACKWARD_PASS = 1, SQUARE_PASS = 2, TOUCHLINE_ISOLATION = 3, HEAVY_TOUCH = 4, FACING_OWN_GOAL = 5, PROLONGED_POSSESSION = 6 }`
- `enum DecisionAction { MAINTAIN_FORMATION, PANIC_CLEAR, PASS, CHASE_BALL, FIND_SPACE, ATTEMPT_DRIBBLE, ATTEMPT_SHOOT, UNKNOWN }`

### Public Data Properties
- `static var instance: MatchWorldModel = null`
- `player_nodes: Array[HeavyPlayerController] = []` — Direct node references.
- `player_positions: PackedVector2Array` — Contiguous world-space positions.
- `player_velocities: PackedVector2Array` — Contiguous kinematic velocities.
- `player_teams: PackedInt32Array` — Team assignments (0 = Team A, 1 = Team B).
- `ball_node: Pseudo3DBall = null`
- `ball_position: Vector2`, `ball_velocity: Vector2`
- `possessor_index: int = NO_INDEX` — Index of current carrier in `player_nodes`.
- `defensive_line_x: Array[float]` — Shared back-line depth per team along the X attack axis.
- `press_trigger_active: bool`, `press_trigger_type: PressTrigger`, `press_trigger_carrier: HeavyPlayerController`, `press_trigger_position: Vector2`
- Macro caches: `team_urgency: Array[float]`, `team_momentum: Array[float]`, `current_match_stage: int`

### Key Public Methods
- **Registration Lifecycle:**
  - `register_player(index: int, node: HeavyPlayerController, team: int) -> int`: Claims slot during node initialization.
  - `register_ball(node: Pseudo3DBall) -> void`: Binds ball reference from pitch.
  - `unregister_all() -> void`: Flushes slot table and resets static index counter.
  - `mark_player_unavailable(player: HeavyPlayerController) -> void`: Flags substituted or sent-off players.
  - `is_slot_live(index: int) -> bool`: Safe validity guard against freed entities (crucial in Practice Arena).
- **Spatial Queries:**
  - `nearest_opponent_dist_to(pos: Vector2, team: int) -> float`
  - `nearest_opponent_position(pos: Vector2, team: int) -> Vector2`
  - `get_opponents_of(team: int) -> Array[int]` / `get_teammates_of(index: int) -> Array[int]`
  - `get_nearby_players(pos: Vector2, radius: float) -> Array[int]`
  - `get_nearby_opponents(pos: Vector2, radius: float, team: int) -> Array[int]`
  - `get_nearby_teammates(pos: Vector2, radius: float, team: int, exclude_index: int = NO_INDEX) -> Array[int]`
  - `get_opponent_density(pos: Vector2, radius: float, team: int) -> float`
- **Passing Lane Geometry:**
  - `is_passing_lane_open(from_pos: Vector2, to_pos: Vector2, clearance: float, team: int) -> bool`
  - `get_passing_lane_min_distance(start_pos: Vector2, end_pos: Vector2, passer_team_id: int) -> float`
- **Tactical Grid & Analytics:**
  - `get_pitch_control_at(pos: Vector2, team: int) -> float`
  - `get_cell_dominance(cell_x: int, cell_y: int) -> int`
  - `is_zone_14(cell_x: int, cell_y: int, attacking_team: int) -> bool`
  - `get_active_possession_hold_seconds() -> float`: Active continuous carry duration for the true possessor.

### Signals & Event Bus
- **Signals Connected:**
  - `GameEvents.ball_struck(kicker, speed, charge_ratio, is_shot)`
  - `GameEvents.match_phase_changed(new_phase)`
  - `GameEvents.match_stage_changed(stage)`
  - `GameEvents.team_momentum_updated(team, momentum)`
  - `GameEvents.team_urgency_updated(team, urgency)`
- **Signals Emitted:**
  - Emits via `GameEvents`: `press_trigger_changed(active, type, carrier, pos)`, `anticipatory_turnover_predicted(carrier, threat_dir)`.

### Core Dependencies
- Upstream: None (Boot singleton #1).
- Downstream: [`PlayerBrain`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/PlayerBrain.gd), [`HeavyPlayerController`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/HeavyPlayerController.gd), [`MatchStatsTracker`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/MatchStatsTracker.gd), [`MatchReferee`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/referee/MatchReferee.gd), [`OffsideDetector`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/referee/OffsideDetector.gd), [`HUD`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/ui/HUD.gd), [`Minimap`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/Minimap.gd), [`PassUtilityScorer`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/shared/PassUtilityScorer.gd), [`FormationAnchorMath`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/shared/FormationAnchorMath.gd).

---

## 3. State Model & Architectural Invariants

### Push-Registration Invariant
Players do not get scanned from the scene tree. In `_ready()`, each `HeavyPlayerController` calls `MatchWorldModel.instance.register_player(NO_INDEX, self, team)`, claiming the next sequential slot. During match teardown or scene transitions, `unregister_all()` resets internal slot counters.

### Shared Defensive Line Contract
`defensive_line_x` computes the collective offside/depth line for each team along the horizontal pitch axis based on ball location, opposition depth, and ball carrier pressure:
$$X_{\text{target}} = \text{clamp}(X_{\text{ball}} \pm \Delta_{\text{offset}}, X_{\text{min}}, X_{\text{max}})$$
Defenders read this value from `MatchWorldModel` and blend toward it rather than computing desynchronized individual offside traps.

### Zero Hot-Path Scene Querying
Hot loops query packed parallel arrays (`player_positions`, `player_velocities`, `player_teams`). Calling `get_tree()` or allocating arrays during spatial iteration is strictly prohibited.

---

## 4. Change-Impact Checklist

When modifying `MatchWorldModel.gd`:
- [ ] **Process Priority:** Confirm `process_priority = -100` remains intact so downstream systems never read stale frames.
- [ ] **Instance Guarding:** Ensure all array access handles Practice Arena mode where only 2 players exist; check `is_slot_live(i)` or `is_instance_valid(player_nodes[i])`.
- [ ] **Static Analysis:**
  ```bash
  py -3 tools/verify_gate.py --fast
  ```
- [ ] **Blast Radius Check:** `MatchWorldModel` directly impacts 23 central modules across all 5 simulation layers:
  ```bash
  py -3 tools/dump_dep_graph.py --blast-radius autoloads/MatchWorldModel.gd
  ```
- [ ] **Performance Benchmarks:** Run the spatial grid benchmark to verify query latencies:
  ```bash
  py -3 tools/spatial_grid_bench.py
  ```
- [ ] **Headless Simulation Harness:**
  ```bash
  py -3 tools/eval_simulation.py --duration=60
  ```

---

## 5. Known Risks & Errata Search Terms

When debugging or altering spatial behavior, consult [`AGENTS_ERRATA.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/AGENTS_ERRATA.md) for these documented edge cases:
- `press-trigger-needs-time-backstop` (lines 22–52): Posture-only triggers failed against calm ball-carriers holding position; required `PROLONGED_POSSESSION` time backstop.
- `possession-hold-timer-has-two-non-interchangeable-variants` (lines 1020–1060): Clarified differences between raw possession timer and continuous true-carrier hold timer (`get_active_possession_hold_seconds()`).
- `match-stage-boundaries-are-fractions-not-literal-seconds` (lines 852–870): Match stages are fractional thresholds of total duration, not fixed second counters.
- `crowding-space-creation-diagnostics` (lines 895–940): Logging crowding density metrics without allocating strings on hot paths.
- `defender-marking-was-uncoordinated-and-boundary-clamp-already-existed` (lines 1093–1150): Marking assignments must use centralized coordination rather than greedy local assignment.
- `ERR-20260830-02` & `ERR-20260831-01` (lines 1664–1710): Stale node references when players are freed in practice mode.

---

## 6. Sources Examined

- [`autoloads/MatchWorldModel.gd`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/MatchWorldModel.gd)
- [`autoloads/README.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/README.md)
- [`docs/CORE_INVARIANTS.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/CORE_INVARIANTS.md)
- [`docs/API_SURFACE.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/API_SURFACE.md)
- [`AGENTS_ERRATA.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/AGENTS_ERRATA.md)
