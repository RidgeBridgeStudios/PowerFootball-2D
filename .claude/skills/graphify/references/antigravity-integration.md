[← Back to SKILL.md](../SKILL.md)

# Antigravity & Agent Integration

## Hook Setup and CLAUDE.md Integration

Graphify integrates with AI agent workflows via Git hooks and configuration steering rules:
```bash
# Install post-commit / post-checkout hooks
graphify hook install

# Check hook status
graphify hook status
```

## Antigravity Project vs Global Skill Locations

- **Project-Level Skill**: `.agents/skills/graphify/SKILL.md` (or `.claude/skills/graphify/SKILL.md`)
- **Global Skill**: `~/.gemini/config/skills/graphify/SKILL.md`
- **Agent Steering Rules**: `.agents/rules/graphify.md`

## Cache Files & Metadata Inventory

Graphify maintains state in `graphify-out/`:
- `graphify-out/graph.json`: The complete knowledge graph topology (nodes, edges, communities).
- `graphify-out/GRAPH_REPORT.md`: Architectural overview and high-centrality god nodes.
- `graphify-out/manifest.json`: File hashes for change detection and incremental updating.
- `graphify-out/.graphify_python`: Path to the pinned Python interpreter.
- `graphify-out/.graphify_root`: Project scan root path.
- `graphify-out/.graphify_labels.json`: Curated community labels.

## Context-Mode Integration & Tool Routing

In Google Antigravity:
1. Never read raw `graph.json` directly into context.
2. Query AST nodes, callers, and blast radius by executing Python scripts via `ctx_execute`.
3. Verify freshness using `~/.gemini/antigravity/automation/graphify_freshness.sh`.
