# AGENTS_ERRATA.md

Escape hatch for non-Claude sessions. Rules discovered in-session that are not yet promoted to `.claude/rules/`.

## Discovered Rules

(To be populated by non-Claude sessions. Rules here are promoted to `.claude/rules/` at the start of the next Claude Code session.)

## Session State

(Record session context and handoff state here per template in AGENTS.md Section 5.)

## Session State: 2026-08-30 [Claude]
TASK: Implement phase-dependent dynamic formation anchors — off-ball anchors
shift with ball position and team phase (IN_POSSESSION / OUT_OF_POSSESSION /
TRANSITION) on top of the existing ball-proximity compactness lerp, rather
than holding a single static formation line all match.
FILES MODIFIED:
  - shared/FormationAnchorMath.gd (new) — pure static helper, TeamPhase enum,
    get_dynamic_anchor_position(role, phase, base_anchor, ball_pos,
    ball_weight, pitch_centre, pitch_size). Normalizes to -1..1 pitch-half
    space internally, returns world-space. Two tunable dicts:
    _PHASE_LINE_PUSH (per-phase line height) and _ROLE_PHASE_SENSITIVITY
    (per-role stretch scaling).
  - entities/player/PlayerBrain.gd — added TRANSITION_DURATION (1.5s) and
    _transition_timer (armed on every possession change, decayed per
    physics frame), _current_team_phase() helper, and wired the new anchor
    math into _find_open_space_target() (guarded on pitch_boundary != null,
    falls back to the old plain lerp otherwise).
GDCHECK: pass, 0 errors (68 scripts)
INVARIANTS CONSULTED: .claude/rules/ai-architect.md (spatial reads, frame
  jitter, zero-allocation-in-hot-paths — confirmed _find_open_space_target()
  runs on the 15-frame decision stagger, not every physics frame, so the
  extra Vector2 math is not a hot-path violation), .claude/rules/godot-47-core.md
  (strict typing).
NEXT: The per-branch role lerps inside _find_open_space_target() (attacker
  drop-off, midfielder lateral press, defender compression) were tuned
  against a static anchor and now compound with both the compactness lerp
  and the new phase push — worth a pass on the pitch to confirm no branch
  over-collapses toward the ball. No PlayerBrain.Role case needed for
  FormationAnchorMath beyond GOALKEEPER/DEFENDER/MIDFIELDER/ATTACKER; GK
  never reaches this call site (get_target_position() special-cases
  is_goalkeeper before role dispatch).
NEW RULES: None — no new prohibition discovered, existing invariants held.
Confirmed ROADMAP.md had no pre-existing checkbox for this feature (it's an
enhancement to an already-built Layer 2 Match AI system, not a net-new
gameplay feature), so a new line item was added and checked directly rather
than an existing one being flipped.

## Error Log

Format: [date] [model] | [error] | [correct behaviour]

(To be populated by sessions that encounter novel failure modes.)

[2026-08-30] [external-agent] | PlayerRoleConfig migration brief claimed a phantom constant ROLE_SPACE_ALPHA and a runtime crash from ROLE_SPACE_ALPHA.get(role, 0.35) | ROLE_SPACE_ALPHA is a real `const Dictionary` in PlayerBrain.gd (the pre-migration source of per-role roam alpha), so .get() on it is safe — no crash existed. The actual migration defect was a semantic inversion: anchor_weight (1.0 = rigid, 0.0 = free roam) was fed directly into _evaluate_off_ball_target()'s alpha, whose convention is the opposite (1.0 = roam, per ROLE_SPACE_ALPHA: DEF 0.20 / MID 0.40 / ATT 0.65). Correct consumer code: alpha = 1.0 - player.role_config.anchor_weight. Note the alpha block lives in _evaluate_off_ball_target(), NOT _find_open_space_target(). DEFENSIVE_LINE_DEPTH_WEIGHT (0.55) is a separate constant governing X-axis defensive_line_x blending — unrelated to anchor alpha.

[2026-08-30] [Claude] | Substitution task brief assumed `MatchWorldModel.refresh()` exists and that HUD.gd already stores TeamData refs | Neither is true. `MatchWorldModel` refreshes itself every `_physics_process` (priority -100) from `player_nodes[slot]`, which an in-place `apply_player_data()` swap never changes, so no explicit refresh call is needed or exists. HUD.gd holds no TeamData refs at all — resolve a sub banner's names via `DataLoader.get_player(team, squad_index)` (never null, bounds-safe) instead of inventing stored refs. AGENTS.md also has no roadmap-checkbox mirror table — its "Section 5" is Context Budget, not a ROADMAP.md mirror — so a completed ROADMAP.md checkbox has nothing to mirror there today.
