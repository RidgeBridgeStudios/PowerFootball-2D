# Architecture Pivot Errata — Manager-Only Quick-Sim

**Simulation Stack:** 3 layers — Career World → Quick-Sim Match → Narrative & Presentation  
**Primary Modules:** `shared/QuickSimEngine.gd`, `autoloads/CareerManager.gd`, `autoloads/MatchStatsTracker.gd`, `autoloads/GameManager.gd`, `autoloads/GameEvents.gd`  
**Applies To:** Every agent and contributor working anywhere in this repository.

This page is the canonical record of the manager-only pivot. Read it before trusting any document, comment, or symbol reference that names the real-time match layer — and before "fixing" a file that no longer exists at its old path.

---

## Table of Contents
- [1. What changed and why](#1-what-changed-and-why)
- [2. The `legacy/` archive](#2-the-legacy-archive)
- [3. The new 3-layer stack](#3-the-new-3-layer-stack)
- [4. Non-obvious consequences an agent can trip over](#4-non-obvious-consequences-an-agent-can-trip-over)
- [5. Tooling, verification, and where to look next](#5-tooling-verification-and-where-to-look-next)

---

## 1. What changed and why

This project is now a **manager-only football game** in the Championship Manager 01/02 / Football Manager tradition. The user manages a club from the dugout: tactics, transfers, contracts, finance, board confidence, inbox decisions, and a season calendar. There is **no player control, no real-time match engine, no ball physics, and no per-frame AI**.

Matches are resolved entirely by [`shared/QuickSimEngine.gd`](../../shared/QuickSimEngine.gd) — a deterministic statistical simulator. A full season resolves in seconds.

Before the pivot the project was a **real-time 22-player physics football game with a career mode bolted on**: a `CharacterBody2D` player controller, possession-state ball physics, a utility-scored per-frame `PlayerBrain`, a referee crew, a `PitchScene` match harness, and a match-time HUD. That layer and the career layer were maintained in parallel, and every match-day feature had to be built twice.

The pivot retired the real-time layer wholesale instead of keeping two match resolvers alive:

- **One match resolver, one truth.** `QuickSimEngine` is the only thing that produces a match result. Nothing else may publish a score.
- **The career world became the product**, not an accessory to the pitch.
- **The archived code was kept, not deleted**, because its math and tuning remain directly useful when deepening the statistical model (see §5).

> [!IMPORTANT]
> If a document or comment tells you to edit `PlayerBrain`, `MatchWorldModel`, `HeavyPlayerController`, `Pseudo3DBall`, `SetPieceCoordinator`, `PitchScene`, `InputHelper`, or `MatchTelemetryLogger`, treat it as **historical**. Those files are archived and their old paths are empty. Current guidance lives in [CORE_INVARIANTS.md](../CORE_INVARIANTS.md) and this page.

---

## 2. The `legacy/` archive

68 `.gd` files plus scenes, shaders, and READMEs were moved to `legacy/` — **not deleted**. The archive layout is:

```
legacy/
├── .gdignore
├── autoloads/
│   ├── MatchWorldModel.gd
│   ├── MatchTelemetryLogger.gd
│   └── InputHelper.gd
├── entities/
│   ├── ball/         (Pseudo3DBall.gd/.gdshader, BallState.gd, BallStateFactory.gd, Ball.tscn,
│   │                  states/{DeadBallState,FlightState,GroundRollState,PossessionState}.gd, README.md)
│   ├── goalkeeper/   (GoalkeeperDiveBrain.gd)
│   ├── manager/      (ManagerDirector.gd, ManagerVisual.gd, README.md)
│   ├── player/       (HeavyPlayerController.gd, PlayerBrain.gd, MoodSystem.gd, TrustSystem.gd,
│   │                  PlayerState.gd, PlayerStateFactory.gd, PlayerVisual.gd, FacingArrow.gd,
│   │                  HeavyPlayer.tscn, PlayerDot.gdshader, README.md,
│   │                  states/{Aerial,Celebrate,ChargeKick,Dribble,GoalkeeperDive,GoalkeeperHold,
│   │                          Idle,Move,PenaltyKick,SetPieceFreeze,ShotLock,Tackle,ThrowIn}State.gd)
│   └── referee/      (MatchReferee.gd, OffsideDetector.gd, MatchOfficialCrew.gd,
│                      CenterRefereeVisual.gd, AssistantRefereeVisual.gd, FourthOfficialVisual.gd,
│                      WhistleSynthesizer.gd, README.md)
├── pitch/            (PitchScene.gd/.tscn, PitchBoundary.gd, PitchMarkings.gd, SetPieceCoordinator.gd,
│                      PenaltyShootoutCoordinator.gd, GoalCelebrationCoordinator.gd,
│                      GoalReplayCoordinator.gd, GoalNet.gd, GoalZone.gd, MatchCamera.gd,
│                      MatchIntroDirector.gd, Minimap.gd/.tscn, StadiumGraphics.gd, README.md)
├── shared/           (CollisionLayers.gd, PassUtilityScorer.gd, FormationAnchorMath.gd, PlayerFactory.gd)
└── ui/               (HUD.gd/.tscn, ActionText.gd/.tscn, TouchlineBubble.gd/.tscn,
                       MatchIntroUI.gd/.tscn, KickOffMenu.gd/.tscn, FormationDiagram.gd,
                       pregame/, pause/, tactics/)
```

### `legacy/` is invisible to the engine and to every linter

- [`legacy/.gdignore`](../../legacy/.gdignore) makes Godot skip the entire tree at import time. The archived scripts are never compiled, never parsed into the global class cache, and never appear in the editor.
- Every linter and generator in the verification gate also skips `legacy/`, so **breakage inside the archive is invisible to `verify_gate.py`**: `gdcheck.py`, `lint_invariants.py`, `lint_scope.py`, `lint_type_comparisons.py`, `lint_stringnames.py`, `lint_shadowing.py`, `lint_allocations.py`, `lint_xref.py`, `tscn_linter.py`, `dump_api.py`, `generate_symbols.py`, and `dump_dep_graph.py`.

**Consequences — read these as rules:**

1. **Archived code must never be cited as live.** A symbol existing under `legacy/` does not mean the game still runs it. Check whether the path is under `legacy/` before quoting it as a contract.
2. **Archived code must not be "fixed."** Editing it produces no engine import and no lint coverage; the change is unverifiable and out of scope. If archived math needs to change, port it into a live file (typically `shared/QuickSimEngine.gd` or `shared/UtilityMath.gd`) and verify there.
3. **Live code must not reference archived code.** Nothing at a live path may `preload`/`load` a `legacy/` script, and no live scene may instance a `legacy/` scene. All 12 tools skip the tree, so such a reference would only fail at runtime in Godot.

---

## 3. The new 3-layer stack

The former 5-layer stack (Physics → Match AI → Match Social → Club World → Narrative) collapsed to three layers because the first three were all facets of the retired real-time engine.

| Layer | Name | Scope |
|---|---|---|
| **1** | **Career World** | `autoloads/CareerManager.gd`, `DataLoader`, `ManagerLoader`, `RefereeLoader`, `StaffLoader`, `shared/career/*`, `shared/{TeamData,PlayerData,LeagueData,ManagerData,RefereeData,StaffData,TeamManagementData,NationDatabase}.gd`, `shared/CareerProgressionEngine.gd` |
| **2** | **Quick-Sim Match** | `shared/QuickSimEngine.gd`, `shared/PlayerRatingCalculator.gd`, `shared/UtilityMath.gd`, `autoloads/MatchStatsTracker.gd` |
| **3** | **Narrative & Presentation** | `autoloads/WorldEventLog.gd`, `entities/manager/PressOffice.gd`, `ui/manager_mode/*`, `ui/MainMenu.gd`, `ui/OptionsMenu.gd`, `ui/MatchStatsUI.gd`, `ui/QuickSimModal.gd` |

### Autoload boot order (9, in `project.godot` order)

```
GameEvents → GameManager → MatchStatsTracker → DataLoader → RefereeLoader
           → ManagerLoader → StaffLoader → WorldEventLog → CareerManager
```

- `GameEvents` **must boot first**; `tools/gdcheck.py` enforces this (it replaced the retired `MatchWorldModel` at the head of the list).
- `WorldEventLog` and `CareerManager` must stay **after** the four loaders, and `WorldEventLog` before `CareerManager`.
- `MatchWorldModel`, `MatchTelemetryLogger`, and `InputHelper` are no longer autoloads — they are archived.

### Career match-day flow

```
ui/manager_mode/ManagerModeRoot.gd::_on_continue_pressed()
  → CareerManager.simulate_next_fixture()
    → QuickSimEngine.simulate_match()
    → QuickSimEngine.apply_to_match_stats_tracker()
      → GameManager (score / FULL_TIME) + MatchStatsTracker (stat container)
  → CareerManager._apply_fixture_result()
    → league table, finances, morale, board confidence, player records, cups
```

The career UI never leaves `ManagerModeRoot` to play a match.

---

## 4. Non-obvious consequences an agent can trip over

Each of these looks like a bug or an inconsistency until you know the pivot happened.

### `MatchStatsTracker` is still an autoload but is now a pure container

`autoloads/MatchStatsTracker.gd` survived the pivot, but its **live in-match collector is gone**: the 30-physics-tick possession sampler that read `MatchWorldModel`, the 13 real-time event subscriptions (`ball_struck`, `foul_committed`, `offside_called`, `tackle_won`, …), the anti-snowball team-momentum accumulator, and the Moneyball-as-the-match-plays counters were all removed with the real-time layer. What remains is a flat stats container that `QuickSimEngine.apply_to_match_stats_tracker()` writes a simulated result into, and that `MatchStatsUI` reads back for the full-time review. `_possession_samples` is never written any more, so `possession_pct` reports its neutral `50.0` fallback.

Do not "restore" possession sampling or momentum accumulation. If the quick-sim path needs a stat, have `QuickSimEngine` assign it directly, exactly as the other fields are assigned.

### `GameManager` is a thin scoreboard shell

`autoloads/GameManager.gd` is now only a scoreboard boundary between the career world and a resolved fixture. The **entire** surviving surface is:

- `TEAM_A`, `TEAM_B`
- `enum MatchPhase { PREGAME, FULL_TIME }` (two states, not a phase machine)
- `current_phase`
- `score`
- `match_time`, `match_duration`, `half_duration_real_sec`, `simulated_match_time`
- `set_half_duration()`

Everything else — the per-frame clock, stoppage-time accumulation, kickoff/half-time/full-time transitions, set-piece placement state, the penalty-shootout controller, and their `GameEvents` broadcasts — was archived. **Do not reintroduce a phase machine, clock, or set-piece state there.** `QuickSimEngine` sets `current_phase = MatchPhase.FULL_TIME` when it publishes a result; `OptionsMenu` calls `set_half_duration()`.

### `GameEvents` carries exactly 11 signals

`autoloads/GameEvents.gd` is the only signal bus, and it now carries:

`formation_changed`, `lineup_changed`, `career_started`, `career_day_advanced`, `career_advance_halted`, `career_inbox_changed`, `career_match_ready`, `career_result_recorded`, `career_season_ended`, `career_manager_sacked`, `world_event_logged`.

The old match vocabulary (kickoff/set-piece flow, referee calls, contact/telemetry events, momentum and urgency broadcasts, game-crunch hooks) was removed with its emitters. Do not add match-engine signals back. When adding a career or presentation signal, append a **new** signal — never widen an existing signature, because under-declared listeners break silently.

### `shared/TeamManagementData.gd` and `shared/UtilityMath.gd` were deliberately KEPT

Both are **live files that must not be archived**:

- `shared/TeamManagementData.gd` is used in code by [`ui/manager_mode/TacticsPanel.gd`](../../ui/manager_mode/TacticsPanel.gd) (`TeamManagementData.from_team()` → `apply_to_team()`).
- `shared/UtilityMath.gd` remains a live math helper class (`class_name UtilityMath`), cited by `shared/README.md`, `docs/MATH_SOLVERS.md`, `tools/benchmark_math.py`, and `tools/fuzz_solvers.py`.

> [!NOTE]
> **Correcting a common misstatement:** `autoloads/MatchStatsTracker.gd` does **not** reference `UtilityMath` (its header lists only `PlayerRatingCalculator`, `PlayerData`, `DataLoader`, `GameManager`). Before repeating the claim that some live file uses `UtilityMath`, run `grep -rn UtilityMath --include=*.gd .` and exclude `legacy/`.

### `CareerManager.play_next_fixture()` / `record_user_match_result()` are orphaned

Both methods still exist in `autoloads/CareerManager.gd` (lines ~1111 and ~1147) but **are no longer called by any live UI** — they were the old `PitchScene` hand-off and its result callback. `CareerManager.simulate_next_fixture()` is the live path, called from `ManagerModeRoot.gd::_on_continue_pressed()`. Do not wire new UI to the orphaned methods, and do not delete them without confirming no tool or test references them.

### `ui/QuickSimModal.gd` / `ui/MatchStatsUI.gd` are functional but unreached

`ui/QuickSimModal.gd`/`.tscn` and `ui/MatchStatsUI.gd`/`.tscn` are kept, compile, and work — but nothing in the current UI flow instantiates them (the only references are `QuickSimModal`'s internal `preload` of `MatchStatsUI.tscn`). They are the natural presentation home for a richer quick-sim result view. If a task says "the quick-sim modal is broken," first confirm it is reachable at all.

### The tool split

- **Current quick-sim gate:** `tools/test_quick_sim.py` — the `QuickSimEngine` validation suite.
- **Retirement candidates (they describe the archived engine):** `tools/eval_simulation.py`, `tools/fuzz_formations.py`, `tools/fuzz_utility_scorer.py`, `tools/formation_ascii.py`, `tools/dump_match_frames.py`, `tools/spatial_grid_bench.py`.
- **Static gate:** `py -3 tools/verify_gate.py --fast` (10 linters) is the post-write gate.

### Linter and `gdcheck` behavior changed with the pivot

The skip lists in `gdcheck.py`, the `lint_*` linters, `tscn_linter.py`, `dump_api.py`, `generate_symbols.py`, and `dump_dep_graph.py` were all updated in the same commit as the archive — `legacy` is now in each one's skip set. `gdcheck.py`'s boot-order rule was also rewritten: it **requires `GameEvents` to be the first autoload** (the removed `MatchWorldModel` check is gone) while still requiring loaders before `WorldEventLog`/`CareerManager`. If you add an autoload, insert it without violating that order or `--fast` fails.

---

## 5. Tooling, verification, and where to look next

**Verify the archive before citing it:**

```bash
ls legacy/                                   # top-level archive groups
find legacy -name '*.gd' | wc -l             # 68
find legacy -type f | sort                   # full inventory
cat legacy/.gdignore                         # exclusion marker
```

**Verify a symbol is live, not archived:**

```bash
grep -rn "SymbolName" --include=*.gd . | grep -v legacy
```

**Verify current architecture claims against source:**

```bash
sed -n '/\[autoload\]/,/^\[/p' project.godot   # 9 autoloads, boot order
grep -n '^signal' autoloads/GameEvents.gd      # 11 signals
grep -n '^func simulate_next_fixture\|^func play_next_fixture\|^func record_user_match_result' autoloads/CareerManager.gd
py -3 tools/verify_gate.py --fast              # 10 linters, 0 errors
py -3 tools/test_quick_sim.py                  # quick-sim validation gate
```

**Canonical reading order after this page:**

1. [`docs/CORE_INVARIANTS.md`](../CORE_INVARIANTS.md) — the live 3-layer contracts, boot order, and choke points.
2. [`docs/agent-errata/README.md`](README.md) — topic index; bannered pages are historical.
3. `shared/QuickSimEngine.gd` — the match resolver; its header comment documents the statistical pipeline.
4. `autoloads/CareerManager.gd` — the career ladder and match-day pipeline.
5. This page's §2 archive inventory — but only when looking for pre-pivot math to port forward.
