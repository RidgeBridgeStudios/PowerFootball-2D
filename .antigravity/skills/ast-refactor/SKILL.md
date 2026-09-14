---
name: ast-refactor
description: Localized GDScript AST refactoring workflow preserving strict typing, choke points, and zero-allocation hot paths.
---

# AST Refactor & Invariant Preservation Skill

Guidelines and verification loop for rewriting or refactoring GDScript components in PowerFootball-2D.

## Strict Refactoring Rules

1. **Mandatory Type Annotations**: Every variable, function parameter, and function return type must be explicitly typed.
2. **Allocation Discipline**:
   - The 60Hz per-entity loops were archived with the real-time match layer, so `score_pass()`, `_physics_process()`, and `get_dynamic_anchor_position()` are no longer live hot paths.
   - Never use `.new()`, array literals `[]`, or dictionary literals `{}` inside a per-player/per-event simulation loop (`shared/QuickSimEngine.gd`) or a shared solver (`shared/UtilityMath.gd`).
3. **Career/Match Choke Points**:
   - `autoloads/CareerManager.gd` owns the ONLY live `CareerSaveData`; nothing else mutates it.
   - A simulated match publishes once, through `QuickSimEngine.apply_to_match_stats_tracker()` — no other code may write a match outcome.
   - Route inter-system events through `autoloads/GameEvents.gd`, never a direct cross-module call.
4. **Strict Scope & Type Comparison Discipline**:
   - Avoid duplicate variable declarations across function scopes.
   - Never compare object instances or typed enums (e.g. `current_phase`) directly to String/StringName literals.

## Verification Loop

After any file modification, run:
```bash
py -3 tools/verify_gate.py --fast
```
Do not proceed until the gate output reports 0 errors. For quick-sim changes also run `py -3 tools/test_quick_sim.py`.
