# CORE_INVARIANTS.md — PowerFootball-2D Architectural & Engine Invariants

**Canonical Single Source of Truth for all Agents (Antigravity, Gemini, Claude, DeepSeek, Human Developers).**

All agents, workflows, and tools reference this document for universal engine contracts, simulation layer rules, and file choke points.

---

## 1. Engine Lock

**Godot 4.7-stable · GDScript 2.0 ONLY · Strictly Typed**

### Prohibited / Strictly Forbidden APIs
| Forbidden | Replacement | Rationale / Context |
|---|---|---|
| `yield(...)` | `await ...` | Godot 4 coroutine syntax |
| `KinematicBody2D` | `CharacterBody2D` | Godot 4 2D physics body |
| `RigidBody` | `RigidBody2D` | 2D physics type specificity |
| `file.open()` / `File.new()` | `FileAccess.open(...)` | Godot 4 FileAccess static API |
| `dir.open()` / `Directory.new()` | `DirAccess.open(...)` | Godot 4 DirAccess static API |
| `OS.get_ticks_msec() / 1000` | `Time.get_ticks_msec()` | Godot 4 Time singleton |
| `export(...)` | `@export` | Godot 4 annotation |
| `onready var` | `@onready var` | Godot 4 annotation |

### Strict Typing Invariant
Every variable declaration, function parameter, and function return type MUST be explicitly typed:
- **CORRECT:** `var score_home: int = 0`
- **INCORRECT:** `var score_home = 0`
- **CORRECT:** `func calculate_xg(distance: float, angle: float) -> float:`
- **INCORRECT:** `func calculate_xg(distance, angle):`
- **CORRECT:** `for team: TeamData in league.teams:`
- **INCORRECT:** `for team in league.teams:`

### Scene Initialization & Serialization
- Node references must use `@onready var`.
- Exported properties must use `@export var name: Type`.
- Any node instantiated dynamically in GDScript meant for scene persistence must set `.owner = scene_root` before saving.

---

## 2. Simulation Stack

PowerFootball-2D is a **manager-only quick-sim football game**. There is no real-time match engine, no player control, no ball physics, and no per-frame AI. A fixture is resolved statistically and the career world reacts to the result.

Three-layer upward propagation model:

```text
LAYER 3 — NARRATIVE & PRESENTATION   WorldEventLog, PressOffice, ui/manager_mode/*,
                                       MatchStatsUI, QuickSimModal, MainMenu
                                         ↑ reads career facts and resolved results
LAYER 2 — QUICK-SIM MATCH            QuickSimEngine, PlayerRatingCalculator,
                                       UtilityMath, MatchStatsTracker
                                         ↑ resolves two squads into a scoreline,
                                           stats, ratings and match events
LAYER 1 — CAREER WORLD               CareerManager, loaders, shared data classes,
                                       shared/career/*, CareerProgressionEngine
```

### Cross-Layer Architectural Invariant
Career facts originate in Layer 1, are resolved into a fixture result in Layer 2, and are narrated and presented in Layer 3. Layer 3 never mutates career state — it reads `CareerManager.career` and `WorldEventLog`. Layer 2 is pure: `QuickSimEngine` and `PlayerRatingCalculator` expose stateless static functions.

### Per-Layer File Scope
- **Layer 1 — Career World:** `autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `autoloads/ManagerLoader.gd`, `autoloads/RefereeLoader.gd`, `autoloads/StaffLoader.gd`, `shared/career/*`, `shared/TeamData.gd`, `shared/PlayerData.gd`, `shared/LeagueData.gd`, `shared/ManagerData.gd`, `shared/RefereeData.gd`, `shared/StaffData.gd`, `shared/TeamManagementData.gd`, `shared/NationDatabase.gd`, `shared/CareerProgressionEngine.gd`.
- **Layer 2 — Quick-Sim Match:** `shared/QuickSimEngine.gd`, `shared/PlayerRatingCalculator.gd`, `shared/UtilityMath.gd`, `autoloads/MatchStatsTracker.gd`.
- **Layer 3 — Narrative & Presentation:** `autoloads/WorldEventLog.gd`, `entities/manager/PressOffice.gd`, `ui/manager_mode/*`, `ui/MainMenu.gd`, `ui/OptionsMenu.gd`, `ui/MatchStatsUI.gd`, `ui/QuickSimModal.gd`.
- **Shared tactical data (consumed by Layers 1–2):** `shared/FormationLibrary.gd`, `shared/FormationRegistry.gd`, `shared/PlayerRoleConfig.gd`, `shared/roles/*.tres`.

---

## 3. Critical File Contracts (Choke Points)

| File | Contract | Must Never Do |
|---|---|---|
| `autoloads/GameEvents.gd` | The ONLY signal bus. Carries exactly 11 signals: `formation_changed`, `lineup_changed`, `career_started`, `career_day_advanced`, `career_advance_halted`, `career_inbox_changed`, `career_match_ready`, `career_result_recorded`, `career_season_ended`, `career_manager_sacked`, `world_event_logged`. | Emit cross-system signals from individual components directly; grow the bus beyond the documented set. |
| `autoloads/CareerManager.gd` | Owns the ONLY live `CareerSaveData`. Drives the day loop (`advance_day()`, `continue_until_event()`) and is the only thing that mutates career state. | Let another system mutate career state; keep a second live `CareerSaveData`. |
| `shared/QuickSimEngine.gd` | `simulate_match()` is the ONLY match resolver. `apply_to_match_stats_tracker()` is the ONLY place a `QuickSimResult` is published into `GameManager` and `MatchStatsTracker`. | Write match state outside `apply_to_match_stats_tracker()`; add a second match resolver. |
| `autoloads/GameManager.gd` | Thin scoreboard shell. Members ONLY: `TEAM_A`, `TEAM_B`, `enum MatchPhase { PREGAME, FULL_TIME }`, `current_phase`, `score`, `match_time`, `match_duration`, `half_duration_real_sec`, `simulated_match_time`, `set_half_duration()`. | Grow a phase machine, clock loop, set-piece state or shootout controller back into it. |
| `autoloads/MatchStatsTracker.gd` | Pure quick-sim stats container: stat arrays plus `reset()`, `stop_possession_sampling()` (no-op), `get_player_events()`, `compute_all_ratings()`, `get_stats()`, `get_advanced_stats()`. | Sample live possession; assume a running match exists. |
| `shared/PlayerRatingCalculator.gd` | Pure 1.0–10.0 player rating function over one player's `PlayerMatchEvents`. No state, no signals, no Node. | Hold match state or emit signals. |
| `shared/PlayerData.gd` | Player attributes, personality, traits, contract, morale and career stats. Persists across matches. | Mutate attributes directly from outside call sites; use class methods only. |
| `shared/PlayerRoleConfig.gd` | Data-driven role tuning resource (`.tres` presets in `shared/roles/`): `anchor_weight`, `max_chase_distance`, pass utility weights `w_dist`/`w_angle`/`w_press`/`w_adv`, and normalized `pitch_bounds`. | Assume a config is assigned — always guard reads with `if config != null`. |
| `docs/course_implementation_specification.md` | READ-ONLY reference specification: build phases, FSM patterns, formulas, data models, gotchas. Consult before starting any new phase. | Modify this file. It is a reference artifact only. |

### Boot Order (`project.godot`)
`GameEvents` → `GameManager` → `MatchStatsTracker` → `DataLoader` → `RefereeLoader` → `ManagerLoader` → `StaffLoader` → `WorldEventLog` → `CareerManager`

*Constraints:* `GameEvents` boots FIRST; all loaders (`DataLoader`, `RefereeLoader`, `ManagerLoader`, `StaffLoader`) precede `WorldEventLog`, which precedes `CareerManager`. `tools/gdcheck.py` enforces this ordering and fails the gate if it is broken.

---

## 4. Quick-Sim & Career Invariants

### Match Resolution & Publishing
- A fixture is resolved ONLY by `QuickSimEngine.simulate_match()`. Nothing else produces a scoreline.
- The result is published ONLY through `QuickSimEngine.apply_to_match_stats_tracker()`, which writes `GameManager.score`, sets `current_phase = MatchPhase.FULL_TIME`, and populates `MatchStatsTracker` and its per-player events.
- `QuickSimResult` carries the scoreline, probabilities, match events, per-player `PlayerMatchEvents`, per-player ratings, team stats and advanced stats.

### Rating Contract
- `PlayerRatingCalculator.calculate()` returns a rating in `[1.0, 10.0]`.
- `BASE_RATING = 6.70` is the centre of the distribution; a sent-off player is confined to `[5.20, 5.80]`.

### Career State Ownership
- `CareerManager` owns the ONLY live `CareerSaveData`; `DataLoader` owns the league (squads, attributes) and persists it via `DataLoader.save_league()`.
- `CareerManager` uses its own `_rng: RandomNumberGenerator`, seeded from `CareerSaveData.rng_seed`, for world simulation. Quick-sim stat sampling inside `QuickSimEngine` draws from the global RNG.

### Match-Day Flow
`ui/manager_mode/ManagerModeRoot.gd::_on_continue_pressed()` → `CareerManager.simulate_next_fixture()` → `QuickSimEngine.simulate_match()` → `CareerManager._apply_fixture_result()` (league table, finances, morale, board confidence, player records, cups). The career UI never leaves `ManagerModeRoot` to play a match. `CareerManager.play_next_fixture()` and `record_user_match_result()` still exist but are no longer called by the UI.

### Legacy Archive
The retired real-time match layer (entities, pitch, match HUD, in-match states) lives under `legacy/`, which is skipped by all verification tools via `legacy/.gdignore`.

---

## 5. Static Verification & Autoload Handling

### Verification Choke Point
Static analysis is executed via:
```bash
python3 tools/gdcheck.py || python tools/gdcheck.py || py -3 tools/gdcheck.py
```
**Invariant:** 0 errors required before committing or completing any turn.

### Autoload Handling Contract
`gdcheck.py` parses `[autoload]` in `project.godot` and registers autoload singleton names as known global types.
Godot 4.7+ rejects a `class_name` that collides with an autoload singleton. **Never add a `class_name` to an autoload script to fix a type warning.**
