---
name: ast-refactor
description: Localized GDScript AST refactoring workflow preserving strict typing, choke points, and zero-allocation hot paths.
---

# AST Refactor & Invariant Preservation Skill

Guidelines and verification loop for rewriting or refactoring GDScript components in PowerFootball-2D.

## Strict Refactoring Rules

1. **Mandatory Type Annotations**: Every variable, function parameter, and function return type must be explicitly typed.
2. **Zero Allocation in Hot Paths**:
   - Never use `.new()`, array literals `[]`, or dictionary literals `{}` inside `score_pass()`, `calculate_intercept_point()`, `_physics_process()`, or `get_dynamic_anchor_position()`.
3. **Brain Mutation Choke Point**:
   - `PlayerBrain.gd` and state classes must write **only** to `player.movement_intent` and `player.wants_sprint`.
   - Never directly mutate `player.velocity`, `player.global_position`, or call `player.move_and_slide()`.
4. **Spatial Query Choke Point**:
   - Always query `MatchWorldModel.instance.player_positions[i]`. Never crawl the scene tree with `get_tree().get_nodes_in_group()`.
5. **Strict Scope & Type Comparison Discipline**:
   - Avoid duplicate variable declarations across function scopes.
   - Never compare object instances (e.g. `current_state`) directly to String/StringName literals.

## Verification Loop

After any file modification, run:
```bash
py -3 tools/verify_gate.py --fast
```
Do not proceed until the gate output reports 0 errors.
