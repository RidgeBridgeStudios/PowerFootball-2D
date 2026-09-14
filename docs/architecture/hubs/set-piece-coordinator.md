> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match architecture.**
> This hub documents a file from the abandoned 22-player real-time match engine. That code now lives archived under `legacy/` (excluded from Godot via `legacy/.gdignore` and skipped by every linter) and must never be cited as live or "fixed".
> It is retained as historical reference — useful when deepening `QuickSimEngine` — not as current implementation guidance.
> Current architecture: [architecture-pivot.md](../../agent-errata/architecture-pivot.md) · canonical contracts: [CORE_INVARIANTS.md](../../CORE_INVARIANTS.md).

# Architecture Hub: SetPieceCoordinator

**Canonical Location:** [`docs/architecture/hubs/set-piece-coordinator.md`](set-piece-coordinator.md)  
**Source Script:** [`pitch/SetPieceCoordinator.gd`](../../../legacy/pitch/SetPieceCoordinator.gd)  
**Simulation Layer:** Layer 1 — Physics & Kinematics (Match Coordination)  
**Node Type:** `SetPieceCoordinator` extends `Node` (Child of [`PitchScene`](../../../legacy/pitch/PitchScene.gd))  

---

## 1. Purpose and Non-Responsibilities

### Purpose
`SetPieceCoordinator` is the single authority for dead-ball restarts (throw-ins, goal kicks, corner kicks, direct/indirect free kicks, penalty kicks, and practice penalties). It receives out-of-bounds, foul, and offside events, resolves the applicable restart type, selects and positions the restart taker, freezes non-participating players via `SetPieceFreezeState`, enforces legal defensive wall distances (`wall_distance = 176.0`), coordinates human taker cycling (`action_switch`), and manages auto-activation timeouts for CPU takers.

### Non-Responsibilities
- **No Open-Play Ball Integration:** Ball flight, height decay, and spin are computed by [`Pseudo3DBall`](../../../legacy/entities/ball/Pseudo3DBall.gd).
- **No Penalty Shootout Coordination:** Post-match penalty shootouts are managed by [`PenaltyShootoutCoordinator`](../../../legacy/pitch/PenaltyShootoutCoordinator.gd).
- **No Officiating Judgments:** Foul decisions, cards, and offside calls are evaluated by [`MatchReferee`](../../../legacy/entities/referee/MatchReferee.gd) and [`OffsideDetector`](../../../legacy/entities/referee/OffsideDetector.gd).
- **No Direct Scene Tree Coupling:** It operates only on references provided via `bind(ball, boundary, players)`.

---

## 2. Public API, Signals, Events, Contracts & Dependencies

### Scene Hierarchy
Child of `PitchScene`: `$PitchScene/SetPieceCoordinator`. Contains a child `Timer` (`$ConfirmationTimer`) for managing taker input confirmation timeouts.

### Exported Properties & Constants
- `@export var penalty_spot_offset: float = 320.0` — Distance (pixels) from goal line to penalty spot.
- `@export var corner_flag_inset: float = 16.0` — Placement offset from pitch boundary corner.
- `@export var wall_distance: float = 176.0` — Minimum legal separation for defensive walls and markers.
- `@export var confirmation_timeout: float = 4.0` — Fallback auto-kick timeout for human restarts.
- `@export var cpu_confirmation_delay: float = 1.0` — Delay before a CPU taker executes the restart.
- `const PENALTY_AREA_DEPTH: float = 320.0`, `const PENALTY_AREA_HALF_WIDTH: float = 400.0`
- `const THROW_IN_INSET: float = 24.0` — Offset inside touchline preventing boundary sensor re-triggering.

### Key Public Methods
- `bind(ball: Pseudo3DBall, boundary: PitchBoundary, players: Node2D) -> void`: Injects required node references.
- `handle_out_of_bounds(side: String, exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void`:
  Routes boundary crossings to throw-ins, goal kicks, or corners.
- `handle_foul(fouler: HeavyPlayerController, victim: HeavyPlayerController, foul_pos: Vector2) -> void`:
  Determines whether a foul warrants a direct free kick or penalty kick.
- `handle_indirect_offside(defending_team: int, offside_pos: Vector2) -> void`:
  Sets up an indirect free kick restart from the offside offense coordinate.
- `start_penalty_with_taker(attacking_team: int, defending_team: int, designated_taker: HeavyPlayerController) -> void`
- `start_penalty_for_practice(attacking_team: int, defending_team: int) -> void`
- `start_kickoff(team: int) -> void`
- `can_switch_taker() -> bool`: Validates whether human `action_switch` can cycle takers (free kicks/penalties only).
- `get_taker() -> HeavyPlayerController`: Returns the current designated taker.

### Signals & Event Bus
- **Signals Connected:**
  - `_confirmation_timer.timeout` -> `_on_confirmation_timer_timeout`
- **Signals Emitted (via GameEvents):**
  - `GameEvents.defensive_wall_requested`
  - `GameEvents.player_switched` (when cycling takers)
  - `GameEvents.set_piece_taken`

### Core Dependencies
- Upstream: [`PitchBoundary`](../../../legacy/pitch/PitchBoundary.gd), [`MatchReferee`](../../../legacy/entities/referee/MatchReferee.gd), [`OffsideDetector`](../../../legacy/entities/referee/OffsideDetector.gd), [`GameManager`](../../../autoloads/GameManager.gd).
- Downstream: [`HeavyPlayerController`](../../../legacy/entities/player/HeavyPlayerController.gd), [`PlayerBrain`](../../../legacy/entities/player/PlayerBrain.gd), [`Pseudo3DBall`](../../../legacy/entities/ball/Pseudo3DBall.gd).

---

## 3. State Model & Architectural Invariants

### Restart Phase Flow
```text
Event Received (foul / out-of-bounds / offside)
  ↓
Freeze Players → Set non-takers to PlayerState.SET_PIECE_FREEZE
  ↓
Position Ball & Defensive Wall (wall_distance = 176.0)
  ↓
Assign Taker → Mark ball.mark_set_piece_restart(taker)
  ↓
Awaiting Confirmation (Human: action_kick / CPU: timer delay)
  ↓
Activate Set Piece → Transition taker to ChargeKickState / ThrowInState
  ↓
Release Play → Resume GameManager.MatchPhase.IN_PLAY
```

### Anti-Double-Touch Law
Upon positioning the ball, the coordinator executes `ball.mark_set_piece_restart(taker)`. The taker is forbidden from touching the ball a second time until another player (teammate or opponent) makes contact.

### Non-Reentrant Guard Invariant
`handle_out_of_bounds()` and `handle_foul()` immediately discard calls if a set piece is already active (`_awaiting_confirmation || GameManager.is_set_piece_active()`), preventing event pile-up race conditions.

---

## 4. Change-Impact Checklist

When modifying `SetPieceCoordinator.gd`:
- [ ] **Boundary Clearances:** Verify `THROW_IN_INSET` and corner flag offsets keep the ball inside legal playable bounds.
- [ ] **Wall Positioning:** Confirm defensive walls do not push players outside pitch boundaries.
- [ ] **Fast Gate:**
  ```bash
  py -3 tools/verify_gate.py --fast
  ```
- [ ] **Blast Radius Assessment:** Affects 9 direct dependent files across physics, AI, and officiating:
  ```bash
  py -3 tools/dump_dep_graph.py --blast-radius pitch/SetPieceCoordinator.gd
  ```
- [ ] **Simulation Harness:** Run 60s headless simulation to verify dead-ball transitions:
  ```bash
  py -3 tools/eval_simulation.py --duration=60
  ```

---

## 5. Known Risks & Errata Search Terms

When investigating restart glitches, consult [`AGENTS_ERRATA.md`](../../../AGENTS_ERRATA.md) for these documented edge cases:
- `kickoff-backward-pass-veto-starves-taker` (lines 53–100): Kickoff confinement rules required backward passing support in pass evaluations.
- `throw-in-ball-outside-chase-legality-rect` (lines 1922–1940): Placing throw-in ball too close to the boundary line caused sensor re-triggering.
- `ERR-20260831-01`, `ERR-20260831-02`, `ERR-20260831-03` (lines 1697–1830): Out-of-bounds events firing simultaneously with foul whistles required strict reentrancy gating.

---

## 6. Sources Examined

- [`pitch/SetPieceCoordinator.gd`](../../../legacy/pitch/SetPieceCoordinator.gd)
- [`pitch/README.md`](../../../legacy/pitch/README.md)
- [`docs/CORE_INVARIANTS.md`](../../CORE_INVARIANTS.md)
- [`docs/API_SURFACE.md`](../../API_SURFACE.md)
- [`AGENTS_ERRATA.md`](../../../AGENTS_ERRATA.md)
