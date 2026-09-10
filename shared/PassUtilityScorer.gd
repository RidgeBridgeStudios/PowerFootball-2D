##
## PassUtilityScorer
##
## Pure static scoring for pass-target candidates — no instance state, no
## lifecycle, no spatial queries of its own. PlayerBrain._find_best_pass_target()
## already has every input this needs from its own roster walk
## (MatchWorldModel positions, the attack-axis dot, HeavyPlayerController.
## get_facing_dot()); this class only turns those numbers into one comparable
## score, in one place, so the four scoring dimensions and their weights can be
## read and retuned without hunting through the decision tree.
##
## Scoring dimensions (each normalized to 0.0-1.0 before weighting):
##   distance      — quadratic falloff around PREFERRED_DISTANCE; too short
##                    wastes the pass, too long is a low-percentage ball.
##   angle         — passer_facing_dot remapped from [-1,1] to [0,1]: how
##                    natural the pass is given the passer's current heading,
##                    not how good it is tactically.
##   pressure      — receiver_open_dist remapped so a marked receiver scores
##                    low and a free one scores high (MatchWorldModel.
##                    nearest_opponent_dist_to() supplies the distance).
##   advancement   — forward_dot remapped from [-1,1] to [0,1] (how much the
##                    pass's direction progresses toward the opponent goal),
##                    blended with UtilityMath.get_xt_value() for the
##                    receiver's actual pitch zone when a caller supplies one
##                    (xt_value param) — direction alone rewards any forward
##                    ball equally, xT additionally rewards landing in a
##                    genuinely dangerous zone (e.g. central final third)
##                    over a forward-but-low-value one (e.g. a sideways-deep
##                    touchline ball that still has forward_dot > 0).
##
## The four WEIGHT_* constants below are the single place to retune passing
## behaviour project-wide. They do not need to sum to 1.0 — candidates are only
## ever compared against each other and a fixed minimum-quality threshold, never
## against an absolute scale.
##
## Passer pressure reshapes the weights at score time rather than being a fifth
## dimension: a passer under pressure should favour the safe, open outlet over
## the ambitious forward ball, so weight shifts from advancement to receiver
## pressure as passer_pressure rises. See PRESSURE_SAFETY_SHIFT.
##
## score_pass() is the hot-path entry point — returns a bare float, allocates
## nothing, and is safe to call once per candidate on every decision tick
## (ai-architect.md's zero-allocation rule for evaluate_tactical_action's call
## tree). score_pass_breakdown() does the same math but returns a
## PassScoreBreakdown object for debugging — call it only from debug-gated
## code, never unconditionally in the per-candidate loop.
##
## Depends on: UtilityMath (quadratic_decay for the distance curve; the
## caller, not this file, calls get_xt_value() and passes the result in as
## xt_value — this class still performs no spatial lookups of its own).
## Exposes: score_pass(), score_pass_breakdown(), PassScoreBreakdown
##

class_name PassUtilityScorer
extends RefCounted

## --- Tunable weights — edit these to retune passing behaviour. ---
## Calibration (line-breaking pass): the previous split (pressure 0.38 /
## advancement 0.24, safety shift 0.75) made receiver openness worth more than
## forward progress at every pressure reading, so the highest-scoring ball on
## the pitch was almost always the square one to an unmarked teammate behind
## the play. That is the arithmetic behind the sterile centre-back/full-back
## recycling loop: nothing was wrong with the decision tree, the weights just
## priced safety above progression. Advancement now outweighs receiver
## openness, and a new packing dimension pays specifically for the defenders a
## pass actually eliminates rather than for forward direction alone.
const WEIGHT_DISTANCE: float = 0.20
const WEIGHT_ANGLE: float = 0.18
const WEIGHT_PRESSURE: float = 0.25
const WEIGHT_ADVANCEMENT: float = 0.38
## Value of each opponent the pass takes out of the game between the carrier
## and the receiver along the attacking axis. Distinct from advancement: a 40px
## forward ball that splits two midfielders progresses far less ground than a
## 200px one down the untenanted flank, but is worth much more.
##
## Unlike the other four dimensions this one is deliberately NOT normalised to
## 0-1 before weighting — it is a price per defender eliminated, so a ball that
## takes out three is worth three times one. That makes a genuine line-breaking
## pass able to outscore a comfortable sideways one outright rather than merely
## edge it, which is the whole point of the dimension: at a normalised 0.18
## ceiling, packing was worth less than the distance term and the sterile
## recycling loop survived the reweighting intact.
## The caller supplies the raw count (it owns the spatial read).
const WEIGHT_PACKING: float = 0.18
## Bypassed-defender count at which the packing term stops growing. Four is the
## practical ceiling for a single pass — beyond a back four there is nothing
## further to eliminate — and it caps the term at 0.72 so one speculative ball
## through a congested midfield can never become an unanswerable score.
const PACKING_SATURATION: float = 4.0

## Passing distance (px) this scorer treats as ideal — short enough to be
## reliably on target, long enough to actually progress play. Distance utility
## falls off symmetrically on both sides of this value, reaching 0 at 0px and
## at 2x this value.
const PREFERRED_DISTANCE: float = 220.0
## Passes longer than this are never worth attempting regardless of how open
## or well-angled the receiver is — distance utility floors to 0.0.
const MAX_USEFUL_DISTANCE: float = 520.0

## Receiver is treated as fully open at or beyond this distance from the
## nearest opponent; pressure utility ramps linearly down to 0.0 as that
## opponent closes to 0px.
const RECEIVER_OPEN_RADIUS: float = 160.0

## How strongly the passer's own pressure reading reshapes the weights at
## score time. 0.0 leaves weights untouched; 1.0 fully swaps
## WEIGHT_ADVANCEMENT's share over onto WEIGHT_PRESSURE. The shift is a
## same-amount transfer (see _weighted_total()), so WEIGHT_PRESSURE +
## WEIGHT_ADVANCEMENT stays constant regardless of pressure — only the split
## between "safe" and "ambitious" moves.
## Calibration: cut from 0.75 to 0.42. At 0.75 a passer reading even moderate
## pressure had almost the whole advancement weight transferred onto receiver
## openness, so the safe outlet won under exactly the conditions where a
## line-breaking ball is most valuable — a pressed team that plays out of the
## press. 0.42 still bends the choice toward safety under a genuine press
## without erasing forward ambition the moment an opponent gets close.
const PRESSURE_SAFETY_SHIFT: float = 0.42

## --- Directional bias constants (applied by the caller, named here) ----------
## Dot of (ball -> receiver) with the attacking axis below which a candidate
## counts as a genuinely negative ball rather than a square one.
const BACKWARD_PASS_DOT: float = -0.2
## Flat penalty applied to a negative candidate when the carrier is in the
## middle or attacking third and is NOT under real tackle pressure. Under
## pressure the safety valve stays open — this only removes the unforced
## backward recycle.
const BACKWARD_PASS_PENALTY: float = 0.35
## The same penalty while the passing team is trailing in the closing stage:
## a side chasing the game does not pass backwards for the sake of it.
const BACKWARD_PASS_PENALTY_TRAILING: float = 0.60
## Nearest-defender distance (px) above which the carrier counts as unpressured
## for the purposes of BACKWARD_PASS_PENALTY.
const UNPRESSURED_DEFENDER_DIST: float = 110.0
## Attack-relative X (px, own goal negative) beyond which the backward-damping
## rule applies at all — i.e. from the middle third forward.
const BACKWARD_DAMP_MIN_AXIS_X: float = -100.0
## Occlusion fraction every forward lane must exceed before two centre-backs
## are permitted to recycle between themselves.
const CB_RECYCLE_MIN_OCCLUSION: float = 0.85
## Bonus for a ball played into the space ahead of a sprinting runner rather
## than into their feet.
const LEAD_PASS_BONUS: float = 0.28
## Receiver velocity . attacking axis above which a candidate counts as
## genuinely running onto a through-ball.
const LEAD_PASS_MIN_FORWARD_DOT: float = 0.5
## Multiplier on the advancement weight while trailing in the closing stage.
const TRAILING_PROGRESS_MULTIPLIER: float = 1.5


## Debug-inspectable breakdown of one candidate's score. Only ever built by
## score_pass_breakdown() for debug printing/drawing — the scored hot loop
## itself uses score_pass()'s bare float and allocates nothing.
class PassScoreBreakdown:
	var distance_utility: float = 0.0
	var angle_utility: float = 0.0
	var pressure_utility: float = 0.0
	var advancement_utility: float = 0.0
	## Bypassed-defender count, capped at PACKING_SATURATION — a raw count, not
	## a 0-1 utility like the four dimensions above it. See WEIGHT_PACKING.
	var packing_utility: float = 0.0
	var total: float = 0.0
	## The candidate this breakdown belongs to. Set by the caller for debug
	## printing; never read by the scoring math itself.
	var receiver: HeavyPlayerController = null


## Scores one pass candidate as a bare float. Every input is a value the
## caller already has in hand from its own spatial reads — this function
## performs no lookups of its own and allocates nothing, so it is safe to call
## once per candidate on every decision tick.
##
## distance: px, ball position -> candidate position.
## passer_facing_dot: HeavyPlayerController.get_facing_dot(candidate_pos) read
##   on the passer — how aligned the pass is with the body's current heading.
## forward_dot: dot of the ball->candidate direction with the team's attacking
##   axis — how much the pass advances play toward the opponent goal.
## receiver_open_dist: MatchWorldModel.nearest_opponent_dist_to(candidate_pos,
##   team) — how tightly the receiver is marked.
## passer_pressure: 0.0-1.0 pressure reading on the PASSER (PlayerBrain.
##   UtilityContext.pressure) — shifts weight toward the safe/open dimension
##   and away from forward ambition as it rises.
## xt_value: UtilityMath.get_xt_value() for the receiver's pitch zone, or
##   -1.0 (default) to skip it — advancement_utility then falls back to pure
##   forward_dot, unchanged from before this parameter existed.
## bypassed_defenders: raw count of opponents the pass eliminates between the
##   carrier and the receiver along the attacking axis (MatchWorldModel.
##   count_bypassed_opponents()). Normalised here against PACKING_SATURATION.
## directional_bias: signed adjustment the caller has already resolved from
##   match context — negative for an unforced backward ball
##   (BACKWARD_PASS_PENALTY / _TRAILING), positive for a ball led into the
##   space ahead of a sprinting runner (LEAD_PASS_BONUS). Kept as one resolved
##   scalar rather than two flags so this class stays free of match-state
##   knowledge, consistent with its no-lookups contract.
static func score_pass(
		distance: float,
		passer_facing_dot: float,
		forward_dot: float,
		receiver_open_dist: float,
		passer_pressure: float,
		w_dist: float = WEIGHT_DISTANCE,
		w_angle: float = WEIGHT_ANGLE,
		w_press: float = WEIGHT_PRESSURE,
		w_adv: float = WEIGHT_ADVANCEMENT,
		xt_value: float = -1.0,
		bypassed_defenders: float = 0.0,
		directional_bias: float = 0.0
) -> float:
	if distance > MAX_USEFUL_DISTANCE:
		return 0.0

	var distance_utility: float
	if distance <= PREFERRED_DISTANCE:
		distance_utility = UtilityMath.quadratic_decay(PREFERRED_DISTANCE - distance, PREFERRED_DISTANCE)
	else:
		var max_tail: float = MAX_USEFUL_DISTANCE - PREFERRED_DISTANCE
		distance_utility = UtilityMath.quadratic_decay(distance - PREFERRED_DISTANCE, max_tail)

	var angle_utility: float = clampf((passer_facing_dot + 1.0) * 0.5, 0.0, 1.0)
	var pressure_utility: float = clampf(receiver_open_dist / RECEIVER_OPEN_RADIUS, 0.0, 1.0)
	var direction_advancement: float = clampf((forward_dot + 1.0) * 0.5, 0.0, 1.0)
	var advancement_utility: float = direction_advancement if xt_value < 0.0 \
		else clampf((direction_advancement + xt_value) * 0.5, 0.0, 1.0)
	var packing_utility: float = clampf(bypassed_defenders, 0.0, PACKING_SATURATION)

	return _weighted_total(
		distance_utility, angle_utility, pressure_utility, advancement_utility,
		packing_utility, passer_pressure, w_dist, w_angle, w_press, w_adv,
		directional_bias)


## Same math as score_pass(), but returns the full per-dimension breakdown for
## debug printing/drawing. Allocates a PassScoreBreakdown — call only from
## debug-gated code (e.g. PlayerBrain.debug_log_pass_scores), never
## unconditionally inside the per-candidate scoring loop.
static func score_pass_breakdown(
		distance: float,
		passer_facing_dot: float,
		forward_dot: float,
		receiver_open_dist: float,
		passer_pressure: float,
		receiver: HeavyPlayerController = null,
		w_dist: float = WEIGHT_DISTANCE,
		w_angle: float = WEIGHT_ANGLE,
		w_press: float = WEIGHT_PRESSURE,
		w_adv: float = WEIGHT_ADVANCEMENT,
		xt_value: float = -1.0,
		bypassed_defenders: float = 0.0,
		directional_bias: float = 0.0
) -> PassScoreBreakdown:
	var result := PassScoreBreakdown.new()
	result.receiver = receiver
	if distance > MAX_USEFUL_DISTANCE:
		return result

	if distance <= PREFERRED_DISTANCE:
		result.distance_utility = UtilityMath.quadratic_decay(PREFERRED_DISTANCE - distance, PREFERRED_DISTANCE)
	else:
		var max_tail: float = MAX_USEFUL_DISTANCE - PREFERRED_DISTANCE
		result.distance_utility = UtilityMath.quadratic_decay(distance - PREFERRED_DISTANCE, max_tail)

	result.angle_utility = clampf((passer_facing_dot + 1.0) * 0.5, 0.0, 1.0)
	result.pressure_utility = clampf(receiver_open_dist / RECEIVER_OPEN_RADIUS, 0.0, 1.0)
	var direction_advancement: float = clampf((forward_dot + 1.0) * 0.5, 0.0, 1.0)
	result.advancement_utility = direction_advancement if xt_value < 0.0 \
		else clampf((direction_advancement + xt_value) * 0.5, 0.0, 1.0)
	result.packing_utility = clampf(bypassed_defenders, 0.0, PACKING_SATURATION)
	result.total = _weighted_total(
		result.distance_utility, result.angle_utility,
		result.pressure_utility, result.advancement_utility,
		result.packing_utility, passer_pressure,
		w_dist, w_angle, w_press, w_adv, directional_bias)
	return result


## Shared weighting step for score_pass() and score_pass_breakdown() — takes
## the four already-normalized utilities and passer_pressure and combines them
## into one total. See PRESSURE_SAFETY_SHIFT for the weight-shift rationale.
static func _weighted_total(
		distance_utility: float,
		angle_utility: float,
		pressure_utility: float,
		advancement_utility: float,
		packing_utility: float,
		passer_pressure: float,
		w_dist: float = WEIGHT_DISTANCE,
		w_angle: float = WEIGHT_ANGLE,
		w_press: float = WEIGHT_PRESSURE,
		w_adv: float = WEIGHT_ADVANCEMENT,
		directional_bias: float = 0.0
) -> float:
	var safety_shift: float = clampf(passer_pressure, 0.0, 1.0) * PRESSURE_SAFETY_SHIFT
	var effective_w_pressure: float = w_press + w_adv * safety_shift
	var effective_w_advancement: float = w_adv * (1.0 - safety_shift)

	# The packing term deliberately does NOT participate in the safety shift:
	# eliminating opponents is what makes a pass progressive, and a pressed
	# passer who can still find that ball should not have its value transferred
	# onto "find someone unmarked behind me".
	return maxf(
		w_dist * distance_utility
		+ w_angle * angle_utility
		+ effective_w_pressure * pressure_utility
		+ effective_w_advancement * advancement_utility
		+ WEIGHT_PACKING * packing_utility
		+ directional_bias,
		0.0)
