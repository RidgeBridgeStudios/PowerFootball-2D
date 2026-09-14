---
name: check_blast_radius
description: Evaluates dependency topology and assesses blast radius prior to modifying core simulation classes.
---

# Blast Radius & Dependency Impact Skill

Before making changes to core choke points (e.g. `autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `autoloads/GameEvents.gd`, `autoloads/MatchStatsTracker.gd`, `shared/QuickSimEngine.gd`, `shared/career/*`):

1. **QUERY TOPOLOGY**: Execute the knowledge graph query via `run_command`:
   ```bash
   py -3 -m graphify query "<SymbolName>"
   ```

2. **ASSESS BLAST RADIUS**: Run the dependency inspection script:
   ```bash
   py -3 tools/dump_dep_graph.py --blast-radius autoloads/<FileName>.gd
   ```

3. **EVALUATE DOWNSTREAM IMPACT**: In your plan artifact, document:
   - High-centrality dependent nodes
   - Affected simulation layers (Career World / Quick-Sim Match / Narrative & Presentation)
   - Secondary updates required to keep choke-point contracts intact
