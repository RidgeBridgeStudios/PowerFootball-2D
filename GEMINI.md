# GEMINI.md - Google Antigravity & Gemini 3.8 Flash Protocol
# Engine: Godot 4.7-stable | GDScript 2.0 ONLY | Strict Static Typing

## CRITICAL SYNTAX RULES: ZERO-TOLERANCE ENFORCEMENT

1. NEVER emit Python-specific keywords: `None`, `def`, `len()`, `True`, `False`. Use exclusively GDScript literals: `null`, `func`, `.size()`, `true`, `false`.
2. ALL variable declarations MUST include explicit static typing:
   - Arrays: `var units: Array[Unit2D] = []`
   - Dictionaries: `var cache: Dictionary[String, Variant] = {}`
   - Inferred types: `var speed := 150.0`
3. FUNCTION SIGNATURES:
   - Must explicitly type all parameters and return values:
     `func process_kick(force: float, dir: Vector2) -> bool:`
4. Capturing `self` inside GDScript anonymous lambdas is forbidden. Assign `var host = self` first.
5. NEVER overwrite or rewrite an entire file. Always use `edit_file` or line-bounded unified diffs.
6. DO NOT read full files to orient. Target line ranges via `py -3 tools/codebase_slice.py` or query Graphify.

## Graphify-First Tool Routing
| Anti-Pattern in PowerFootball-2D | Required Tooling Alternative |
| :--- | :--- |
| Reading full files (`cat autoloads/CareerManager.gd`) | `py -3 tools/codebase_slice.py --file autoloads/CareerManager.gd --method simulate_next_fixture` |
| Broad grepping (`grep -r "simulate_match"`) | `py -3 -m graphify query "How does QuickSimEngine resolve a fixture?"` |
| Modifying shared files without dependency checks | `py -3 tools/dump_dep_graph.py --blast-radius shared/PlayerData.gd` |
| Re-running long simulations for syntax checks | `py -3 tools/verify_gate.py --fast` (<150ms post-write gate) |

## ARCHITECTURAL CHOKE POINTS & LAYER BOUNDARIES

The simulation is a manager-only quick-sim stack with three layers: **Career World → Quick-Sim Match → Narrative & Presentation**. You are FORBIDDEN from bypassing established boundaries:

- **LAYER 1 — CAREER WORLD:** `autoloads/CareerManager.gd` owns the ONLY live `CareerSaveData`. The league (squads, staff, attributes) stays owned by the four loaders (`DataLoader`, `ManagerLoader`, `RefereeLoader`, `StaffLoader`) and is saved per slot via `DataLoader.save_league()`. `shared/career/*` holds the career data model and engines.

- **LAYER 2 — QUICK-SIM MATCH:** every fixture is resolved by `shared/QuickSimEngine.gd` — `calculate_probabilities()`, `simulate_match()`, `apply_to_match_stats_tracker()`. Never compute or fabricate a scoreline in UI code. The career match-day flow is `ui/manager_mode/ManagerModeRoot.gd::_on_continue_pressed()` → `CareerManager.simulate_next_fixture()` → `QuickSimEngine.simulate_match()` → `CareerManager._apply_fixture_result()`.

- **LAYER 3 — NARRATIVE & PRESENTATION:** `autoloads/WorldEventLog.gd`, `entities/manager/PressOffice.gd`, and `ui/` (`ui/manager_mode/*`, `ui/MainMenu.gd`, `ui/OptionsMenu.gd`, `ui/MatchStatsUI.gd`, `ui/QuickSimModal.gd`) react to simulation state; they never mutate it directly.

- DO NOT invoke methods directly across simulation layers. Route decoupled communications through `GameEvents`:
  ```gdscript
  GameEvents.career_match_ready.emit(home_team_index, away_team_index)
  ```

- **AUTOLOAD ORDER:** exactly nine autoloads, registered in this order — `GameEvents` → `GameManager` → `MatchStatsTracker` → `DataLoader` → `RefereeLoader` → `ManagerLoader` → `StaffLoader` → `WorldEventLog` → `CareerManager`. `GameEvents` must stay first; the four loaders must stay before `WorldEventLog`, which must stay before `CareerManager`. Enforced by `tools/gdcheck.py`.

- Autoload definitions: Never add `class_name` to an autoload script registered in `project.godot`.

- **LEGACY ARCHIVE:** the real-time 22-player match layer (ball/player physics, per-frame AI, pitch scene, collision matrix, in-match HUD) now lives under `legacy/` behind `legacy/.gdignore`. Treat it as read-only reference for future `QuickSimEngine` depth work; do not re-wire it into the live stack.

## VERIFICATION

Every edit will be validated using `py -3 tools/verify_gate.py --fast`. Files with untyped variables or layer violations will fail immediately.