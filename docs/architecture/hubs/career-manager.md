# Architecture Hub: CareerManager

**Canonical Location:** [`docs/architecture/hubs/career-manager.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/architecture/hubs/career-manager.md)  
**Source Script:** [`autoloads/CareerManager.gd`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/CareerManager.gd)  
**Simulation Layer:** Layer 4 — Club World & Persistent Entities  
**Node Type:** Autoload Singleton (`Node`, registered in `project.godot`)  

---

## 1. Purpose and Non-Responsibilities

### Purpose
`CareerManager` is the authoritative state and progression singleton for Manager Career Mode. Acting as `GameManager`'s off-pitch counterpart, it owns the active `CareerSaveData` resource, executes the continuous calendar day loop (`advance_day`, `continue_until_event`), handles player recovery, progression, and physical decline, processes transfer market bids and contract negotiations, coordinates scouting assignments, tracks board objectives and financial budgets, and manages squad assignments (Senior vs. U23). It serves as the primary bridge from persistent career history into match gameplay by seeding `MoodSystem` and `TrustSystem` via `apply_career_state_to_player()`.

### Non-Responsibilities
- **No Real-Time Match Simulation:** Does not run pitch physics, ball flight, or frame-by-frame player kinematics. Match gameplay is executed by [`PitchScene`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/pitch/PitchScene.gd), and quick results are calculated via statistical resolution in `simulate_next_fixture()`.
- **No League Database Ownership:** The static league catalog, base attributes, and team rosters are loaded and owned by [`DataLoader`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/DataLoader.gd). `CareerManager` saves and applies career-specific delta states per slot.
- **No Direct Narrative Generation:** Narrative history and press reactions are logged through [`WorldEventLog`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/WorldEventLog.gd) and surfaced by [`PressOffice`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/entities/manager/PressOffice.gd).
- **No `class_name` Declaration:** As an autoload singleton in Godot 4.7+, declaring `class_name` is forbidden to prevent global namespace collision.

---

## 2. Public API, Signals, Events, Contracts & Dependencies

### Process Mode & Boot Order
- **Boot Order (`project.godot`):** Initialized after all loaders and loggers:
  `DataLoader` → `RefereeLoader` → `ManagerLoader` → `StaffLoader` → `WorldEventLog` → `CareerManager` → `InputHelper`.
- **Process Mode:** `process_mode = Node.PROCESS_MODE_ALWAYS` (runs even when match scenes or menus are paused).

### Enums & Constants
- `enum HaltReason { NONE, MATCH_DAY, INBOX_DECISION, SEASON_END, SACKED, TRANSFER_RESPONSE }`
- `const MAX_CONTINUE_DAYS: int = 120` — Safety circuit breaker preventing infinite loops during day advancement.
- `const SEASON_START_MONTH: int = 7`, `const SEASON_START_DAY: int = 1` (July 1st).
- `const FIRST_MATCHDAY_MONTH: int = 8`, `const FIRST_MATCHDAY_DAY: int = 8` (August 8th).
- `const LAST_MATCHDAY_MONTH: int = 5`, `const LAST_MATCHDAY_DAY: int = 17` (May 17th).
- `const MIN_MATCHDAY_SPACING_DAYS: int = 3` — Minimum spacing between competitive fixtures.
- `const SEASON_END_MONTH: int = 6`, `const SEASON_END_DAY: int = 1` (June 1st).
- `const SUMMER_WINDOW_MONTHS: Array[int] = [7, 8]`, `const WINTER_WINDOW_MONTH: int = 1`.

### Public Properties
- `career: CareerSaveData = null` — The active live career state (null when in main menu or exhibition).

### Key Public Methods
- **Career Lifecycle:**
  - `start_new_career(profile: ManagerCareerProfile, team_index: int, slot: int) -> CareerSaveData`
  - `load_career(slot: int) -> bool`
  - `save_career() -> bool`
  - `close_career() -> void`
  - `is_career_active() -> bool`
- **Calendar & Progression:**
  - `advance_day() -> HaltReason`: Simulates one calendar day (stamina recovery, injury ticks, transfer bids, fixture execution).
  - `continue_until_event() -> HaltReason`: Repeats day advancement until manager intervention is required.
  - `play_next_fixture() -> bool`: Configures `GameManager` and pre-game data to launch `PitchScene`.
  - `simulate_next_fixture() -> FixtureData`: Instant analytical resolution of the manager's upcoming match.
  - `record_user_match_result(home_score: int, away_score: int) -> void`: Updates league tables, player match ratings, fatigue, and morale following a played match.
- **Club Management & Transfers:**
  - `resolve_inbox_item(item: InboxItem, option_index: int) -> void`
  - `submit_transfer_bid(team_index: int, squad_index: int, fee: int) -> TransferOffer`
  - `raise_transfer_bid(offer: TransferOffer, new_fee: int) -> void`
  - `offer_personal_terms(offer: TransferOffer, wage: int = -1) -> void`
  - `file_board_request(kind: BoardState.RequestKind) -> void`
  - `move_player_to_u23(player_key: int) -> void` / `move_player_to_senior(player_key: int) -> void`
  - `hire_staff_member(staff: StaffData, weekly_salary: int, years: int) -> bool`
  - `assign_scout_to_region(scout_name: String, region: String) -> void`
- **Career-to-Match Bridge:**
  - `apply_career_state_to_player(player: HeavyPlayerController, team_index: int, squad_index: int) -> void`:
    Seeds player morale into `MoodSystem` and chemistry/relationship ratings into `TrustSystem`.

### Signals & Event Bus
- **Signals Emitted (via GameEvents):**
  - `GameEvents.career_started`
  - `GameEvents.career_day_advanced`
  - `GameEvents.career_inbox_changed`
  - `GameEvents.career_advance_halted`
  - `GameEvents.career_match_ready`
  - `GameEvents.career_result_recorded`
  - `GameEvents.career_season_ended`
  - `GameEvents.career_manager_sacked`

### Core Dependencies
- Upstream: [`DataLoader`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/DataLoader.gd), [`ManagerLoader`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/ManagerLoader.gd), [`StaffLoader`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/StaffLoader.gd), [`RefereeLoader`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/RefereeLoader.gd), [`WorldEventLog`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/WorldEventLog.gd), [`GameEvents`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/GameEvents.gd), [`GameManager`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/GameManager.gd).
- Downstream / Resources: All 18 career resources in `shared/career/` (`CareerSaveData`, `BoardState`, `ContractData`, `ScoutReport`, `TransferOffer`, `MoraleEngine`, `ProgressionEngine`, `CareerSerializer`), [`ManagerModeRoot`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/ui/manager_mode/ManagerModeRoot.gd).

---

## 3. State Model & Architectural Invariants

### Single Ownership Contract
`CareerManager` owns the ONLY live `CareerSaveData` instance. Individual UI panels and match scenes must never retain divergent copies of career state or modify attributes directly.

### Career-to-Match Morale Seeding Invariant
When launching a match, `apply_career_state_to_player()` maps career morale to in-match `MoodSystem` states using an asymmetric threshold curve:
- High Morale ($\ge 0.70$): Biased toward `STREAK` form.
- Baseline Morale ($0.50$–$0.69$): Maps to `NORMAL` form.
- Depressed Morale ($< 0.45$): Triggers `SLUMP` form penalties.

### Dynamic Calendar Spacing
Matchday calendar spacing is dynamically derived from the total round count and the target closing matchday date (May 17), ensuring leagues of any size (8–20 teams) pace naturally across the sporting year without early seasonal collapse.

---

## 4. Change-Impact Checklist

When modifying `CareerManager.gd`:
- [ ] **Database Integrity:** Run the schema validation test suite:
  ```bash
  py -3 tools/verify_db.py
  py -3 tools/validate_schemas.py
  ```
- [ ] **Cross-Reference Checking:** Verify all member access using the static symbol checker:
  ```bash
  py -3 tools/lint_xref.py
  ```
- [ ] **Fast Gate:**
  ```bash
  py -3 tools/verify_gate.py --fast
  ```
- [ ] **Serialization & Save Versioning:** If changing fields on `CareerSaveData`, confirm that `CareerSerializer` backwards compatibility is preserved.

---

## 5. Known Risks & Errata Search Terms

When investigating career progression or save state bugs, consult [`AGENTS_ERRATA.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/AGENTS_ERRATA.md) for these documented edge cases:
- `Session State: 2026-09-02 (Manager Career Mode, Phase 4)` (lines 1970–2049):
  - `RefereeLoader.get_or_assign_referee()`: Implemented deterministic assignment so all screens reference the identical referee for a given fixture.
  - `TrustSystem.trust_multiplier()` clamp fix: Fixed input clamping so neutral trust (1.0) does not map to maximum bonus.
  - Player decline curve calibration: Replaced steep linear pace decay with a gradual aging curve modified by player traits.
  - Morale-to-MoodSystem curve calibration: Made threshold asymmetric so merely "Restless" players do not plunge into SLUMP.
  - Calendar rhythm: Spacing derived from round count rather than a hard 7-day interval to prevent premature November finishes.

---

## 6. Sources Examined

- [`autoloads/CareerManager.gd`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/CareerManager.gd)
- [`autoloads/README.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/autoloads/README.md)
- [`docs/CORE_INVARIANTS.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/CORE_INVARIANTS.md)
- [`docs/API_SURFACE.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/docs/API_SURFACE.md)
- [`AGENTS_ERRATA.md`](file:///f:/PowerFootball-2D-main/PowerFootball-2D-main/AGENTS_ERRATA.md)
