[← Back to SKILL.md](../SKILL.md)

# Graph Construction & Architecture Pipeline

## Step 2 - Detect Files

Scans project files while respecting `.gitignore`, `.graphifyignore`, and directory excludes:
```bash
python3 -c "
from graphify.scan import scan_corpus
files = scan_corpus(\".\")
print(f\"Detected {len(files)} files\")
"
```

## Step 2.5 - Video and Audio Processing

When audio/video media files are present in the repository, transcode or transcribe them into companion markdown documents before semantic processing.

## Step 3 - Extract Entities and Relationships

> [!NOTE]
> **graphify needs no API key. Never ask the user for one, and never block on one.** Code indexing runs entirely via local AST parsing.
> When `GEMINI_API_KEY` or `GOOGLE_API_KEY` are unset, Step 3 uses the local AST-only pass and omits the semantic pass automatically.

### Part A - Structural Extraction for Code Files
Parses source files into Abstract Syntax Trees (ASTs), mapping functions, classes, calls, imports, and inheritance without LLM dependencies.

### Part B - Semantic Extraction
Dispatches content files (documentation, READMEs, specs) in parallel batches to extract high-level conceptual relationships.

### Part C - Merge AST and Semantic Extractions
Combines deterministic AST nodes and semantic conceptual nodes, deduplicating IDs and normalizing schema properties.

## Step 4 - Build Graph, Cluster, Analyze, Generate Outputs

Constructs network topology and executes Leiden community detection:

> [!CAUTION]
> **Empty Extraction Guard**: Guard BEFORE any write: an empty extraction must not clobber a healthy `graph.json`, `GRAPH_REPORT.md`, or analysis sidecar. Check immediately after build.

> [!CAUTION]
> **Shrink-Guard Enforcement (#479)**: `to_json` returns `False` (writing nothing) when the new graph is smaller than the existing `graph.json`. Only write `GRAPH_REPORT.md` and sidecars when the graph was actually written.

## Step 4.5 - Graph Health Check

> [!WARNING]
> **Graph Health Warning Gate**: An integrity check verifies that node count, edge density, and disconnected components remain within valid structural ratios:
> ```bash
> python3 -c "
> from graphify.health import check_graph_health
> issues = check_graph_health(\"graphify-out/graph.json\")
> if issues:
>     print(\"GRAPH HEALTH WARNING:\", issues)
> "
> ```

## Step 5 - Label Communities

Labels clusters using dominant node centralities, producing human-readable community names in `GRAPH_REPORT.md` and `graph.json`.

## Step 9 - Save Manifest, Update Cost Tracker, Clean Up, and Report

> [!IMPORTANT]
> **Manifest Stamping Safety (#2015)**: Only stamp semantic files that actually produced output so failed chunks re-queue on the next incremental update. Code files are always stamped because AST extraction is deterministic.
