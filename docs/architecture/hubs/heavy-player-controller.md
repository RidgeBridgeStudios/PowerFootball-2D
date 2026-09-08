# Architecture Hub: HeavyPlayerController

**Canonical Location:** [`docs/architecture/hubs/heavy-player-controller.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/architecture/hubs/heavy-player-controller.md)  
**Source Script:** [`entities/player/HeavyPlayerController.gd`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/HeavyPlayerController.gd)  
**Simulation Layer:** Layer 1 — Physics & Kinematics  
**Node Type:** `HeavyPlayerController` extends `CharacterBody2D`  

---

## 1. Purpose and Non-Responsibilities

### Purpose
`HeavyPlayerController` is the physics execution body and kinematic weight model for human and CPU players. It realizes the core physical feel of the game: mass-scaled inertia, acceleration curves, momentum bleed through turns, friction deceleration, sprint stamina consumption, progressive three-tier fatigue slowing, sprint-jostle shoulder duels, knockback resolution, and `move_and_slide()` integration. It hosts the player state machine (`PlayerStateFactory`) and exposes sensor ranges for foot and aerial ball contact.

### Non-Responsibilities
- **No Tactical Decision Making:** It contains zero utility scoring, offside logic, or tactical planning. It consumes intent exclusively via `movement_intent`, `wants_sprint`, and `wants_tackle` provided by [`PlayerBrain`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/PlayerBrain.gd) or [`InputHelper`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/InputHelper.gd).
- **No Direct Velocity Snapping:** Velocity is never set directly to input vectors. Acceleration and turning penalties are always integrated continuously via `move_toward()`.
- **No Direct Ball Collision Masking:** The `CharacterBody2D` MUST NOT mask Layer 3 (`BallPhysicsBody`). Direct kinematic collisions with the ball would zero player velocity in Godot's solver and flatten the momentum model.
- **No Scene Tree Scanning:** It never queries scene tree groups for other players or the ball; all spatial lookups route through [`MatchWorldModel`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/MatchWorldModel.gd).

---

## 2. Public API, Signals, Events, Contracts & Dependencies

### Process Priority & Collision Matrix
- **Process Priority:** Runs at `process_priority = 100` (executing physics *after* `MatchWorldModel` at `-100` and `PlayerBrain` at `0`).
- **Collision Layer:** Layer 2 (`PlayerBodies`).
- **Collision Mask:** Layer 1 (`PitchWorld`) and Layer 2 (`PlayerBodies`) ONLY. (Layer 3 Ball is strictly excluded).

### Exported Properties
- `@export var player_mass: float = 75.0` — Mass in kg (70kg neutral baseline; scales inertia and friction).
- `@export var top_speed: float = 240.0` — Pixels per second at maximum stick deflection.
- `@export var acceleration_time: float = 0.22` — Seconds to reach top speed from a standstill.
- `@export var friction_time: float = 0.12` — Seconds to coast to a complete stop without input.
- `@export_range(0.0, 1.0) var turning_penalty_factor: float = 0.35` — Turning resistance multiplier.
- `@export var sprint_multiplier: float = 1.45` — Speed multiplier during sprint.
- `@export var stamina_max: float = 100.0`, `@export var stamina_drain_rate: float = 18.0`, `@export var stamina_recover_rate: float = 9.0`
- `@export var stamina_sprint_unlock: float = 20.0` — Stamina required to resume sprinting after exhaustion.
- `@export var team: int = 0` — Team identifier (0 = Team A, 1 = Team B).
- `@export var is_user_controlled: bool = false` — True reads `InputHelper`; false is driven by `PlayerBrain`.
- `@export var squad_index: int = 0` — Index in team roster.
- `@export var role_config: PlayerRoleConfig` — Role tuning resource.

### Signals Declared & Emitted
- `signal stamina_state_changed(ratio: float)`: Emitted when stamina ratio changes.
- `signal possession_gained` / `signal possession_lost`: Dispatched during ball capture transitions.
- Emits via `GameEvents`: `stamina_depleted(player)`.
- Connects to: `GameEvents.player_mood_changed` (triggers `_recalculate_movement_curve()`).

### Enums & Constants
- `enum FatigueTier { FRESH, TIRED, EXHAUSTED }`
- `const FATIGUE_TIRED_RATIO: float = 0.6`, `const FATIGUE_EXHAUSTED_RATIO: float = 0.25`
- `const FATIGUE_SPRINT_SCALE`: `FRESH: 1.0`, `TIRED: 0.85`, `EXHAUSTED: 0.65`
- `const FATIGUE_BASE_SCALE`: `FRESH: 1.0`, `TIRED: 0.95`, `EXHAUSTED: 0.85`
- `const NEUTRAL_MASS: float = 70.0`, `const MIN_ACCELERATION_RATIO: float = 0.18`
- `const MAX_CAPTURE_HEIGHT: float = 25.0`, `const GOALKEEPER_CATCH_RADIUS: float = 34.0`
- `const JOSTLE_HEADING_DOT_MIN: float = 0.70`, `const JOSTLE_MIN_SPEED: float = 100.0`, `const JOSTLE_IMPULSE_PER_SECOND: float = 90.0`

### Key Public Methods
- **Kinematics & Momentum:**
  - `apply_kinematic_weight(input_dir: Vector2, delta: float) -> void`: Core movement integration and turning penalty solver.
  - `apply_external_impulse(impulse: Vector2) -> void`: Adds impulse from tackles, headers, or jostles.
  - `freeze_momentum() -> void`: Immediately stops velocity (used during set-piece setups).
- **Physical Metrics & Attributes:**
  - `get_current_top_speed() -> float`: Returns top speed adjusted by sprint status and fatigue tier.
  - `get_fatigue_tier() -> FatigueTier` / `get_stamina_ratio() -> float`
  - `apply_player_data(p: PlayerData, reset_stamina: bool = true) -> void`: Re-applies squad attributes.
- **Ball Interaction Sensors:**
  - `get_ball_in_foot_range() -> Pseudo3DBall` (Layer 4 area sensor)
  - `get_ball_in_aerial_range() -> Pseudo3DBall` (Layer 5 area sensor)
  - `get_ball_in_catch_range() -> Pseudo3DBall` (Goalkeeper specific)
  - `can_capture_ball(ball: Pseudo3DBall) -> bool`: Height check (`z <= MAX_CAPTURE_HEIGHT`).
- **Feedback & UI:**
  - `show_action_text(message: String, color: Color = Color.WHITE) -> void`

### Core Dependencies
- Upstream: [`InputHelper`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/InputHelper.gd) (for user player), [`PlayerBrain`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/PlayerBrain.gd) (for CPU), [`MatchWorldModel`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/MatchWorldModel.gd).
- State Machine: [`PlayerStateFactory`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/PlayerStateFactory.gd) and all child states in `entities/player/states/`.
- Sibling Systems: [`MoodSystem`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/MoodSystem.gd), [`TrustSystem`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/TrustSystem.gd).

---

## 3. State Model & Architectural Invariants

### Kinematic Acceleration & Turning Penalty Law
Player acceleration is degraded proportionally to the sharpness of the turn:
$$\theta = \arccos(\hat{v}_{\text{current}} \cdot \hat{v}_{\text{target}})$$
$$a_{\text{eff}} = a_{\text{base}} \cdot \max\left(1.0 - \gamma \cdot \frac{\theta}{\pi}, 0.18\right)$$
Velocity is stepped via:
$$\vec{v}_t = \text{move\_toward}(\vec{v}_{t-1}, \vec{v}_{\text{target}}, a_{\text{eff}} \cdot \Delta t)$$

### Three-Tier Fatigue Model
Fatigue progressively scales top speed across three tiers (`FRESH` $\to$ `TIRED` $\to$ `EXHAUSTED`). Sprinting drains stamina at 18.0/sec; exhaustion locks sprint (`sprint_locked = true`) until stamina recovers past 20.0.

### Brain / Controller Choke Point
`PlayerBrain` or `InputHelper` communicates purely through:
- `movement_intent: Vector2`
- `wants_sprint: bool`
- `wants_tackle: bool`
Neither brain nor input ever sets `velocity` or manipulates `move_and_slide()` directly.

---

## 4. Change-Impact Checklist

When modifying `HeavyPlayerController.gd`:
- [ ] **Collision Masks:** Verify `collision_mask` never enables bit 3 (Layer 3 Ball).
- [ ] **Direct Velocity Prohibition:** Confirm no `velocity = ...` assignments bypass `move_toward` in kinematic update functions.
- [ ] **Fast Gate Verification:**
  ```bash
  py -3 tools/verify_gate.py --fast
  ```
- [ ] **Blast Radius Assessment:** Affects 53 direct dependent files across all layers:
  ```bash
  py -3 tools/dump_dep_graph.py --blast-radius entities/player/HeavyPlayerController.gd
  ```
- [ ] **Kinematic Fuzz Testing:** Run property fuzzers to assert boundary and solver stability:
  ```bash
  py -3 tools/fuzz_solvers.py
  ```

---

## 5. Known Risks & Errata Search Terms

When investigating movement glitches or controller instability, consult [`AGENTS_ERRATA.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/AGENTS_ERRATA.md) for these documented edge cases:
- `dribble-magnet-forward-overshoot-oscillation` (lines 576–605): Dribble magnet overshooting target forward offset produced oscillatory stutter; required dampening.
- `dribble-claim-ignores-existing-possessor-dual-driver-jitter` (lines 1275–1310): Dual-driver jitter occurred when multiple controllers claimed possession simultaneously.
- `cpu-players-never-gated-into-tackle-state` (lines 1337–1360): Tackle state transition required explicit distance, angle, and cooldown gates.
- `defender-marking-was-uncoordinated-and-boundary-clamp-already-existed` (lines 1145–1170): Marking movements must respect pitch boundaries.

---

## 6. Sources Examined

- [`entities/player/HeavyPlayerController.gd`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/HeavyPlayerController.gd)
- [`entities/player/README.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/README.md)
- [`docs/CORE_INVARIANTS.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/CORE_INVARIANTS.md)
- [`docs/API_SURFACE.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/API_SURFACE.md)
- [`AGENTS_ERRATA.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/AGENTS_ERRATA.md)
