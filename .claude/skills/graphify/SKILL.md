---
name: graphify
description: Build, query, and maintain a structural knowledge graph of the codebase with AST parsing when exploring complex multi-module dependencies.
allowed-tools: ["Bash"]
---

# /graphify

Build, query, and maintain a structural knowledge graph of the codebase.

## Safety & Integrity Notes

> [!NOTE]
> **Zero API Key Requirement**: graphify runs local AST code indexing with zero keys. Never ask the user for an API key and never block waiting for one.

> [!CAUTION]
> **Empty Extraction Guard**: An empty extraction must never overwrite an existing healthy `graph.json`, `GRAPH_REPORT.md`, or analysis sidecar.

> [!CAUTION]
> **Shrink-Guard Enforcement (#479)**: The engine returns `False` and writes nothing when a new graph is smaller than the existing `graph.json`. Never force-overwrite past the shrink-guard.

## When to Use
- When exploring unfamiliar codebase architectures, key choke points, or central modules.
- When performing pre-edit blast radius checks across multi-file dependencies.
- When querying caller/callee relationships, inheritance hierarchies, or shortest dependency paths.

## When NOT to Use
- For simple string or literal text searches (use grep or file searching).
- For reading small, already-identified leaf files.
- When editing localized UI styling or documentation that has no cross-system dependencies.

## Usage & Execution Commands

Verify dependencies and run graph extraction or queries:
```bash
set -euo pipefail
# Verify prerequisite
command -v graphify >/dev/null 2>&1 || { echo "graphify not found"; exit 1; }

# Incremental update on modified files
graphify update . || exit 1

# Query natural language questions
graphify query "<question>" || exit 1
```

| Command / Flag | Purpose | Reference Guide |
|---|---|---|
| `graphify extract .` | Full codebase extraction and graph build | [architecture.md](references/architecture.md#step-4---build-graph-cluster-analyze-generate-outputs) |
| `graphify update .` | Incremental AST update on modified files | [commands.md](references/commands.md#for---update-and---cluster-only) |
| `graphify query "<Q>"` | Natural language semantic graph query | [commands.md](references/commands.md#for-graphify-query) |
| `graphify path "<A>" "<B>"` | Find shortest dependency path between symbols | [commands.md](references/commands.md#for-graphify-query) |
| `graphify export html` | Export interactive D3 visualizer HTML | [commands.md](references/commands.md#step-6---generate-obsidian-vault-and-html) |

## What graphify is for

graphify turns a complex codebase into an explicit directed property graph, discovering architectural god nodes, clusters, and dependency blast radius with zero token cost.

## 10-Step High-Level Protocol

1. **Step 0 - Remote/Multi-path**: Clone or merge remote repositories if needed. See [commands.md](references/commands.md#step-0---github-repos-and-multi-path-merge).
2. **Step 1 - Ensure Installed**: Detect Python environment and pin interpreter. See [setup.md](references/setup.md#step-1---ensure-graphify-is-installed).
3. **Step 2 - Detect Files**: Scan project files and apply ignore filters. See [architecture.md](references/architecture.md#step-2---detect-files).
4. **Step 2.5 - Media Processing**: Transcribe media files if present. See [architecture.md](references/architecture.md#step-25---video-and-audio-processing).
5. **Step 3 - Extract Entities**: Run local AST parsing and optional semantic pass. See [architecture.md](references/architecture.md#step-3---extract-entities-and-relationships).
6. **Step 4 - Build & Cluster**: Run Leiden community clustering with shrink-guards. See [architecture.md](references/architecture.md#step-4---build-graph-cluster-analyze-generate-outputs).
7. **Step 4.5 - Health Check**: Validate edge-to-node density ratios. See [architecture.md](references/architecture.md#step-45---graph-health-check).
8. **Step 5 - Community Labels**: Assign human-readable labels to clusters. See [architecture.md](references/architecture.md#step-5---label-communities).
9. **Step 6 - Exporters**: Export interactive HTML, Obsidian vaults, or SVG diagrams. See [commands.md](references/commands.md#step-6---generate-obsidian-vault-and-html).
10. **Step 9 - Finalize**: Stamp manifest and update cost tracker. See [architecture.md](references/architecture.md#step-9---save-manifest-update-cost-tracker-clean-up-and-report).

## Honesty Rules

- **Zero Hallucination**: Never invent dependencies or claim a file has connections not present in `graph.json`.
- **Accurate Tool Reporting**: Always report AST-only extractions accurately; do not claim semantic LLM analysis ran when API keys are absent.
- **Fail Fast**: If `graphify` fails or the shrink-guard triggers, report the error directly rather than masking it.

## Reference Documentation Index

- [references/setup.md](references/setup.md): Installation, Python interpreter pinning, and troubleshooting.
- [references/commands.md](references/commands.md): Querying, incremental updates, and export commands.
- [references/architecture.md](references/architecture.md): Graph extraction pipeline, AST parsers, Leiden clustering, and health checks.
- [references/antigravity-integration.md](references/antigravity-integration.md): Agent hooks, cache files, and Antigravity tool routing.
