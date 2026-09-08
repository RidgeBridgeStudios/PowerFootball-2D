##
## FormationAnchorMath
##
## Pure static utility — no instance needed. Takes a role's static formation
## anchor (set once by ManagerDirector/FormationLibrary) and nudges it toward
## the ball, biased by which team phase play is currently in, so the shape
## breathes with the game instead of holding a single rigid line all match.
##
## TeamPhase is a coarse, per-team read (not per-player): IN_POSSESSION when
## this team last touched the ball, OUT_OF_POSSESSION otherwise, and a brief
## TRANSITION window right after a turnover so the shape doesn't snap between
## the two the instant the ball changes hands. PlayerBrain owns deciding which
## phase applies (see PlayerBrain._current_team_phase()) — this class only
## consumes the result, it never reads the ball or match state itself.
##
## All math happens in normalized pitch-half space (-1..1 on each axis,
## origin at pitch centre) so the same tuning constants read the same near
## either touchline or goal line, then converts back to world space before
## returning — callers never see a normalized value.
##
## Depends on: PlayerBrain (for the Role enum only — no instance access).
## Exposes: TeamPhase, get_dynamic_anchor_position().
##

class_name FormationAnchorMath
extends RefCounted

enum TeamPhase { IN_POSSESSION, OUT_OF_POSSESSION, TRANSITION }

## How far (normalized pitch-half units along the attacking axis) each phase
## pushes a role's anchor up the pitch (+) or drops it back toward its own
## goal (-). Applied ON TOP of the existing ball-proximity lerp below, not
## instead of it. TUNE HERE for a higher/lower defensive line per phase.
## Calibration: OUT_OF_POSSESSION drop deepened slightly (-0.06 -> -0.08) for a
## tighter, more coordinated defensive squeeze without the line collapsing all
## the way to a back-five bunker.
const _PHASE_LINE_PUSH: Dictionary = {
	TeamPhase.IN_POSSESSION: 0.08,
	TeamPhase.OUT_OF_POSSESSION: -0.08,
	TeamPhase.TRANSITION: 0.0,
}

## Scales _PHASE_LINE_PUSH per role so the team stretches like an accordion
## instead of sliding as one rigid slab — defenders barely move, attackers
## move the most. TUNE HERE for how much each line compresses/expands.
const _ROLE_PHASE_SENSITIVITY: Dictionary = {
	PlayerBrain.Role.GOALKEEPER: 0.15,
	PlayerBrain.Role.OUTFIELD_DEFENDER: 0.60,
	PlayerBrain.Role.OUTFIELD_MIDFIELDER: 1.00,
	PlayerBrain.Role.OUTFIELD_ATTACKER: 1.30,
}

## Per-role ball_weight applied to the Y (lateral/width) axis only, decoupled
## from the caller-supplied [ball_weight] which still drives the X (line
## depth) axis unchanged. Without this split, a winger/fullback's lateral
## position collapses toward the ball's own Y by the same full weight as its
## depth does, so the whole back line and both flanks bunch up around
## whichever touchline the ball is on instead of holding the pitch's width.
## Lower values here keep a role wider; TUNE HERE for width discipline per role.
const _ROLE_Y_BALL_WEIGHT: Dictionary = {
	PlayerBrain.Role.GOALKEEPER: 0.15,
	PlayerBrain.Role.OUTFIELD_DEFENDER: 0.15,
	PlayerBrain.Role.OUTFIELD_MIDFIELDER: 0.20,
	PlayerBrain.Role.OUTFIELD_ATTACKER: 0.30,
}

## Macro urgency modulation (POWERFOOTBALL_MASTER_VISION.md / architecture
## plan "Dynamic Formation & Compactness Shifts") — applied uniformly across
## every role, on top of the existing per-role phase push above, so the whole
## line shifts together the same way MatchWorldModel.defensive_line_x is one
## shared depth rather than four independently-computed ones (see
## ai-architect.md). World-px shift at |urgency| == 1.0.
const URGENCY_MAX_DEF_LINE_SHIFT: float = 120.0
## How much a fully positive urgency (siege) compresses lateral spread (0.65x)
## and a fully negative urgency (preservation) expands it (1.35x).
const URGENCY_COMPACTNESS_SCALE: float = 0.35


## Returns a world-space anchor for [role] that has drifted from
## [base_anchor] toward [ball_pos] by [ball_weight] (team compactness — same
## meaning and value as PlayerBrain.formation_ball_weight), then pushed
## further up/back along the attacking axis according to [phase]. Ball-zone
## sensitivity comes from the lerp itself: a ball deep in one normalized zone
## pulls the anchor toward that same normalized zone. [pitch_centre] and
## [pitch_size] come straight from PitchBoundary.
##
## [urgency] is this player's team's cached MatchWorldModel.team_urgency
## reading ([-1, 1]) — positive urgency (chasing the game) shifts the whole
## line further upfield and compresses lateral spread for a compact press;
## negative urgency (protecting a lead) drops the line deep and widens the
## shape for safe possession recycling. Applied uniformly across every role,
## on top of the existing per-role phase push, so the back line moves as one
## band rather than four independently-shifted dots. Defaults to 0.0 (no
## shift) for any caller that doesn't have an urgency reading.
static func get_dynamic_anchor_position(
		role: PlayerBrain.Role,
		phase: TeamPhase,
		base_anchor: Vector2,
		ball_pos: Vector2,
		ball_weight: float,
		pitch_centre: Vector2,
		pitch_size: Vector2,
		attack_sign: float = 1.0,
		urgency: float = 0.0
) -> Vector2:
	var half: Vector2 = pitch_size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return base_anchor.lerp(ball_pos, ball_weight)

	# Normalize base anchor and ball position to -1..1 pitch-half units so
	# the shift constants above are resolution/pitch-size independent.
	var base_norm: Vector2 = (base_anchor - pitch_centre) / half
	var ball_norm: Vector2 = ((ball_pos - pitch_centre) / half).clamp(
		Vector2(-1.0, -1.0), Vector2(1.0, 1.0))

	# X (line depth) keeps the full caller-supplied ball_weight; Y (width)
	# uses the role's own, generally lower, weight — see _ROLE_Y_BALL_WEIGHT.
	var y_ball_weight: float = float(_ROLE_Y_BALL_WEIGHT.get(role, ball_weight))
	var pulled_norm: Vector2 = Vector2(
		lerpf(base_norm.x, ball_norm.x, ball_weight),
		lerpf(base_norm.y, ball_norm.y, y_ball_weight)
	)

	var push: float = float(_PHASE_LINE_PUSH.get(phase, 0.0)) \
		* float(_ROLE_PHASE_SENSITIVITY.get(role, 1.0)) * attack_sign
	var urgency_shift_norm: float = (urgency * URGENCY_MAX_DEF_LINE_SHIFT * attack_sign) / half.x
	pulled_norm.x = clampf(pulled_norm.x + push + urgency_shift_norm, -1.0, 1.0)

	var compactness_mult: float = 1.0 - URGENCY_COMPACTNESS_SCALE * urgency
	pulled_norm.y = clampf(pulled_norm.y * compactness_mult, -1.0, 1.0)

	return pitch_centre + pulled_norm * half
