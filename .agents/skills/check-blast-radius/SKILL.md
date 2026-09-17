---
name: check-blast-radius
description: Analyze dependency topology and assess downstream blast radius before modifying core simulation classes or choke points.
---

# Blast Radius & Dependency Impact Skill

Assess dependency topology and downstream blast radius across simulation layers before modifying shared choke points.

## When to Use
- Before modifying core choke points (`autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `autoloads/GameEvents.gd`, `autoloads/MatchStatsTracker.gd`, `shared/QuickSimEngine.gd`, `shared/career/*`).
- When tracing cross-system blast radius across simulation layers (Career World, Quick-Sim Match, Narrative & Presentation).

## When NOT to Use
- For self-contained leaf files (e.g. standalone UI theme colors, isolated comments, docs).
- For localized text or formatting tweaks with no exported properties or signal contract changes.

## Step-by-Step Workflow

1. **Verify Tooling Prerequisite**:
   ```bash
   set -e
   py -3 tools/dump_dep_graph.py --help > /dev/null || exit 1
   ```

2. **Query Knowledge Graph Topology**:
   ```bash
   set -e
   py -3 -m graphify query "<SymbolName>" || exit 1
   ```

3. **Assess Blast Radius**: Run dependency inspection for the target file:
   ```bash
   set -e
   py -3 tools/dump_dep_graph.py --blast-radius autoloads/<FileName>.gd || exit 1
   ```

4. **Validation Check**:
   - Confirm the blast radius output lists all immediate importers and downstream dependents before editing.
   - If blast radius includes Tier 3 choke points, require a full pre-turn verification battery (`tools/verify_gate.py --full`).

5. **Document Downstream Impact**: In your plan artifact, document:
   - High-centrality dependent nodes
   - Affected simulation layers (Career World / Quick-Sim Match / Narrative & Presentation)
   - Secondary updates required to keep choke-point contracts intact

