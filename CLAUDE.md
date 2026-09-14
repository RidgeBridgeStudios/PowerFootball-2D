# CLAUDE.md — Claude Code Agent Entry Point

**Canonical Policy Notice:**
`AGENTS.md` is the canonical shared repository policy and architectural guide for all AI agents.
Before implementing any feature or modifying code, review and adhere to **[AGENTS.md](AGENTS.md)**.

**Simulation stack (3 layers, manager-only):**
1. **Career World** — `autoloads/CareerManager.gd`, the four loaders (`DataLoader`, `ManagerLoader`, `RefereeLoader`, `StaffLoader`), `shared/career/*`, the `shared/*Data.gd` model, and `shared/CareerProgressionEngine.gd`.
2. **Quick-Sim Match** — `shared/QuickSimEngine.gd`, `shared/PlayerRatingCalculator.gd`, `shared/UtilityMath.gd`, `autoloads/MatchStatsTracker.gd`.
3. **Narrative & Presentation** — `autoloads/WorldEventLog.gd`, `entities/manager/PressOffice.gd`, `ui/manager_mode/*`, `ui/MainMenu.gd`, `ui/OptionsMenu.gd`, `ui/MatchStatsUI.gd`, `ui/QuickSimModal.gd`.

The real-time 22-player match layer (ball/player physics, per-frame AI, pitch scene, collision matrix, in-match HUD) is archived under `legacy/` and skipped by all tooling via `legacy/.gdignore`.

---

## 1. Primary Reading Order

1. **@AGENTS.md** — Canonical shared policy: engine lock, 3-layer simulation stack, architectural choke points, Graphify-first navigation protocol, change-impact tiers, and conditional documentation policy.
2. **@docs/GRAPHIFY_LIFECYCLE.md** — Canonical Graphify lifecycle, git hooks, update mechanics, and enforcement matrix.
3. **@POWERFOOTBALL_MASTER_VISION.md** — Historical pre-pivot design vision; read its `## Pivot Note` first. Retained as reference for future `QuickSimEngine` depth work, not as current implementation guidance.
4. **@docs/CORE_INVARIANTS.md** — Canonical engine lock, simulation stack, and critical file contracts.
5. **@docs/course_implementation_specification.md** — Course-derived reference specification (READ-ONLY): FSMs, formulas, gotchas.
6. **@ROADMAP.md** — Tactical `[ ]`/`[x]` feature checklist.
7. **@.claude/rules/** — Path-specific rulebooks automatically evaluated by Claude Code (career mode, context hygiene, GDScript antipatterns, Godot 4.7 core contracts, Graphify, reuse/complexity gating via [ponytail.md](.claude/rules/ponytail.md), and real-world football/IFAB grounding via [football-domain.md](.claude/rules/football-domain.md), backed by the local `football-expert` MCP server). The `ai-architect` and `soccer-physics` rulebooks are scoped to archived `legacy/` paths and are retained for reference only.

---

## 2. Graphify-First Navigation Protocol

This repository maintains an active Graphify knowledge graph (`graphify-out/graph.json`).

### Mandatory Pre-Exploration Query
- **Before Broad Source Exploration:** Whenever investigating functionality, architectural dependencies, or cross-layer data flows, query Graphify first:
  - CLI: `graphify query "<question>"`, `graphify path "<A>" "<B>"`, `graphify explain "<concept>"`.
  - MCP: `query_graph`, `shortest_path`, `get_node`, `get_neighbors`, `god_nodes`.
- **Prohibited Anti-Patterns:**
  - **NO Blind Ripgrep/Grep:** Do not run recursive grep across entire directories (`grep -r ...`) without a scoped target path.
  - **NO Directory Orientation Dumps:** Do not `cat` or read all files in a folder (`autoloads/*.gd`, `shared/*.gd`) to "orient" yourself.

### Mandatory Pre-Edit Blast Radius (Tier 2 & Tier 3)
- **Before Tier 2 (Cross-Module) and Tier 3 (Core Simulation) Edits:**
  - Run dependency blast radius:
    ```bash
    py -3 tools/dump_dep_graph.py --blast-radius <target_file>
    ```
  - Query Graphify neighbors/path (`get_neighbors` / `graphify explain "<target>"`) to map dependent modules and affected simulation layers prior to touching code.

> [!NOTE]
> **Scope Clarification:** Graphify is NOT queried for every conversational prompt. Conversational pleasantries, simple code formatting, or localized answers from existing context do not invoke Graphify. It is required for codebase exploration, cross-module relationship discovery, and pre-edit blast radius checks.

---

## 3. Non-Destructive Validation Checklist

Follow this 5-step checklist before concluding any turn or proposing changes:

1. **Format & Static Lint (Fast Gate):**
   ```bash
   python tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast
   ```
   All 10 linters must pass with 0 errors (`gdcheck`, `lint_invariants`, `lint_scope`, `lint_type_comparisons`, `lint_stringnames`, `lint_shadowing`, `lint_allocations`, `lint_xref`, `tscn_linter`, `verify_db`).
2. **Targeted Subsystem Test / Smoke Check:**
   Execute the relevant domain check based on touched files:
   - Kinematics/solvers (shared math): `py -3 tools/fuzz_solvers.py --iterations=10000`
   - Formation math (legacy reference solver): `py -3 tools/fuzz_formations.py --iterations=5000`
   - Quick-sim match simulation: `py -3 tools/eval_simulation.py --duration=10`
   - Determinism: `py -3 tools/replay_test.py`
3. **Diff Review & Invariant Audit:**
   Inspect `git diff` to confirm strict typing on all variables/signatures, zero hot-path allocations, no object-to-string comparisons, and no accidental changes.
4. **Graphify Refresh:**
   Synchronize graph topology via `graphify update .` or run the full pre-turn battery:
   ```bash
   python tools/verify_gate.py --full || py -3 tools/verify_gate.py --full
   ```
   (Step 17 runs `graphify update .` automatically).
5. **Concise Final Evidence:**
   Report exact verification results: linters passed, execution duration, and zero invariant violations.

---

## 4. Context Budget & Session Discipline (Claude Code)

| Range | State | Action |
|---|---|---|
| **0–50%** | **OPTIMAL** | Full architecture work. Multi-layer features. Reference files inline. |
| **50–70%** | **MONITOR** | Verify outputs against `docs/CORE_INVARIANTS.md` and `.claude/rules/`. Use targeted slices for spot checks. |
| **70–85%** | **DANGER** | Run `/compact` to compress prior messages. Do not start new multi-file features. |
| **85%+** | **CRITICAL** | Run `/compact` or `/clear` before next task. Major subsystem switches only. |

### Subsystem Switching
Switch major subsystems (career world ↔ quick-sim match ↔ narrative/presentation) with `/clear`.
`CLAUDE.md`, `AGENTS.md`, `docs/CORE_INVARIANTS.md`, `docs/GRAPHIFY_LIFECYCLE.md`, and `.claude/rules/` survive both compaction and clear.

---

## 5. Claude Code Hooks & Permissions

Configured in `.claude/settings.json`:
- **`PreToolUse` (Edit|Write):** Automatically blocks writes to sensitive files (`.env`, `.git/`, `addons/gut/`).
- **`PreToolUse` (Bash|Grep):** Executes `graphify hook-guard search` — nudges the agent to query Graphify instead of running broad ripgrep searches.
- **`PreToolUse` (Read|Glob):** Executes `graphify hook-guard read` — nudges the agent to use Graphify navigation before reading broad source files.
- **`Stop` Hook:** Runs GUT headless suite (if available) or static `tools/gdcheck.py` fallback to prevent stopping with broken syntax.
- **Git Hooks:** Detached background rebuilds via `.git/hooks/post-commit` and `.git/hooks/post-checkout` (bypass via `GRAPHIFY_SKIP_HOOK=1`). Union merge driver in `.git/config` for `graph.json`.

