# ui/ — Menus, Career Screens, & Match Presentation

All user-facing screens. In the manager-only architecture this is Layer 3 (Narrative & Presentation): the UI reads career state and resolved match results, and never drives a live match.

## Architecture Overview

```
SplashScreen.tscn (main scene, fades into the menu)
  └─ MainMenu.tscn
       ├─ Manager Mode → manager_mode/ManagerCreationScreen.tscn
       │                    └─ manager_mode/ManagerModeRoot.tscn (career hub)
       ├─ OptionsMenu.tscn
       └─ Quit

ManagerModeRoot.tscn — the career never leaves this scene to play a match
  ├─ Career panels: Overview, Inbox, Squad, Tactics, Training, Transfers,
  │    Scouting, Staff, Fixtures, League, Finances, Board, Calendar
  ├─ QuickSimModal.tscn (manual quick-sim modal)
  └─ MatchStatsUI.tscn (full-time result and ratings view)
```

**Archive note:** the pre-pivot real-time match screens (HUD, pre-game, pause, tactics diagram, touchline overlays) now live under `legacy/ui/` and are not part of the live UI tree.

## Key Scenes

### SplashScreen.tscn

**Responsibilities:**
- The project's main scene: fade in, hold, then load `MainMenu.tscn`
- Allow skipping the splash with input

---

### MainMenu.tscn

**Responsibilities:**
- Display exactly three buttons: **Manager Mode**, **Options**, and **Quit**
- Route Manager Mode to `manager_mode/ManagerCreationScreen.tscn` (creation/slot selection decides whether to load a career or start a new one)
- Open `OptionsMenu.tscn` and confirm quit via a dialog

---

### OptionsMenu.tscn

**Responsibilities:**
- Adjust audio buses (master/music/SFX), fullscreen, and FPS display
- Select half duration; written through `GameManager.set_half_duration()`
- Emit `menu_closed` so the main menu can restore focus

---

### manager_mode/ManagerCreationScreen.tscn

**Responsibilities:**
- Render career slots and create-or-load selection
- Gather manager identity and pick a club/job
- Populate `CareerManager` and hand off to `manager_mode/ManagerModeRoot.tscn`

---

### manager_mode/ManagerModeRoot.tscn

**Responsibilities:**
- The career hub. Sidebar navigation swaps one `CareerPanel` subclass into the content host at a time: `OverviewPanel`, `InboxPanel`, `SquadPanel`, `TacticsPanel`, `TrainingPanel`, `TransfersPanel`, `ScoutingPanel`, `StaffPanel`, `FixturesPanel`, `LeaguePanel`, `FinancesPanel`, `BoardPanel`, `CalendarPanel`
- Drive the Continue loop: `_on_continue_pressed()` calls `CareerManager.simulate_next_fixture()`, which resolves the next fixture through `QuickSimEngine` and folds the result back into the career
- Surface contract negotiation (`ContractNegotiationModal.gd`), theming (`CareerTheme.gd`, `CareerThemePalette`) and shared panel base (`CareerPanel.gd`)

---

### QuickSimModal.tscn

**Responsibilities:**
- Present a pre-sim summary and open a manual quick-sim
- On completion, emit `match_completed(result: QuickSimEngine.QuickSimResult)` for the caller to consume
- Emit `modal_closed` when dismissed

---

### MatchStatsUI.tscn

**Responsibilities:**
- Full-time view populated from `MatchStatsTracker` and the published `QuickSimResult`
- Tabs for the summary, traditional stats and advanced stats (xG, PSxG, xT, packing, progressive actions)
- Display per-player match ratings (1.0–10.0) computed by `PlayerRatingCalculator.gd`
- Emit `stats_dismissed` to return control to the career hub

---

## Presentation Contract

- All UI updates are passive: listen to the `GameEvents` signal bus; never mutate career state or match state directly.
- Career panels read `CareerManager.career` and the `shared/career/*` data classes; they do not own career state.
- Match presentation reads results published by `QuickSimEngine.apply_to_match_stats_tracker()`; the UI never resolves a fixture itself.

**DO NOT:**
- Change scene out of `ManagerModeRoot` to play a match
- Duplicate career or match state in UI nodes
- Emit cross-system signals outside `GameEvents`

---

## Themes & Styling

Career screens use the shared career theme (`CareerTheme.gd`, `manager_mode_theme.tres`, `shared/career/CareerThemePalette.gd`) for a clean, flat management-game look.
