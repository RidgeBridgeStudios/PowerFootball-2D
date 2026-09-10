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
| Reading full files (`cat autoloads/MatchWorldModel.gd`) | `py -3 tools/codebase_slice.py --file autoloads/MatchWorldModel.gd --method get_defensive_line_x` |
| Broad grepping (`grep -r "TackleState"`) | `py -3 -m graphify query "How does player transition to TackleState?"` |
| Modifying shared files without dependency checks | `py -3 tools/dump_dep_graph.py --blast-radius shared/PlayerData.gd` |
| Re-running long simulations for syntax checks | `py -3 tools/verify_gate.py --fast` (<150ms post-write gate) |

## ARCHITECTURAL CHOKE POINTS & LAYER BOUNDARIES

The simulation relies on an encapsulated 5-layer simulation stack. You are FORBIDDEN from bypassing established boundaries:

- DO NOT query the scene tree directly using `get_tree().get_nodes_in_group()` or absolute node paths (`$root/...`). All spatial state queries must route through `MatchWorldModel`:
  ```gdscript
  var defenders: Array[PlayerState] = MatchWorldModel.query_spatial_radius(pos, radius)
  ```

- DO NOT invoke methods directly across simulation modules. Route decoupled communications through `GameEvents`:
  ```gdscript
  GameEvents.player_state_changed.emit(player_id, new_state)
  ```

- KINEMATIC INTEGRITY: Never assign `CharacterBody2D.velocity` directly from tactical AI logic (Layers 3/4). `HeavyPlayerController` executes physical integration. `PlayerBrain` writes ONLY to `player.movement_intent` and `player.wants_sprint`. Direct velocity assignment is forbidden:
  ```gdscript
  KinematicController.request_velocity(vector)
  ```

- Autoload definitions: Never add `class_name` to an autoload script registered in `project.godot`.
- Collision layers: `CharacterBody2D` masks Layer 1 and Layer 2 ONLY. Never mask Layer 3 (Ball).

## VERIFICATION

Every edit will be validated using `py -3 tools/verify_gate.py --fast`. Files with untyped variables or layer violations will fail immediately.