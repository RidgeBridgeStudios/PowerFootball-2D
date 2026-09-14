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

The simulation is an encapsulated 3-layer stack — Career World -> Quick-Sim Match -> Narrative & Presentation. You are FORBIDDEN from bypassing established boundaries:

- DO NOT invoke methods directly across simulation modules. Route decoupled communications through `GameEvents`:
  ```gdscript
  GameEvents.career_result_recorded.emit(home_score, away_score)
  ```

- CAREER STATE OWNERSHIP: `CareerManager` owns the ONLY live `CareerSaveData`; nothing else mutates it. Match outcomes are published only through `QuickSimEngine.apply_to_match_stats_tracker()`.

- RETIRED — the spatial cache (`MatchWorldModel`), the per-frame player brains and kinematic controller, and their scene-tree-polling ban and `movement_intent` choke point were archived under `legacy/` with the real-time match layer. Those boundaries no longer apply; see `docs/agent-errata/architecture-pivot.md`.

## VERIFICATION

Every edit will be validated using `python3 tools/verify_gate.py --fast`. Files with untyped variables or layer violations will fail immediately.