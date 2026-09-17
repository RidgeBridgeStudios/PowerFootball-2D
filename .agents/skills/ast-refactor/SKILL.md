---
name: ast-refactor
description: Refactor GDScript components with localized AST edits while preserving strict static typing, layer choke points, and zero-allocation hot paths.
---

# AST Refactor & Invariant Preservation Skill

Guidelines and verification loop for rewriting or refactoring GDScript components in PowerFootball-2D.

## When to Use
- When modifying or refactoring GDScript classes across `autoloads/`, `shared/`, or `ui/`.
- When eliminating duplicate declarations, fixing typing warnings, or adhering to layer contracts.

## When NOT to Use
- For non-code files (JSON database records, markdown docs, project metadata).
- When making major architectural changes that require an approved implementation plan first.

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

## Step-by-Step Workflow

1. **Verify Tooling Prerequisite**:
   ```bash
   set -e
   test -f tools/verify_gate.py || exit 1
   ```

2. **Execute Fast Verification Gate**:
   After any file modification, run the 10 static linters:
   ```bash
   set -e
   py -3 tools/verify_gate.py --fast || exit 1
   ```

3. **Domain Verification**:
   If editing quick-sim or statistical solvers, run targeted tests:
   ```bash
   set -e
   py -3 tools/test_quick_sim.py || exit 1
   ```

4. **Validation Check**:
   - Confirm `tools/verify_gate.py --fast` passes with exactly 0 errors and 0 warnings before concluding changes.

