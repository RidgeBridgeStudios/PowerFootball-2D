# GDScript 2.0 & Simulation Architectural Invariants

## CRITICAL SYNTAX RULES: ZERO-TOLERANCE ENFORCEMENT

1. NEVER emit Python-specific keywords: `None`, `def`, `len()`, `True`, `False`. Use exclusively GDScript literals: `null`, `func`, `.size()`, `true`, `false`.

2. ALL variable declarations MUST include explicit static typing:
   - Arrays: `var units: Array[Unit2D] = []`
   - Dictionaries: `var cache: Dictionary[String, Variant] = {}`
   - Inferred types: `var speed := 150.0`

3. FUNCTION SIGNATURES:
   - Must explicitly type all parameters and return values:
     `func process_kick(force: float, dir: Vector2) -> bool:`

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

- KINEMATIC INTEGRITY: Never assign `CharacterBody2D.velocity` directly from tactical AI logic (Layers 3/4). Invoke the validated movement interface:
  ```gdscript
  KinematicController.request_velocity(vector)
  ```

## VERIFICATION

Every edit will be validated using `python3 tools/verify_gate.py --fast`. Files with untyped variables or layer violations will fail immediately.