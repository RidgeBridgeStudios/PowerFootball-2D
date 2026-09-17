---
name: cross-system-feature
description: Design, implement, and validate gameplay features spanning multiple simulation layers in PowerFootball-2D when adding cross-subsystem functionality.
---

# Cross-System Gameplay Feature Workflow

This workflow governs any change touching multiple gameplay systems across the 3-layer simulation stack in PowerFootball-2D. It enforces architectural choke points, static typing, allocation discipline, and progressive verification.

Canonical Reference: See [AGENTS.md](AGENTS.md) and [docs/CORE_INVARIANTS.md](docs/CORE_INVARIANTS.md) for root architectural policies.

## When to Use
- When implementing or modifying gameplay features that span multiple simulation layers (Career World, Quick-Sim Match, Narrative & Presentation).
- When modifying shared data resources or adding new signal bus contracts to `autoloads/GameEvents.gd`.

## When NOT to Use
- For single-file styling, color palette tweaks, or UI label updates (Tier 1 Local changes).
- For isolated mathematical helper optimizations without layer or signal interactions.
- For simple documentation or formatting edits.

---

## The 10-Step Mandatory Protocol

Every cross-system feature implementation must proceed through these 10 distinct phases in strict order:

```
[1. Restate Outcome & Non-Goals]
               │
               ▼
[2. Classify Change-Impact Tier]
               │
               ▼
[3. Graphify Impact Query & Blast Radius]
               │
               ▼
[4. Targeted Context Reading]
               │
               ▼
[5. Written Implementation Plan]
               │
               ▼
[6. Small Staged Edits]
               │
               ▼
[7. Targeted Validation & Diff Review]
               │
               ▼
[8. Graphify Refresh]
               │
               ▼
[9. Conditional Documentation Updates]
               │
               ▼
[10. Final Verification Report]
```

---

### Step 1: Restate Requested Outcome and Non-Goals

Before inspecting files or writing code, formulate an explicit scope boundary:
- **Desired Outcome:** Exactly what gameplay mechanics, data models, or player behaviors are being introduced or modified.
- **Non-Goals:** Explicitly declare what is **out of scope** (e.g., refactoring existing state machines, altering ball drag constants, modifying unrelated UI menus, renaming signals).
- **Interfacing Layers:** Identify which of the 3 simulation layers ([AGENTS.md §9](AGENTS.md)) are touched:
  - *Layer 1 (Career World)*: CareerManager, DataLoader, ManagerLoader, RefereeLoader, StaffLoader, `shared/career/*`, the `shared/*Data.gd` models, CareerProgressionEngine.
  - *Layer 2 (Quick-Sim Match)*: QuickSimEngine, PlayerRatingCalculator, UtilityMath, MatchStatsTracker.
  - *Layer 3 (Narrative & Presentation)*: WorldEventLog, PressOffice, `ui/manager_mode/*`, MainMenu, OptionsMenu, MatchStatsUI, QuickSimModal.

---

### Step 2: Classify Change-Impact Tier

Classify the task into one of the three tiers defined in [AGENTS.md §3](AGENTS.md#3-change-impact-tiers):

| Tier | Scope & Affected Files | Pre-Edit Requirement | Post-Edit Verification Gate |
|---|---|---|---|
| **Tier 1: Local** | Leaf files: UI styling/labels (`ui/manager_mode/CareerTheme.gd`, `shared/career/CareerThemePalette.gd`), isolated math/formatting helpers without contract changes, comments/docs. | Local file inspection; confirm no exported variables or public signatures are altered. | Fast Gate:<br>`py -3 tools/verify_gate.py --fast`<br>(0 errors required) |
| **Tier 2: Cross-Module** | Multi-file interactions within or between adjacent simulation layers: signal signatures in `autoloads/GameEvents.gd`, shared resources (`shared/PlayerData.gd`, `shared/TeamData.gd`, `shared/career/*`), role configs (`shared/PlayerRoleConfig.gd`), exported properties across scenes. | Pre-edit blast radius calculation (`tools/dump_dep_graph.py --blast-radius <target>`) and Graphify neighbor inspection. | Fast Gate + Targeted Linters & Domain Tests:<br>`py -3 tools/verify_gate.py --fast`<br>+ domain-specific test. |
| **Tier 3: Core Simulation** | Architectural choke points (`autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `autoloads/GameManager.gd`, `autoloads/GameEvents.gd`, `autoloads/MatchStatsTracker.gd`, `shared/QuickSimEngine.gd`, `shared/career/*`, `shared/TeamManagementData.gd`), boot order, signal-bus contracts, career-state ownership, quick-sim publishing, career match-day flow. | Mandatory blast radius DAG, Graphify path trace, and explicit review of [docs/CORE_INVARIANTS.md](docs/CORE_INVARIANTS.md) and [docs/ANTI_PATTERNS.md](docs/ANTI_PATTERNS.md). | Full Pre-Turn Battery:<br>`py -3 tools/verify_gate.py --full`<br>(all 10 static linters + fuzzers + sim + replay test). |

---

### Step 3: Graphify Impact Query Before Reading Broad Source Files

Do NOT start by opening source files or running broad text searches. Query the structural knowledge graph first:

```bash
# Query the knowledge graph for concepts, nodes, and connections:
graphify query "<feature-or-symbol>"

# Trace shortest dependency paths between two interacting components:
graphify path "<SourceComponent>" "<TargetComponent>"

# Explain a concept or subsystem structure:
graphify explain "<SubsystemName>"

# For Tier 2 and Tier 3, calculate the exact dependency DAG blast radius:
py -3 tools/dump_dep_graph.py --blast-radius <target-file-path>
```

> [!CAUTION]
> **Strict Navigation Anti-Patterns:**
> - NEVER run recursive blind ripgrep (`grep -r ...`) across root folders without a scoped target path.
> - NEVER run bulk directory orientation dumps (`cat autoloads/*.gd` or viewing whole directories of code).

---

### Step 4: Reading Only Relevant Module READMEs, Hub Maps, and Targeted Files

Navigate with pinpoint accuracy using the localized documentation map:

1. **Subsystem READMEs (Read ONLY the affected subsystems):**
   - [autoloads/README.md](autoloads/README.md) — Boot order, singletons, global services.
   - [shared/README.md](shared/README.md) — Shared data resources, career models, managed tactical data, maths helpers.
   - [ui/README.md](ui/README.md) — Manager-mode presentation, menus, match-review UI.
   - [tools/README.md](tools/README.md) — Verification tools, linters, fuzzers, benchmarks.

2. **Architecture Hub Maps (for central choke points):**
   - [docs/architecture/hubs/career-manager.md](docs/architecture/hubs/career-manager.md)
   - The other hub pages (`match-world-model`, `player-brain`, `heavy-player-controller`, `pitch-scene`, `set-piece-coordinator`) describe the archived real-time layer — read them only as history.

3. **Topic-Scoped Errata (read only the relevant domain):**
   - [docs/agent-errata/architecture-pivot.md](docs/agent-errata/architecture-pivot.md) — START HERE: the manager-only pivot, `legacy/` layout, 3-layer stack.
   - [docs/agent-errata/scene-and-node-paths.md](docs/agent-errata/scene-and-node-paths.md)
   - [docs/agent-errata/data-and-persistence.md](docs/agent-errata/data-and-persistence.md)
   - Historical pages (archived real-time layer — do not apply): [player-ai.md](docs/agent-errata/player-ai.md), [match-state.md](docs/agent-errata/match-state.md), [physics-and-ball.md](docs/agent-errata/physics-and-ball.md), [set-pieces.md](docs/agent-errata/set-pieces.md), [telemetry-and-stats.md](docs/agent-errata/telemetry-and-stats.md), [ui-and-signals.md](docs/agent-errata/ui-and-signals.md).

4. **Targeted Code Inspection:**
   - Use `py -3 tools/codebase_slice.py` or targeted line ranges with `view_file` to read specific functions or classes.

---

### Step 5: Short Written Implementation Plan

Draft a concise plan explicitly documenting these five mandatory sections:

```markdown
### Plan: <Feature Name>

1. **Affected Modules & Files:**
   - Layer 1 (Career World): <files or "None">
   - Layer 2 (Quick-Sim Match): <files or "None">
   - Layer 3 (Narrative/Presentation): <files or "None">

2. **Contracts & Choke Points Touched:**
   - Singletons / Bus signals: <e.g. GameEvents.gd signal signatures>
   - Career state: <e.g. CareerManager save ownership>
   - Match publishing: <e.g. QuickSimEngine.apply_to_match_stats_tracker() only>

3. **Invariants to Preserve:**
   - Strict typing on every variable, parameter, and return type.
   - Zero heap allocations in per-player/per-event simulation loops.
   - Career state ownership: `CareerManager` owns the ONLY live `CareerSaveData`.
   - Quick-sim publishing: only `QuickSimEngine.apply_to_match_stats_tracker()` writes a match outcome.
   - Boot order: GameEvents first; the four loaders -> WorldEventLog -> CareerManager.
   - No object-to-string comparisons (`current_phase == "FULL_TIME"` is forbidden).

4. **Identified Risks & Failure Modes:**
   - Potential circular signal loops or race conditions.
   - Match-side vs league-index mix-ups (see `.claude/rules/career-mode.md`).
   - Stale `squad_index` identity after a transfer or squad removal.

5. **Test & Verification Plan:**
   - Fast gate: `py -3 tools/verify_gate.py --fast`
   - Targeted domain test: <e.g. tools/test_quick_sim.py>
   - Full gate (if Tier 3): `py -3 tools/verify_gate.py --full`
```

---

### Step 6: Small Staged Edits; No Unrelated Refactors

Execute changes in small, staged batches:
1. **Dependency Order:** Edit core contracts / shared data first, then simulation logic, then presentation/UI.
2. **Zero Opportunistic Refactoring:**
   - Modify ONLY lines necessary for the feature.
   - Do NOT rewrite existing code for personal aesthetic preferences.
   - Do NOT reformat unrelated functions or rename existing signals without contractual requirement.
3. **Preserve Integrity:** Keep all existing comments, docstrings, and type annotations intact.

---

### Step 7: Targeted Validation and Diff Review

Immediately validate changes using the repository's test battery:

1. **Fast Gate (Mandatory after every edit):**
   ```bash
   py -3 tools/verify_gate.py --fast
   ```
   *Requirement:* All 10 static linters (`gdcheck`, `lint_invariants`, `lint_scope`, `lint_type_comparisons`, `lint_stringnames`, `lint_shadowing`, `lint_allocations`, `lint_xref`, `tscn_linter`, `verify_db`) must report 0 errors.

2. **Targeted Domain Smoke Test (Run test matching the touched domain):**
   - **Shared math:** `py -3 tools/fuzz_solvers.py --iterations=10000` or `py -3 tools/benchmark_math.py`
   - **Quick-sim match resolution:** `py -3 tools/test_quick_sim.py`
   - **Determinism / Replay:** `py -3 tools/replay_test.py`
   - **Database / Schema:** `py -3 tools/verify_db.py` or `py -3 tools/validate_schemas.py`
   - **Scene Hierarchies:** `py -3 tools/tscn_linter.py`
   - *Archived real-time engine (retirement candidates, not current gates):* `tools/eval_simulation.py`, `tools/fuzz_formations.py`, `tools/formation_ascii.py`

3. **Diff Review:**
   Inspect `git diff` against strict invariants:
   - Are all variables and functions explicitly typed?
   - Are hot paths free of `.new()`, array `[]`, or dictionary `{}` allocations?
   - Are candidate distances calculated with `distance_squared_to()` rather than `distance_to()`?
   - Are there any forbidden object-to-string comparisons (`obj == "string"`)?
   - Does the change keep `CareerManager` the sole owner of `CareerSaveData` and route match publishing through `QuickSimEngine.apply_to_match_stats_tracker()`?

---

### Step 8: Graphify Refresh After Source Changes

When GDScript, scene, or contract files have been modified, update the structural knowledge graph:

```bash
graphify update .
```

*(Note: If running `py -3 tools/verify_gate.py --full`, Step 17 automatically runs `graphify update .`).*

---

### Step 9: Documentation Updates Only When Public Contracts or Architecture Changed

Apply the **Conditional Documentation-Update Policy** ([AGENTS.md §4](AGENTS.md#4-conditional-documentation-update-policy)):

| Trigger | Required Action |
|---|---|
| **Public API / Signatures Changed** | Regenerate API surface and symbol index:<br>`py -3 tools/dump_api.py` (updates `docs/API_SURFACE.md`)<br>`py -3 tools/generate_symbols.py` (updates `docs/SYMBOLS.json`) |
| **Dependencies / Autoloads Changed** | Regenerate dependency DAG:<br>`py -3 tools/dump_dep_graph.py` (updates `docs/DEPENDENCY_GRAPH.json`) |
| **Architectural Laws / Invariants Changed** | Update [docs/CORE_INVARIANTS.md](docs/CORE_INVARIANTS.md) and synchronized rules. |
| **New Bugs / Edge Cases Discovered** | Record structured entry in [AGENTS_ERRATA.md](AGENTS_ERRATA.md); run `py -3 tools/sync_rules.py`. |
| **Roadmap Milestones Achieved** | Mark completed checkbox `[x]` in [ROADMAP.md](ROADMAP.md). |
| **Internal Refactors / Bug Fixes** | **DO NOT regenerate or modify documentation** (avoids token waste and noisy diffs). |

---

### Step 10: Final Verification Report

Conclude with a structured report summarizing the work:

```markdown
### Cross-System Feature Delivery Report

- **Feature / Outcome:** <1-2 sentence description of delivered capability>
- **Impact Tier:** <Tier 1 / Tier 2 / Tier 3>
- **Files Modified:**
  - Layer X: `<path/to/file.gd>` (Description of change)
- **Verification Battery Results:**
  - `tools/verify_gate.py --fast`: PASS (0 errors, 10 linters)
  - Domain test (`<command>`): PASS (Details / duration)
  - Full gate (if Tier 3): PASS (10 linters + quick-sim/solver harnesses)
- **Invariants Verified:**
  - Strict typing: Confirmed across all new/modified declarations.
  - Zero hot-path allocations: Confirmed via `lint_allocations.py`.
  - Choke points respected: Confirmed via `lint_invariants.py`.
- **Knowledge Graph:** `graphify update .` completed.
- **Residual Risks & Follow-Ups:** <Identified edge cases or deferred roadmap items, or "None">
```

---

## Invocation in Antigravity

Users and agents can invoke this workflow in Antigravity in three ways:

1. **Direct Slash Command:**
   Type `/cross-system-feature` in the Antigravity chat prompt.

2. **Explicit Natural Language Prompt:**
   Ask Antigravity:
   > "Use the cross-system-feature skill to implement [feature description]."

3. **Autonomous Activation:**
   Antigravity progressively activates this skill whenever a prompt involves modifying multi-layer gameplay systems, cross-module signals, or core simulation choke points.
