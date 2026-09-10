# GEMINI.md - Google Antigravity & Gemini 3.8 Flash Protocol
# Engine: Godot 4.7-stable | GDScript 2.0 ONLY | Strict Static Typing

## Behavioral Constraints & Token Discipline
- NEVER overwrite or rewrite an entire file. Always use `edit_file` or line-bounded unified diffs.
- DO NOT read full files to orient. Target line ranges via `py -3 tools/codebase_slice.py` or query Graphify.
- NO PYTHONISMS: Use `null` (not None), `true/false` (lowercase), `.size()` (not len()), `func` (not def), `is` (not isinstance).
- Capturing `self` inside GDScript anonymous lambdas is forbidden. Assign `var host = self` first.
- Explicit static typing is mandatory on EVERY variable, function parameter, and return value.

## Graphify-First Tool Routing
| Anti-Pattern in PowerFootball-2D | Required Tooling Alternative |
| :--- | :--- |
| Reading full files (`cat autoloads/MatchWorldModel.gd`) | `py -3 tools/codebase_slice.py --file autoloads/MatchWorldModel.gd --method get_defensive_line_x` |
| Broad grepping (`grep -r "TackleState"`) | `py -3 -m graphify query "How does player transition to TackleState?"` |
| Modifying shared files without dependency checks | `py -3 tools/dump_dep_graph.py --blast-radius shared/PlayerData.gd` |
| Re-running long simulations for syntax checks | `py -3 tools/verify_gate.py --fast` (<150ms post-write gate) |

## Architectural Choke Points
- Spatial positions: Route strictly through `autoloads/MatchWorldModel.gd`. NEVER call `get_nodes_in_group()`.
- Inter-system events: Route strictly through `autoloads/GameEvents.gd` signal bus.
- Kinematics: `HeavyPlayerController` executes physical integration. `PlayerBrain` writes ONLY to `player.movement_intent` and `player.wants_sprint`. Direct velocity assignment is forbidden.
- Autoload definitions: Never add `class_name` to an autoload script registered in `project.godot`.
- Collision layers: `CharacterBody2D` masks Layer 1 and Layer 2 ONLY. Never mask Layer 3 (Ball).

## Verification Gate
Run after EVERY edit before concluding a turn:
`py -3 tools/verify_gate.py --fast` (All 10 linters must pass with 0 errors).
