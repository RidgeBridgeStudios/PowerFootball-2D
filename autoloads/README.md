# autoloads/ — Singletons & Global Services

Autoloads are the backbone of PowerFootball-2D's 3-layer manager-only architecture. They initialize in a fixed order (see below and `project.godot`) and must never reference each other directly in `_ready()` — use signal connections or deferred calls.

## Boot Order (project.godot)

1. **GameEvents** — Signal bus for inter-system events
2. **GameManager** — Thin scoreboard shell (score, phase, durations)
3. **MatchStatsTracker** — Quick-sim team stats and per-player rating container
4. **DataLoader** — League, team and player data (JSON)
5. **RefereeLoader** — Referee database
6. **ManagerLoader** — Manager database and formation library
7. **StaffLoader** — Staff database
8. **WorldEventLog** — Career narrative event log
9. **CareerManager** — Career state owner and day loop

**Invariant:** `GameEvents` boots FIRST; all four loaders precede `WorldEventLog`, which precedes `CareerManager`. `tools/gdcheck.py` enforces this and fails the gate if the order is broken. Do not change it without updating `docs/CORE_INVARIANTS.md`.

---

### GameEvents.gd

**Contract:** The ONLY signal bus. No system references another directly; all communication routes here. It carries exactly 11 signals:

| Signal | Meaning |
|---|---|
| `formation_changed(team, new_formation)` | Team formation changed via tactics |
| `lineup_changed(team)` | Starting XI / bench changed |
| `career_started(save_name, club_name)` | A new or loaded career became active |
| `career_day_advanced(iso_date)` | The day loop advanced one day |
| `career_advance_halted(reason)` | Continue stopped and needs the manager |
| `career_inbox_changed(unread_count, pending_decisions)` | Inbox state changed |
| `career_match_ready(home_team_index, away_team_index)` | A user fixture is ready |
| `career_result_recorded(home_score, away_score)` | A fixture result was folded in |
| `career_season_ended(season_year, final_position)` | Season rolled over |
| `career_manager_sacked(club_name, reason)` | The user was dismissed |
| `world_event_logged(event)` | A `WorldEvent` entered the log |

**DO NOT:**
- Reference other autoloads or scene nodes directly from GameEvents
- Emit cross-system signals from individual components instead of the bus
- Add signals beyond the documented set

---

### GameManager.gd

**Contract:** A thin scoreboard shell — the boundary between the career world and a resolved fixture. Members are ONLY:
- `TEAM_A`, `TEAM_B` — side constants
- `enum MatchPhase { PREGAME, FULL_TIME }` — the two states the career world observes
- `current_phase: MatchPhase`
- `score: Array[int]`
- `match_time: float`, `match_duration: float`, `half_duration_real_sec: float`, `simulated_match_time: float`
- `set_half_duration(real_sec: float)`

**Responsibilities:**
- Hold the last published score, phase and clock for the full-time view
- Be written by `QuickSimEngine.apply_to_match_stats_tracker()`, read by `MatchStatsUI` and `MatchStatsTracker`

**DO NOT:**
- Grow a phase machine, per-frame clock loop, set-piece state or shootout controller back into it
- Make gameplay decisions or hold duplicate career state

---

### MatchStatsTracker.gd

**Contract:** Pure quick-sim stats container. It no longer collects events from a live match; `QuickSimEngine` fills it.

**Responsibilities:**
- Hold the traditional stat arrays (shots, passes, fouls, cards, corners, offsides) and advanced stats (xG, PSxG, xT delta, packing, IMPECT, progressive actions, VAEP, …)
- Provide `reset()`, `stop_possession_sampling()` (no-op retained for API compatibility), `get_player_events()`, `compute_all_ratings()`, `get_stats(team_index)` and `get_advanced_stats(team_index)`
- Compute end-of-match player ratings (1.0–10.0) via `PlayerRatingCalculator.gd`

**DO NOT:**
- Sample live possession or assume a running real-time match exists
- Mutate `PlayerData` directly; provide ratings via `compute_all_ratings()`

---

### DataLoader.gd

**Contract:** Loads and owns the league: teams, squads and player data. Persists per slot.

**Responsibilities:**
- Load league JSON into `league: LeagueData`
- Expose `get_team(index)`, `get_team_by_name(...)`, `get_match_team(side)` and `get_player(team_index, squad_index)`
- Save changed league data via `save_league()`

**DO NOT:**
- Emit GameEvents
- Reference scene nodes

---

### RefereeLoader.gd

**Contract:** Referee database loader.

**Responsibilities:**
- `get_referee(index)`, `get_random_referee()`, `get_or_assign_referee(home_team_name, away_team_name)`
- `save_referees()` for persisted referee state

---

### ManagerLoader.gd

**Contract:** Manager database loader and owner of manager records for every club.

**Responsibilities:**
- `get_manager_for_team(team_name)`, `get_or_assign_manager(team_name)`, `all_available()`
- `save_managers()` for persisted manager state
- Formation library data consumed by the tactics UI — the formation-change signal is emitted by the UI, not by this loader

---

### StaffLoader.gd

**Contract:** Staff database loader.

**Responsibilities:**
- `get_staff_for_team(team_name)`, `get_assistant_manager`, `get_head_physio`, `get_tactical_analyst`, `all_available_staff()`
- `hire_staff(...)`, `terminate_staff(...)`, `save_staff()`

---

### WorldEventLog.gd

**Contract:** The club world's history book (Layer 1 → Layer 3). It is a live view over `CareerSaveData.world_events`, plus the append API and query helpers — it does NOT own the events; `CareerSaveData` persists them.

**Responsibilities:**
- `bind(career)`, `log_event(event)`, `record(...)`, `record_for_player(...)`
- Query helpers: `all_events()`, `recent()`, `for_player()`, `by_category()`, `since()`, `newsworthy()`
- `generate_press_reaction(event, manager)` via `PressOffice`, `clear()`

**DO NOT:**
- Treat autoload state as durable storage; the log must survive a save/load round trip, so `CareerSaveData` owns it

---

### CareerManager.gd

**Contract:** The career-state singleton. It owns the ONLY live `CareerSaveData`, drives the day loop, and is the only thing that mutates career state.

**Responsibilities:**
- `start_new_career(...)`, `load_career(slot)`, `save_career()`, `is_career_active()`
- `advance_day()` — one simulated day: recovery, training, scouting, transfers, AI club activity, inbox expiry, then fixtures
- `continue_until_event()` — repeats `advance_day()` until something needs the manager (the FM "Continue" button)
- `simulate_next_fixture()` — resolves the user's next fixture via `QuickSimEngine` and folds the outcome into table, finances, morale, board confidence, player records and cups
- Uses its own `_rng: RandomNumberGenerator`, seeded from `CareerSaveData.rng_seed`

`play_next_fixture()` and `record_user_match_result()` still exist but are no longer called by the UI.

**DO NOT:**
- Duplicate league ownership (that is `DataLoader`)
- Let the UI or narrative layer mutate career state

---

## Adding a New Autoload

1. Create the file in `autoloads/`
2. Register in `project.godot` (Project → Project Settings → Autoload)
3. Update the boot order in `docs/CORE_INVARIANTS.md` if it has dependencies on other autoloads
4. Emit all events through GameEvents; receive through signal connections in `_ready()`
5. Run `py -3 tools/gdcheck.py` to verify no undeclared members

---

## Notes

- Autoloads persist across scene changes; clear state explicitly when re-entering a career
- Avoid circular references by never calling another autoload in `_ready()`; use signal connections instead
- Never add a `class_name` to an autoload script — Godot 4.7 rejects a `class_name` that collides with the injected autoload global
