---
trigger: always_on
description: Consult the graphify knowledge graph at graphify-out/ for codebase and architecture questions.
---

## graphify

This project maintains an active Graphify knowledge graph at `graphify-out/graph.json` and exposes MCP tools (`query_graph`, `shortest_path`, `get_node`, `get_neighbors`, `god_nodes`). Full lifecycle specification: `docs/GRAPHIFY_LIFECYCLE.md`.

### Strict Context & Token Optimization Rules
- **Before Broad Source Exploration:** NEVER run broad ripgrep searches (`grep -r ...`) or bulk directory reads (`cat autoloads/*.gd`) to explore architecture or trace data flows. ALWAYS use `graphify` first via MCP (`query_graph`, `shortest_path`, `get_node`) or CLI (`graphify query "<question>"`, `graphify path "<A>" "<B>"`, `graphify explain "<concept>"`).
- **Targeted Reading:** Open raw source files with `view_file` ONLY AFTER Graphify has pinpointed the specific class, function, or source location.
- **Mandatory Pre-Edit Blast Radius (Tier 2 & Tier 3):** Before modifying shared contracts (`autoloads/GameEvents.gd`, shared resources) or core simulation choke points (`MatchWorldModel.gd`, `HeavyPlayerController.gd`, `PlayerBrain.gd`, `Pseudo3DBall.gd`), agents MUST:
  1. Calculate static blast radius: `python tools/dump_dep_graph.py --blast-radius <target>`.
  2. Query Graphify neighbors/paths (`get_neighbors` or `graphify explain "<target>"`) to map dependent modules across simulation layers.
- **Scope Clarification:** Graphify is NOT queried for every conversational prompt. Conversational pleasantries, localized code edits, or questions answered by existing loaded context do not invoke Graphify.
- **Keep Graph Current:** After modifying GDScript or contract files, ensure `graphify update .` is run (or verified via Step 17 of `tools/verify_gate.py --full`) to keep the topology synchronized with zero LLM token cost.
- **Reflection Loop:** Record valuable navigation paths using `graphify save-result --outcome useful`.

### Non-Destructive Validation Checklist
1. **Lint/Format:** `python tools/verify_gate.py --fast` (all 10 static linters must pass with 0 errors).
2. **Targeted Smoke Test:** Domain-specific test (`eval_simulation.py`, `fuzz_solvers.py`, `fuzz_formations.py`, `replay_test.py`).
3. **Diff Review:** Inspect `git diff` against strict typing, zero allocations, no object-to-string comparisons.
4. **Graphify Refresh:** Synchronize topology via `graphify update .` or `tools/verify_gate.py --full`.
5. **Concise Evidence:** Report exact step execution, duration, and pass status.

### Enforcement & Git Hooks
- Background incremental rebuilds run automatically via `.git/hooks/post-commit` and `.git/hooks/post-checkout` (log: `~/.cache/graphify-rebuild.log`).
- To bypass git hook rebuilds when needed: set `GRAPHIFY_SKIP_HOOK=1`.
- Union merge driver registered in `.git/config` for `graph.json`.

