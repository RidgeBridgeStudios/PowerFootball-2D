# Architecture Hub: PitchScene

**Canonical Location:** [`docs/architecture/hubs/pitch-scene.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/architecture/hubs/pitch-scene.md)  
**Source Script:** [`pitch/PitchScene.gd`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/PitchScene.gd)  
**Source Scene:** [`pitch/PitchScene.tscn`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/PitchScene.tscn)  
**Simulation Layer:** Layer 1 — Physics & Kinematics (Root Match Harness)  
**Node Type:** `PitchScene` extends `Node2D`  

---

## 1. Purpose and Non-Responsibilities

### Purpose
`PitchScene` is the root match scene coordinator. It wires together physical field boundaries, scoring zones, ball dynamics, camera tracking, and HUD overlays. It manages the declarative 22-player squad lifecycle, drives match setup and kickoff placement, executes post-goal celebration pauses, triggers half-time pauses, orchestrates human player auto-switching, manages the Practice Arena environment, and hosts the headless analytical simulation assertion harness.

### Non-Responsibilities
- **No Kinematic Integration:** It does not integrate velocity or calculate inertia; player physics are resolved solely inside [`HeavyPlayerController`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/HeavyPlayerController.gd).
- **No Tactical Decision Making:** It does not score utility functions or steer players; tactical AI belongs to [`PlayerBrain`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/PlayerBrain.gd) and tactical managerial overrides belong to [`ManagerDirector`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/manager/ManagerDirector.gd).
- **No Match Lifecycle Authority:** It does not own the primary match clock, official score, or game phase transitions; it reacts to and triggers phases via [`GameManager`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/GameManager.gd).
- **No Dead-Ball Geometry:** Restart placement, defensive wall positioning, and set-piece freeze states are delegated entirely to [`SetPieceCoordinator`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/SetPieceCoordinator.gd).
- **No Officiating Rules:** Card thresholds, foul evaluations, and offside lines are calculated by [`MatchReferee`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/referee/MatchReferee.gd) and [`OffsideDetector`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/referee/OffsideDetector.gd).

---

## 2. Public API, Signals, Events, Contracts & Dependencies

### Scene Node Hierarchy
```text
PitchScene (Node2D)
  ├── PitchBoundary (PitchBoundary - Area2D Layer 6)
  ├── GoalZoneA / GoalZoneB (GoalZone - Area2D Layer 1)
  ├── GoalNetA / GoalNetB (GoalNet)
  ├── Ball (Pseudo3DBall - CharacterBody2D Layer 3)
  ├── Players (Node2D - 22 Declarative CharacterBody2D instances)
  ├── MatchCamera (Camera2D)
  ├── RestartTimer (Timer)
  ├── HUD (HUD CanvasLayer)
  ├── SetPieceCoordinator (SetPieceCoordinator)
  ├── PenaltyShootoutCoordinator (PenaltyShootoutCoordinator)
  ├── MatchReferee (MatchReferee)
  ├── MatchOfficialCrew (MatchOfficialCrew)
  ├── OffsideDetector (OffsideDetector)
  ├── ManagerDirectorA / ManagerDirectorB (ManagerDirector)
  ├── TouchlineBubble (TouchlineBubble)
  ├── Minimap (Minimap)
  ├── PreGameScreen (PreGameScreen CanvasLayer)
  └── PauseMenu (PauseMenu CanvasLayer)
```

### Exported Properties & Constants
- `@export var goal_restart_delay: float = 2.5` — Delay (seconds) before kickoff positioning after a goal.
- `@export var shake_decay: float = 6.0` — Camera shake decay speed.
- `@export var shake_strength: float = 8.0` — Maximum camera shake offset in pixels.
- `const AUTOSWITCH_ADVANTAGE_PX: float = 160.0` — Required distance advantage over current player to trigger human switch.
- `const AUTOSWITCH_MIN_BALL_DIST: float = 200.0` — Minimum distance from ball before switch is evaluated.
- `const AUTOSWITCH_COOLDOWN: float = 3.0` — Switch cooldown to prevent rapid oscillation.
- `const HALF_TIME_DURATION: float = 5.0` — Stoppage duration between halves.
- `const PRACTICE_GOAL_RESET_DELAY: float = 1.5` — Practice Arena ball reset timer.
- `const MOMENTUM_SWING_THRESHOLD: float = 0.35` — Momentum delta threshold triggering manager touchline commentary.

### Public Methods
- `reset_for_kickoff(kickoff_team: int) -> void`: Places ball at centre spot, unfreezes players, resets momentum, and arms kickoff.
- `shake_camera(amount: float) -> void`: Adds camera trauma for heavy impacts or goal events.
- `switch_to_nearest_teammate() -> void`: Manually or automatically transfers human control to the optimal teammate.

### Signals & Event Bus
- **Signals Connected (via GameEvents & Child Nodes):**
  - `GameEvents.ball_out_of_bounds`, `ball_struck`, `ball_bounced`
  - `GameEvents.goal_scored`
  - `GameEvents.half_time_reached`, `match_ended`
  - `GameEvents.pregame_confirmed`, `pause_closed`, `stats_dismissed`
  - `GameEvents.substitution_made`, `manager_formation_changed`
  - `GameEvents.team_momentum_updated`, `emergency_tactics_triggered`
- **Signals Emitted:**
  - Emits via `GameEvents`: `kickoff_confirmed`, `half_time_ended`, `player_switched`, `manager_stats_updated`, `player_mood_changed`.

### Core Dependencies
- Upstream: [`GameManager`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/GameManager.gd), [`GameEvents`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/GameEvents.gd), [`DataLoader`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/DataLoader.gd).
- Scene Children: [`PitchBoundary`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/PitchBoundary.gd), [`Pseudo3DBall`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/ball/Pseudo3DBall.gd), [`HeavyPlayerController`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/player/HeavyPlayerController.gd), [`SetPieceCoordinator`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/SetPieceCoordinator.gd), [`MatchReferee`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/referee/MatchReferee.gd), [`HUD`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/ui/HUD.gd).

---

## 3. State Model & Architectural Invariants

### 22-Player Declarative Layout Invariant
All 22 players exist as pre-instantiated nodes under `$Players` in `PitchScene.tscn`. The scene does not dynamically instantiate outfield players at runtime. In `_ready()`, each player binds to [`MatchWorldModel`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/MatchWorldModel.gd) via self-service static indexing.

### Six-Layer Collision Matrix
The pitch configuration strictly respects the repository collision matrix:
- **Layer 1 (`PitchWorld`):** Walls, boundary limits, and goal zones.
- **Layer 2 (`PlayerBodies`):** `CharacterBody2D` players (masks Layer 1 and 2 only).
- **Layer 3 (`BallPhysicsBody`):** Ball `CharacterBody2D` (masks Layer 1 only; NEVER masks Layer 2).
- **Layer 4 (`FootSensorArea`):** Area2D at feet sensing Layer 3 (Ball).
- **Layer 5 (`AerialHitboxZone`):** Area2D at shoulders sensing Layer 3 (Ball).
- **Layer 6 (`BoundarySensor`):** Area2D boundary perimeter sensing Layer 3 (Ball).

### Practice Arena Mode
When started in practice mode (`_is_practice_mode = true`), `PitchScene` retains only the human player and one goalkeeper, and calls `queue_free()` on the remaining 20 players. All system components, minimaps, and spatial queries MUST use `is_instance_valid()` guards when handling node arrays.

---

## 4. Change-Impact Checklist

When modifying `PitchScene.gd` or `PitchScene.tscn`:
- [ ] **Collision Layer Check:** Verify collision masks in the scene inspect panel; ensure player bodies do not mask Layer 3.
- [ ] **Instance Validity:** Ensure any loops over `$Players.get_children()` handle freed practice-mode nodes safely.
- [ ] **Scene Tree Verification:** Run the scene integrity linter:
  ```bash
  py -3 tools/tscn_linter.py
  ```
- [ ] **Static Analysis:**
  ```bash
  py -3 tools/verify_gate.py --fast
  ```
- [ ] **Blast Radius Assessment:** Affects 25 direct dependent files across all 5 simulation layers:
  ```bash
  py -3 tools/dump_dep_graph.py --blast-radius pitch/PitchScene.gd
  ```
- [ ] **Deterministic Simulation Replay:**
  ```bash
  py -3 tools/replay_test.py
  ```

---

## 5. Known Risks & Errata Search Terms

When debugging match scene failures, consult [`AGENTS_ERRATA.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/AGENTS_ERRATA.md) for these documented edge cases:
- `Three latent runtime crashes found by static cross-referencing` (lines 1988–1992): `PitchScene` previously referenced `GameManager.score_team_a` and `MatchStatsTracker.fouls_a`; both are typed arrays (`score[TEAM_A]`, `fouls[TEAM_A]`).
- `ball-struck-signal-arg-count-mismatch` (lines 171–208): Discrepancies between signal emission and handler argument counts broke shot reporting.
- `touchline-bubble-is-one-shared-instance-home-perspective-only` (lines 866–890): Touchline manager commentary uses a single shared bubble instance aligned with the home perspective.
- `stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate` (lines 1187–1225): Match stage transitions occur at fractional thresholds (e.g. 0.833 for late game).
- `ERR-20260830-02`: Stale player reference exceptions during Practice Arena teardown.

---

## 6. Sources Examined

- [`pitch/PitchScene.gd`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/PitchScene.gd)
- [`pitch/PitchScene.tscn`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/PitchScene.tscn)
- [`pitch/README.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/README.md)
- [`docs/CORE_INVARIANTS.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/CORE_INVARIANTS.md)
- [`docs/API_SURFACE.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/API_SURFACE.md)
- [`AGENTS_ERRATA.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/AGENTS_ERRATA.md)
