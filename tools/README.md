# tools/ — Development Utilities

Static analysis and code generation tools.

## gdcheck.py

**Purpose:** Static GDScript 2.0 consistency checker. Runs in CI (no Godot binary needed).

**Catches:**
- Undeclared members (accessing fields that don't exist)
- Unknown types (referencing undefined classes)
- Unbalanced brackets
- Mixed indentation
- Godot 3 deprecated APIs (yield, KinematicBody2D, etc.)
- Malformed autoload declarations in project.godot

**Does NOT:**
- Type-check expressions (use Godot editor for that)
- Execute code
- Simulate runtime behavior

**Usage:**
```bash
python3 tools/gdcheck.py                    # Check all .gd files
python3 tools/gdcheck.py entities/player/   # Check directory
python3 tools/gdcheck.py entities/player/PlayerBrain.gd  # Check single file
```

**When to Run:**
- After every file write (integrated into feature development loop)
- Before committing
- In CI pipelines

**Verification Loop:**
```text
1. Edit file
2. python3 tools/gdcheck.py <file>
3. Fix errors
4. Repeat until: "0 errors"
5. Commit
```

---

## Future Tools

- **trait-compiler** (planned) — Bitmask trait constants generator
- **json-validator** (planned) — Validates squad JSON against docs/json-schema.md
- **formation-preview** (planned) — ASCII visualization of formation anchors
- **stats-reporter** (planned) — Match telemetry export
