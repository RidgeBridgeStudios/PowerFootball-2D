[← Back to SKILL.md](../SKILL.md)

# Graphify Commands & CLI Reference

## Step 0 - GitHub Repos and Multi-Path Merge

When processing a remote repository URL or merging multiple directory paths:
```bash
graphify extract https://github.com/user/repo --mode deep
```

## For --update and --cluster-only

Run incremental updates on modified files or re-run Leiden community clustering without re-extracting AST:
```bash
# Incremental update on modified files only
graphify update .

# Re-cluster existing graph without AST re-scan
graphify cluster graphify-out/graph.json
```

## For /graphify Query

Query the knowledge graph for concepts, symbols, or cross-module paths:
```bash
# Natural language question
graphify query "How does QuickSimEngine resolve a match?"

# Shortest path between two nodes
graphify path "CareerManager" "MatchStatsTracker"

# Detailed explanation of a single entity
graphify explain "QuickSimEngine"
```

> [!TIP]
> Present answers using targeted subgraphs rather than dumping entire dependency matrices.

## For /graphify Add and --watch

```bash
# Add a project to the global graph (~/.graphify/global-graph.json)
graphify global add graphify-out/graph.json --as my-project

# Watch directory for changes and continuously update
graphify watch .
```

## Step 6 - Generate Obsidian Vault and HTML

```bash
# Export interactive HTML graph
graphify export html --output graphify-out/graph.html

# Export Obsidian markdown vault
graphify export obsidian --dir graphify-out/obsidian
```

## Steps 6b-8 - Optional Exporters

```bash
# Export graph to SVG
graphify export svg --output graphify-out/graph.svg

# Export graph to GraphML
graphify export graphml --output graphify-out/graph.graphml

# Export wiki markdown articles
graphify export wiki --output graphify-out/wiki
```
