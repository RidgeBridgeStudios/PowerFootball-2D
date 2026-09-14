# PowerFootball 2D

A **manager-only** football management game built in **Godot 4.7** (GDScript) — Championship Manager / Football Manager style. You run a club: pick the team, manage the squad, staff, finances and board, and watch fixtures resolve through a statistical quick-sim engine.

**Vision:** Dwarf Fortress with a football. Simple visuals, deep social simulation. See @./POWERFOOTBALL_MASTER_VISION.md.

**Current state:** Manager Mode career is playable end to end — create a manager, take a club, advance the day loop, sim fixtures, and react to results. See @./ROADMAP.md for what's next.

## Running it

Open the project folder in Godot 4.7 and press F5. The main scene is `res://ui/SplashScreen.tscn`, which fades into `res://ui/MainMenu.tscn`.
The menu choices are: **Manager Mode**, **Quick Match** (standalone exhibition match isolated from career saves), **Options** (including custom league import), and **Quit**.

Manager Mode opens the manager/slot creation screen, loads or starts a career,
and hands off to the career hub (`res://ui/manager_mode/ManagerModeRoot.tscn`).
There is no real-time match to play: pressing Continue resolves the next fixture
through the quick-sim engine and folds the result back into the career world.

To execute the headless regression test suite:
```bash
godot --headless tests/TestRunner.tscn
```

## Architecture at a Glance

See **@./docs/CORE_INVARIANTS.md** for engine contracts and the 3-layer stack. See **@./llms.txt** for the static repo map.

```
autoloads/     GameEvents (signal bus), GameManager (scoreboard shell),
               MatchStatsTracker, career data loaders, WorldEventLog, CareerManager
shared/        QuickSimEngine, PlayerRatingCalculator, UtilityMath,
               data classes, career/ state, roles/ presets
shared/career/ CareerSaveData, fixtures, finances, transfers, inbox, morale, youth
entities/
  manager/     PressOffice (press reactions)
ui/            SplashScreen, MainMenu, OptionsMenu, MatchStatsUI, QuickSimModal,
               manager_mode/* (career hub and panels)
tools/         gdcheck.py (static checker)
docs/          CORE_INVARIANTS.md, json-schema.md (data import spec)
legacy/        Archived real-time match layer (skipped by all tools)
```

**Three architectural rules:**

1. **Nothing crosses systems directly.** Inter-system events route through the `GameEvents` signal bus.
2. **One match resolver.** Fixtures are resolved only by `shared/QuickSimEngine.gd` and published only through `apply_to_match_stats_tracker()`.
3. **Career state has one owner.** `CareerManager` owns the live `CareerSaveData`; the career UI and narrative layer never mutate it directly.

### The three layers

| Layer | Role | Key files |
|---|---|---|
| 1 — Career World | Squad, staff, finances, calendar, day loop | `autoloads/CareerManager.gd`, loaders, `shared/career/*` |
| 2 — Quick-Sim Match | Statistical match resolution, ratings, analytics | `shared/QuickSimEngine.gd`, `shared/PlayerRatingCalculator.gd`, `shared/UtilityMath.gd` |
| 3 — Narrative & Presentation | Event log, press, menus, career panels | `autoloads/WorldEventLog.gd`, `entities/manager/PressOffice.gd`, `ui/manager_mode/*` |

---

## What's Next?

See **@./ROADMAP.md** for the complete feature checklist.

See **@./POWERFOOTBALL_MASTER_VISION.md** for deep systems design, architectural rationale, and long-term vision.

---

## First Setup in Godot

1. Open the project folder in Godot 4.7
2. Godot regenerates `.import` files for `art/*.png` on first open
3. Confirm autoload boot order in Project Settings → Autoload
4. Press F5; the splash screen fades into the main menu, where Manager Mode starts a career

**Troubleshooting cyclic type references:** If Godot reports a cyclic reference between `Resource` data classes, type cross-references as the base `Resource` type instead of the specific class.
