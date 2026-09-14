> [!NOTE]
> **Post-pivot scope note.** This Graphify lifecycle remains current. One item in the §3 validation checklist still names pre-pivot choke points (`PlayerBrain`, `MatchWorldModel`, the 6-layer collision matrix) as live contracts — those are archived under `legacy/` and no longer apply. See [agent-errata/architecture-pivot.md](agent-errata/architecture-pivot.md) and [CORE_INVARIANTS.md](CORE_INVARIANTS.md).

# Graphify Lifecycle & Agent Navigation Protocol — PowerFootball-2D

This document specifies the exact project-local Graphify lifecycle, agent navigation rules, validation checklist, and enforcement boundaries for both **Claude Code** and **Google Antigravity** within the PowerFootball-2D repository.

---

## 1. Project-Local Graphify Lifecycle

The repository uses Graphify (`graphifyy`) to maintain a persistent knowledge graph in `graphify-out/graph.json`, accompanied by `graphify-out/GRAPH_REPORT.md` and `graphify-out/graph.html`.

```
[Source Files] (.gd, .py, .tscn, .md)
       │
       ├──► 1. Initial Build ──────► graphify . (or graphify extract .)
       │                             Creates graphify-out/ (AST + Semantic + Clusters)
       │
       ├──► 2. Source Edits ───────► tools/verify_gate.py --full (Step 17)
       │                             Runs graphify update . (Incremental AST, 0 LLM cost)
       │
       ├──► 3. Git Operations ─────► .git/hooks/post-commit & post-checkout
       │                             Detached background rebuild (log: ~/.cache/graphify-rebuild.log)
       │
       └──► 4. Branch Merges ──────► .git/config [merge "graphify"]
                                     Union-merges graph.json without conflict markers
```

### 1.1. Initial Build
- **When:** Run once when initializing Graphify in a new clone or after purging `graphify-out/`.
- **Command (Interactive):**
  ```bash
  graphify .
  ```
- **Command (Headless / CI / Code-Only):**
  ```bash
  graphify extract . --code-only
  ```
  *(Or with deep semantic inference for docs: `graphify extract . --mode deep`)*
- **Lifecycle Actions:**
  1. **Detection:** Scans repository files and records catalog into `graphify-out/.graphify_detect.json`.
  2. **AST Extraction (Code):** Extracts AST entities and static references from GDScript and Python files into `graphify-out/.graphify_ast.json`.
  3. **Semantic Extraction (Docs):** Extracts semantic relationships from markdown specs and documentation if LLM backend is configured; code-only flows skip this.
  4. **Graph Build & Louvain Clustering:** Merges nodes/edges into `graphify-out/graph.json` and clusters into tactical/architectural communities.
  5. **Analysis & Reporting:** Computes god nodes, bridges, and surprising connections, exporting `graphify-out/GRAPH_REPORT.md` and browser-navigable `graphify-out/graph.html`.
  6. **Manifest & Pinning:** Saves `graphify-out/manifest.json`, pins the Python interpreter in `graphify-out/.graphify_python`, and records the scan root in `graphify-out/.graphify_root`.

### 1.2. Normal Update (Incremental Sync)
- **When:** After adding or modifying files, or to synchronize the graph before major navigation.
- **Command:**
  ```bash
  graphify update .
  ```
  *(Or using pinned python: `py -3 -m graphify update .` or `& (Get-Content graphify-out\.graphify_python) -m graphify update .`)*
- **Lifecycle Actions:**
  - Compares file timestamps and hashes against `graphify-out/manifest.json`.
  - Re-extracts only changed or added files using deterministic AST parsers.
  - **Zero LLM Token Cost:** Operates 100% locally with zero external API calls.
  - Updates topology, community assignments, and `GRAPH_REPORT.md`.
- **Flags:**
  - `--force` (or `GRAPHIFY_FORCE=1`): Overwrites `graph.json` even if node count shrinks (mandatory after refactors that delete obsolete scripts).
  - `--no-cluster`: Skips Louvain re-clustering when fast extraction is needed.

### 1.3. Update After Source Changes (Verification Battery)
- **When:** Automatically during the pre-turn completion verification battery.
- **Enforcement Mechanism:** Step 17 of `tools/verify_gate.py --full`:
  ```bash
  py -3 tools/verify_gate.py --full
  ```
  If `graphify-out/graph.json` exists, `verify_gate.py` invokes `graphify update .` using the discovered `graphify` binary or the interpreter pinned in `graphify-out/.graphify_python`.
- **Developer Live Watch (Optional):**
  Developers may run a file watcher during active coding sessions:
  ```bash
  graphify watch .
  ```
  Rebuilds the graph incrementally in the background whenever files are saved.

### 1.4. Update After Git Operations (Hooks & Merge Driver)
- **When:** Following `git commit`, `git checkout`, or branch switches.
- **Configured Git Hooks:** Installed in `.git/hooks/post-commit` and `.git/hooks/post-checkout` via `graphify hook install`.
- **Execution Profile:**
  - **Detached & Non-Blocking:** Hooks launch a detached background Python process and return exit code 0 immediately. Git operations are never delayed or frozen.
  - **Logging:** Background stdout and stderr are written to `~/.cache/graphify-rebuild.log`.
  - **Incremental:** Inspects `git diff --name-only` and re-extracts only modified files (`_rebuild_code`).
- **Automated Skip Conditions:**
  - Skips during interactive git state transitions: `rebase-merge/`, `rebase-apply/`, `MERGE_HEAD`, or `CHERRY_PICK_HEAD`.
  - Skips if the commit only touched files inside `graphify-out/`.
- **Documented Manual Bypass:**
  To commit or check out without triggering background rebuilds:
  ```bash
  GRAPHIFY_SKIP_HOOK=1 git commit -m "commit message"
  GRAPHIFY_SKIP_HOOK=1 git checkout <branch>
  ```
- **Git Merge Driver:**
  Registered in `.git/config` under `[merge "graphify"]`:
  ```ini
  [merge "graphify"]
      name = graphify graph.json union merge
      driver = "<py -3>" -m graphify merge-driver %O %A %B
  ```
  Performs automatic union merging of `graph.json` across branches, preventing merge conflict stalls on generated graph files.

---

## 2. Agent Navigation Protocol (Claude Code & Antigravity)

All agents working in the repository must adhere to the **Graphify-First Navigation Protocol**.

### 2.1. When Graphify MUST Be Queried
1. **Before Broad Source Exploration:**
   - Whenever locating functionality, understanding data flow across simulation layers, or finding architectural choke points.
   - Prohibited anti-patterns:
     - **NO blind ripgrep searches** (`grep -r ...`, `rg ...`) without a scoped target path.
     - **NO bulk directory orientation reads** (`cat autoloads/*.gd`, `view_file` on entire directories).
   - Approved queries:
     - CLI: `graphify query "<question>"`, `graphify path "<A>" "<B>"`, `graphify explain "<concept>"`.
     - MCP: `query_graph`, `shortest_path`, `get_node`, `get_neighbors`, `god_nodes`.
2. **Before Tier 2 (Cross-Module) and Tier 3 (Core Simulation) Changes:**
   - Mandatory blast-radius analysis before modifying shared resources, singletons, or choke points:
     ```bash
     py -3 tools/dump_dep_graph.py --blast-radius <target_file>
     ```
   - Must query Graphify neighbors or path:
     - Query `get_neighbors` on the target class/symbol or run `graphify explain "<target>"`.
     - Confirm all dependent nodes, signal receivers, and layer boundaries before making edits.

### 2.2. Important Scope Clarification
> [!NOTE]
> **Graphify is NOT queried for every conversational prompt.**
> Agents do not query Graphify for conversational pleasantries, formatting requests, simple explanations of already-loaded context, or isolated syntax adjustments. It is strictly required for codebase exploration, cross-module relationship discovery, and pre-edit blast radius checks.

---

## 3. Non-Destructive Validation Checklist

Before completing any code editing turn or proposing changes, agents must follow this sequential validation checklist:

```markdown
- [ ] 1. Static Lint & AST Validation (Fast Gate)
      Run `python tools/verify_gate.py --fast` (or `py -3 tools/verify_gate.py --fast`).
      Assert 0 errors across all 10 linters:
      - gdcheck (typing and syntax)
      - lint_invariants (choke points, layer separation, zero hot-path allocations)
      - lint_scope (duplicate declarations and dead code)
      - lint_type_comparisons (no Object vs String/StringName comparisons)
      - lint_stringnames (&"string_name" enforcement)
      - lint_shadowing (no member/autoload shadowing)
      - lint_allocations (distance_squared_to, zero transient RNG)
      - lint_xref (qualified member access and res:// paths)
      - tscn_linter (scene tree and collision masks)
      - verify_db (JSON schema and attribute constraints)

- [ ] 2. Targeted Subsystem Test / Smoke Check
      Execute the domain-specific test matching modified files:
      - Kinematics / Physics: `py -3 tools/fuzz_solvers.py --iterations=10000`
      - Tactical AI / Formations: `py -3 tools/fuzz_formations.py --iterations=5000`
      - Match Simulation Invariants: `py -3 tools/eval_simulation.py --duration=10`
      - Replay Determinism: `py -3 tools/replay_test.py`
      - Engine Compilation / GUT (if available): `godot --headless -s addons/gut/gut_cmdln.gd -gexit`

- [ ] 3. Diff Review & Contract Audit
      Inspect `git diff` against core invariants:
      - Strict explicit typing on every parameter, variable, and return type.
      - Kinematic choke points preserved: no direct player.velocity assignment in PlayerBrain.
      - Spatial choke point preserved: all queries route through MatchWorldModel.
      - Collision matrix preserved: CharacterBody2D masks Layer 1 and 2 only (never Layer 3).
      - Zero orphan code or unintended modifications.

- [ ] 4. Graphify Topology Refresh
      Synchronize graph topology:
      - Fast update: `graphify update .`
      - Or Full Battery: `py -3 tools/verify_gate.py --full` (automatically executes Step 17 graphify_update).

- [ ] 5. Concise Final Evidence
      Report exact execution metrics in the final summary:
      - Linters passed (10/10 fast gate, 17/17 full battery).
      - Execution duration (ms).
      - Zero warnings, zero invariant violations, and clean diff confirmation.
```

---

## 4. Enforcement Matrix: Enforced vs. Advisory vs. Manual

To eliminate ambiguity across human developers and automated agents, the table below defines the exact governance status of each workflow component:

| Component | Mechanism | Status | Description |
|---|---|---|---|
| **Edit File Guards** | `.claude/settings.json` (`PreToolUse`) | **Enforced** | Blocks agent writes to sensitive paths: `.env`, `.git/`, and `addons/gut/`. |
| **Grep / Search Nudge** | `.claude/settings.json` (`graphify hook-guard search`) | **Enforced** | Nudges Claude Code to use Graphify instead of broad grep/search when `graph.json` exists. |
| **Read / Glob Nudge** | `.claude/settings.json` (`graphify hook-guard read`) | **Enforced** | Nudges Claude Code to query Graphify before reading broad source files. |
| **Pre-Stop Gate** | `.claude/settings.json` (`Stop`) / `.agents/hooks.json` (`Stop`) | **Enforced** | Runs test/lint gates before session termination. |
| **Post-Commit Rebuild** | `.git/hooks/post-commit` | **Enforced** | Automatically triggers background incremental graph rebuild on commit. |
| **Post-Checkout Rebuild** | `.git/hooks/post-checkout` | **Enforced** | Automatically triggers background incremental graph rebuild on branch checkout. |
| **Merge Driver** | `.git/config` (`[merge "graphify"]`) | **Enforced** | Automatically union-merges `graph.json` during git branch merges. |
| **Full Battery Topology Sync** | `tools/verify_gate.py --full` (Step 17) | **Enforced** | Runs `graphify update .` as part of the 17-step full completion suite. |
| **Graphify-First Exploration** | `AGENTS.md`, `CLAUDE.md`, `.agents/rules/graphify.md` | **Advisory (Agent Instruction)** | Directs agents to query Graphify prior to reading code or exploring the codebase. |
| **Tier 2/3 Blast Radius** | `AGENTS.md`, `CLAUDE.md`, `.claude/rules/graphify.md` | **Advisory (Agent Instruction)** | Mandates `dump_dep_graph.py --blast-radius` and `get_neighbors` prior to editing core files. |
| **Validation Checklist** | `AGENTS.md`, `CLAUDE.md`, `docs/GRAPHIFY_LIFECYCLE.md` | **Advisory (Agent Instruction)** | Five-step validation procedure required before turn completion. |
| **Hook Installation (Fresh Clones)** | `graphify hook install` | **Manual Developer Action** | Git does not version `.git/hooks/`. Users must run this once per fresh clone. |
| **Live Rebuild Watcher** | `graphify watch .` | **Manual Developer Action** | Optional file watcher for live local development. |
| **Visual Exports** | `graphify export html / obsidian / wiki` | **Manual Developer Action** | Optional manual generation of specialized visualization artifacts. |

---

## 5. Repository Setup on Fresh Clones

Because Git does not track `.git/hooks/` across remotes, developers or CI environments setting up a fresh clone should run the following commands to install the repository hooks and merge drivers:

1. **Verify Graphify Installation:**
   ```bash
   graphify --help
   ```
2. **Install Git Hooks and Merge Driver:**
   ```bash
   graphify hook install
   ```
   *Verify with:* `graphify hook status` (should report post-commit: installed, post-checkout: installed, merge driver: registered).
3. **Verify Initial Graph:**
   If `graphify-out/` does not exist:
   ```bash
   graphify extract . --code-only
   ```
   If `graphify-out/` already exists:
   ```bash
   graphify update .
   ```
4. **Run Unified Verification Gate:**
   ```bash
   py -3 tools/verify_gate.py --fast
   ```
