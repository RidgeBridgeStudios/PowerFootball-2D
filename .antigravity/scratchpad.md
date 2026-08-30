# Antigravity Scratchpad — Multi-Step Reasoning & Active State

## Current Subsystem Focus
- Developer Tooling & Context Architecture Optimization

## Active Invariants Checked
- **Engine Lock:** Godot 4.7-stable · GDScript 2.0 Strict Typing (`gdcheck.py` 0 errors required)
- **5-Layer Simulation Stack:** Physics (1) → Match AI (2) → Match Social (3) → Club World (4) → Narrative/UI (5)
- **Spatial Choke Point:** `MatchWorldModel.gd` for all spatial reads
- **Event Dispatch Choke Point:** `GameEvents.gd` for cross-layer signals
- **Player Brain Choke Point:** `PlayerBrain.gd` writes only to `movement_intent` and `wants_sprint`

## Step-by-Step Task Plan
1. [x] Generate Public API Surface Generator (`tools/dump_api.py` & `docs/API_SURFACE.md`)
2. [x] Expand Lifecycle Hooks (`.antigravity/hooks.json`, `.agents/hooks.json`, `tools/hook_gdcheck.py`)
3. [x] Implement Errata Memory Compactor & Archiver (`tools/compact_errata.py`, `.antigravity/scratchpad.md`)
4. [ ] Implement Simulation Layer Context Tool (`tools/layer_context.py`) & Slash Commands (`.antigravity/commands.json`, `.agents/commands.json`)
5. [ ] Update `.aiexclude`, `llms.txt`, and `AGENTS.md` with explicit XML boundaries and API surface links
6. [ ] Execute Complete Verification Gate
