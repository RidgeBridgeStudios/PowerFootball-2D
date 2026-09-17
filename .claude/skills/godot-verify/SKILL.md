---
name: godot-verify
description: Verify GDScript code quality, syntax, and test suites in Godot 4.7 with fallback to static AST checks when the engine is unavailable.
allowed-tools: ["Bash"]
---

# Godot Verification & Headless Testing Skill

Execute headless test verification for Godot 4.7 and validate GDScript syntax and typing.

## When to Use
- When validating GDScript syntax, typing, and GUT tests after modifying code.
- When verifying that autoload references and project paths resolve cleanly.

## When NOT to Use
- When only markdown documentation or non-code data files are changed.
- As a substitute for domain-specific statistical simulation validation (use `tools/test_quick_sim.py` instead).

## Step-by-Step Workflow

1. **Verify Tooling Prerequisite**:
   Check if the Godot binary and GUT test framework are available on the system PATH:
   ```bash
   set -e
   command -v godot >/dev/null 2>&1 || true
   ```

2. **Run Headless GUT Verification**:
   If Godot and GUT are present, execute headless test assertions:
   ```bash
   set -e
   godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit || exit 1
   ```
   - If compilation errors exist: extract file path, line number, and error message; resolve immediately.
   - If GUT test failures exist: inspect assertion failures, update implementation, and re-run.

3. **Fallback: Syntax-Only Check**:
   If `addons/gut/` is not installed, run syntax verification against root autoloads:
   ```bash
   set -e
   godot --headless --check-only --script res://autoloads/GameManager.gd || exit 1
   ```

4. **Container Fallback (No Engine on PATH)**:
   When running in an environment without a `godot` binary installed, run the static AST checker instead:
   ```bash
   set -e
   py -3 tools/gdcheck.py || exit 1
   ```

5. **Validation Check**:
   - Confirm that either GUT passes with 0 failures or `tools/gdcheck.py` passes with 0 errors before proceeding.

