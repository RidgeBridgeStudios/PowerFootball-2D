# AGENTS_ERRATA.md

Escape hatch for non-Claude sessions. Rules discovered in-session that are not yet promoted to `.claude/rules/`.

## Discovered Rules

(To be populated by non-Claude sessions. Rules here are promoted to `.claude/rules/` at the start of the next Claude Code session.)

## Session State

(Record session context and handoff state here per template in AGENTS.md Section 5.)

## Error Log

Format: [date] [model] | [error] | [correct behaviour]

(To be populated by sessions that encounter novel failure modes.)

[2026-08-30] [Claude] | Substitution task brief assumed `MatchWorldModel.refresh()` exists and that HUD.gd already stores TeamData refs | Neither is true. `MatchWorldModel` refreshes itself every `_physics_process` (priority -100) from `player_nodes[slot]`, which an in-place `apply_player_data()` swap never changes, so no explicit refresh call is needed or exists. HUD.gd holds no TeamData refs at all — resolve a sub banner's names via `DataLoader.get_player(team, squad_index)` (never null, bounds-safe) instead of inventing stored refs. AGENTS.md also has no roadmap-checkbox mirror table — its "Section 5" is Context Budget, not a ROADMAP.md mirror — so a completed ROADMAP.md checkbox has nothing to mirror there today.
