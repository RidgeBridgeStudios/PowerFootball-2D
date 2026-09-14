> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match architecture.**
> This hub documents a file from the abandoned 22-player real-time match engine. That code now lives archived under `legacy/` (excluded from Godot via `legacy/.gdignore` and skipped by every linter) and must never be cited as live or "fixed".
> It is retained as historical reference — useful when deepening `QuickSimEngine` — not as current implementation guidance.
> Current architecture: [architecture-pivot.md](../../agent-errata/architecture-pivot.md) · canonical contracts: [CORE_INVARIANTS.md](../../CORE_INVARIANTS.md).

# Architecture Hub: PlayerBrain

**Canonical Location:** [`docs/architecture/hubs/player-brain.md`](player-brain.md)  
**Source Script:** [`entities/player/PlayerBrain.gd`](../../../legacy/entities/player/PlayerBrain.gd)  
**Simulation Layer:** Layer 2 — Match AI & Spatial Navigation  
**Node Type:** `PlayerBrain` extends `Node` (Child of [`HeavyPlayerController`](../../../legacy/entities/player/HeavyPlayerController.gd))  

---

## 1. Purpose and Non-Responsibilities

### Purpose
`PlayerBrain` is the autonomous utility-scored decision engine for outfield CPU players and goalkeepers. Instead of an imperative `if/else` decision tree, it builds a contextual snapshot (`UtilityContext`) from match geometry and passes it through personality attributes (`vision_attribute`, `composure_attribute`, `aggression_attribute`), mood modifiers (`MoodSystem`), and chemistry ratings (`TrustSystem`). It selects tactical actions (such as `MaintainFormation`, `Pass`, `ChaseBall`, `FindSpace`, `AttemptDribble`, `AttemptShoot`, `PanicClear`, `GoaliePatrol`, `GoalieRush`) and converts them into steering directives for its parent controller.

### Non-Responsibilities
- **No Direct Kinematics:** `PlayerBrain` NEVER writes to `velocity`, `acceleration`, or `is_sprinting` on [`HeavyPlayerController`](../../../legacy/entities/player/HeavyPlayerController.gd). It writes strictly to `player.movement_intent` (normalized `Vector2` steering vector) and `player.wants_sprint` (`bool`).
- **No Scene Tree Polling:** Calling `get_tree().get_nodes_in_group()` inside any method is strictly forbidden. All spatial queries, teammate checks, and opponent tracking must route through [`MatchWorldModel`](../../../legacy/autoloads/MatchWorldModel.gd).
- **No Physics Integration:** Collision detection, turning inertia, weight scaling, stamina expenditure, and `move_and_slide()` belong solely to [`HeavyPlayerController`](../../../legacy/entities/player/HeavyPlayerController.gd).
- **No Direct State Mutation:** The brain does not transition the player state machine directly during open play; state machines evaluate controller variables and trigger transitions based on context.
- **No Macro Rule Derivation:** Macro pressing triggers (e.g. `FACING_OWN_GOAL`, `TOUCHLINE_ISOLATION`, `PROLONGED_POSSESSION`) are derived centrally in [`MatchWorldModel`](../../../legacy/autoloads/MatchWorldModel.gd). The brain only reads the active flag.

---

## 2. Public API, Signals, Events, Contracts & Dependencies

### Node Hierarchy & Priority
- **Hierarchy:** `PitchScene` -> `$Players` -> `PlayerInstance` ([`HeavyPlayerController`](../../../legacy/entities/player/HeavyPlayerController.gd)) -> `PlayerBrain` (`Node`).
- **Process Priority:** Runs at `process_priority = 0`.
  - Runs *after* [`MatchWorldModel`](../../../legacy/autoloads/MatchWorldModel.gd) (`-100`).
  - Runs *before* [`HeavyPlayerController`](../../../legacy/entities/player/HeavyPlayerController.gd) (`100`).

### Exported Properties
- `@export_range(0.0, 1.0) var vision_attribute: float = 0.75` — Awareness of passing lanes and teammate runs.
- `@export_range(0.0, 1.0) var composure_attribute: float = 0.60` — Resistance to panic clearing under press.
- `@export_range(0.0, 1.0) var aggression_attribute: float = 0.80` — Tackle frequency and long-range shooting bias.
- `@export var formation_anchor: Vector2 = Vector2.ZERO` — Base world-space anchor position.
- `@export_range(0.0, 1.0) var formation_ball_weight: float = 0.35` — Compactness drift toward ball.
- `@export var decision_interval: float = 0.25` — Backward compatibility setter that translates legacy duration to pressing intensity via `set_pressing_intensity()`.
- `@export var is_goalkeeper: bool = false` — Diverts execution from outfield scoring to `GoaliePatrol`/`GoalieRush`.
- `@export var player_index: int = 0` — Index (0–21) registered in [`MatchWorldModel`](../../../legacy/autoloads/MatchWorldModel.gd).

### Enums & Types
- `enum Role { OUTFIELD_ATTACKER, OUTFIELD_MIDFIELDER, OUTFIELD_DEFENDER, GOALKEEPER }`
- `enum FreeKickActionType { SHORT_PASS, DIRECT_SHOT, CROSS, LONG_BALL }`
- `enum DefensiveDuty { NONE, TRIGGER_PRESS, COVER_SUPPORT, COVER_SHADOW }`

### Key Public Methods
- `evaluate_tactical_action(defenders_nearby: Array[Node2D] = []) -> StringName`: Core scoring loop returning action `StringName`.
- `calculate_pressure_index(defenders: Array[Node2D] = []) -> float`: Computes [0.0, 1.0] opponent crowding index.
- `find_pass_target_for_set_piece() -> HeavyPlayerController`: Evaluates viable passing targets during dead-ball restarts (supports `allow_backward_pass = true`).
- `evaluate_free_kick_intent(fk_pos: Vector2, is_direct: bool) -> Vector2`: Generates target point and parameters for free kicks.
- `has_free_kick_intent() -> bool` / `clear_free_kick_intent() -> void`: Lifecycle for dead-ball intent flags.
- `set_pressing_intensity(intensity: float) -> void`: Maps [0.0, 1.0] into update interval (clamps frame stagger interval between 7 and 25 ticks).
- `bind_ball(match_ball: Pseudo3DBall) -> void` / `bind_boundary(b: PitchBoundary) -> void`: Initial bindings at spawn.
- `clamp_to_playable_area(pos: Vector2) -> Vector2` / `get_playable_rect() -> Rect2`: Boundary safety clamps.
- `apply_player_data(p: PlayerData) -> void`: Synchronizes profile attributes (`vision`, `composure`, `aggression`).
- `get_target_position() -> Vector2`: Retrieves the current active steering destination.

### Signals & Event Bus
- **Signals Connected:**
  - `GameEvents.formation_anchors_changed(team, new_anchors)`: Refreshes anchor coordinates immediately upon tactical shifts or manager overrides.
- **Signals Emitted:**
  - Emits via `GameEvents`: `ball_struck(kicker, speed, charge_ratio, is_shot)`, `powerful_shot_landed(shot_position)`.

### Core Dependencies
- Upstream: [`MatchWorldModel`](../../../legacy/autoloads/MatchWorldModel.gd), [`GameEvents`](../../../autoloads/GameEvents.gd), [`GameManager`](../../../autoloads/GameManager.gd).
- Downstream: [`HeavyPlayerController`](../../../legacy/entities/player/HeavyPlayerController.gd) (writes intent).
- Sibling Components: [`MoodSystem`](../../../legacy/entities/player/MoodSystem.gd), [`TrustSystem`](../../../legacy/entities/player/TrustSystem.gd).
- Math Utilities: [`PassUtilityScorer`](../../../legacy/shared/PassUtilityScorer.gd), [`FormationAnchorMath`](../../../legacy/shared/FormationAnchorMath.gd), [`UtilityMath`](../../../shared/UtilityMath.gd), [`PlayerRoleConfig`](../../../shared/PlayerRoleConfig.gd).

---

## 3. State Model & Architectural Invariants

### Time-Sliced Stagger Model
Heavy decision-making is staggered across 15 physics frames (`UPDATE_INTERVAL = 15`) to prevent CPU spikes:
$$\text{ShouldUpdate}(i, f) \iff (i + f) \pmod{15} = 0$$
Where $i = \text{player\_index}$ and $f = \text{\_frame\_counter}$. Maximum 2 brains run full utility scoring in any single tick (250ms tactical slice at 60Hz). Steering and path validation continue running on every physics frame.

### Hot-Path Zero-Allocation Rule
- No transient `Array`, `Dictionary`, or `Vector2` allocations inside `_physics_process` or `evaluate_tactical_action()`.
- Uses class-level scratch arrays and cached objects.
- Deterministic member `_rng` seeded by `player.get_instance_id() + GameManager.get_match_tick()`.
- Uses `distance_squared_to()` exclusively for sorting and candidate comparisons.

### Defensive Line Invariant
Outfield defenders (`Role.OUTFIELD_DEFENDER`) blend their anchor target with [`MatchWorldModel.instance.defensive_line_x[team]`](../../../legacy/autoloads/MatchWorldModel.gd) rather than computing independent defensive line depths.

---

## 4. Change-Impact Checklist

When modifying `PlayerBrain.gd`:
- [ ] **Contract Verification:** Confirm writes are limited to `player.movement_intent` and `player.wants_sprint`. Never assign `player.velocity` directly.
- [ ] **Spatial Invariant:** Ensure no calls to `get_tree().get_nodes_in_group()` exist; verify all spatial lookups use `MatchWorldModel`.
- [ ] **Allocation Audit:** Check that no `Array.new()`, `Vector2()` instantiation, or dynamic lambdas were added to hot loops.
- [ ] **Static Analysis:**
  ```bash
  py -3 tools/verify_gate.py --fast
  ```
- [ ] **Blast Radius Check:** Direct dependents include 23 modules (`HeavyPlayerController`, `SetPieceCoordinator`, `PitchScene`, `ManagerDirector`, states). Run:
  ```bash
  py -3 tools/dump_dep_graph.py --blast-radius entities/player/PlayerBrain.gd
  ```
- [ ] **Simulation Harness:** Run 60-second headless simulation assertion harness:
  ```bash
  py -3 tools/eval_simulation.py --duration=60
  ```

---

## 5. Known Risks & Errata Search Terms

When debugging or altering behavior, consult [`AGENTS_ERRATA.md`](../../../AGENTS_ERRATA.md) for these documented edge cases:
- `press-trigger-needs-time-backstop` (lines 22–52): Posture-only triggers failed against a calm ball-carrier holding position; required `PROLONGED_POSSESSION` time backstop.
- `kickoff-backward-pass-veto-starves-taker` (lines 53–100): Composure-gated backward pass veto caused kickoffs to starve and turnover; set piece pass search must use `allow_backward_pass = true`.
- `loose-ball-anchor-clamp-deadlock` (lines 101–140): Anchor distance clamping prevented outfielders from chasing uncontested loose balls.
- `maintain-formation-floor-freezes-ball-carrier` (lines 228–260): `MaintainFormation` score flooring caused carrier freezing.
- `cpu-players-never-gated-into-tackle-state` (lines 1337–1380): CPU players required explicit cooldown and distance gating for tackle state entry.
- `possessor-can-chase-own-ball` (lines 702–740): Possessor scoring `ChaseBall` against its own dribble target produced oscillatory jitter.
- `dribble-claim-ignores-existing-possessor-dual-driver-jitter` (lines 1301–1336): Prevented two players simultaneously claiming ball possession.

---

## 6. Sources Examined

- [`entities/player/PlayerBrain.gd`](../../../legacy/entities/player/PlayerBrain.gd)
- [`entities/player/README.md`](../../../legacy/entities/player/README.md)
- [`docs/CORE_INVARIANTS.md`](../../CORE_INVARIANTS.md)
- [`docs/API_SURFACE.md`](../../API_SURFACE.md)
- [`AGENTS_ERRATA.md`](../../../AGENTS_ERRATA.md)
