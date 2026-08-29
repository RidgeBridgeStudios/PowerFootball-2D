##
## UtilityMath
##
## Pure static maths for the CPU decision layer — no instance state, no
## lifecycle, no autoload entry. Everything here is a closed-form or
## fixed-iteration answer to a question PlayerBrain used to answer by
## simulating: where will the ball be when I get there, is that pass on, how
## much is this worth at this range.
##
## Fixed iteration counts matter. These functions are called from brains that
## already run on a frame budget, so every routine here is O(1) with a constant
## small enough to state in its own doc comment.
##
## Depends on: nothing.
## Exposes: calculate_intercept_point(), is_lane_blocked(), quadratic_decay(),
##          sigmoid()
##

class_name UtilityMath
extends RefCounted

## Below this speed the ball is not going anywhere worth predicting — the
## intercept point is simply where it already is.
const MIN_PREDICT_SPEED: float = 10.0

## Bisection steps used by calculate_intercept_point(). Four halvings resolve
## the stop time to 1/16th, which at a typical 2s roll is ~0.12s — finer than a
## player can react to anyway.
const INTERCEPT_ITERATIONS: int = 4


## Closed-form ball intercept.
##
## The ball decelerates linearly under pitch friction, so its position at time t
## (while still rolling) is
##
##     r_b(t) = b_pos + b_dir * (b_speed * t - 0.5 * friction * t^2)
##
## and the player needs
##
##     t_p(t) = |p_pos - r_b(t)| / p_max_speed + reaction_time
##
## seconds to get there. The intercept is the smallest t where t_p(t) <= t.
## t_p is monotone-ish and the feasible set is an interval ending at t_stop, so
## four bisection steps over [0, t_stop] land close enough to run at.
##
## `friction` is the combined per-second deceleration in px/s^2 — for
## Pseudo3DBall that is `pitch_friction * Pseudo3DBall.FRICTION_SCALE`, not the
## raw exported coefficient.
##
## Returns b_pos unchanged when the ball is already at rest.
static func calculate_intercept_point(
		p_pos: Vector2,
		p_max_speed: float,
		b_pos: Vector2,
		b_vel: Vector2,
		friction: float,
		reaction_time: float = 0.08
) -> Vector2:
	var b_speed: float = b_vel.length()
	if b_speed < MIN_PREDICT_SPEED:
		return b_pos

	var b_dir: Vector2 = b_vel / b_speed

	# A zero or negative friction would never stop the ball; clamp the horizon
	# to something finite so the bisection still terminates on a sane interval.
	var safe_friction: float = maxf(friction, 0.001)
	var t_stop: float = b_speed / safe_friction

	var safe_speed: float = maxf(p_max_speed, 1.0)

	var lo: float = 0.0
	var hi: float = t_stop

	for _i: int in range(INTERCEPT_ITERATIONS):
		var mid: float = (lo + hi) * 0.5
		var travel: float = b_speed * mid - 0.5 * safe_friction * mid * mid
		var point: Vector2 = b_pos + b_dir * travel
		var t_player: float = p_pos.distance_to(point) / safe_speed + reaction_time
		if t_player <= mid:
			# Reachable at mid — try to meet it sooner.
			hi = mid
		else:
			lo = mid

	var t_final: float = hi
	var final_travel: float = b_speed * t_final - 0.5 * safe_friction * t_final * t_final
	return b_pos + b_dir * final_travel


## True when `defender` sits within `min_clearance` px of the passer→receiver
## segment, i.e. the pass would have to go through them.
##
## Uses the closest-point-on-segment projection and compares squared distances,
## so the hot path never takes a square root. A degenerate lane (passer standing
## on the receiver) is never blocked.
static func is_lane_blocked(
		passer: Vector2,
		receiver: Vector2,
		defender: Vector2,
		min_clearance: float
) -> bool:
	var lane: Vector2 = receiver - passer
	var lane_len_sq: float = lane.length_squared()
	if lane_len_sq <= 0.0001:
		return false

	# Projection parameter of the defender onto the lane, clamped to the
	# segment so a defender behind the passer or beyond the receiver is judged
	# against the endpoint rather than the infinite line.
	var t: float = clampf((defender - passer).dot(lane) / lane_len_sq, 0.0, 1.0)
	var closest: Vector2 = passer + lane * t
	return closest.distance_squared_to(defender) < min_clearance * min_clearance


## 1.0 at zero distance falling to 0.0 at max_distance, on a quadratic curve.
## Holds its value near the source and drops away fast at the edge — the shape
## wanted for "how much does this thing near me matter".
static func quadratic_decay(distance: float, max_distance: float) -> float:
	if max_distance <= 0.0:
		return 0.0
	if distance >= max_distance:
		return 0.0
	var ratio: float = distance / max_distance
	return clampf(1.0 - ratio * ratio, 0.0, 1.0)


## Logistic curve through (midpoint, 0.5). `steepness` sets how sharply the
## response switches: small values give a gentle ramp, large values a soft
## threshold.
static func sigmoid(value: float, midpoint: float, steepness: float) -> float:
	return 1.0 / (1.0 + exp(-steepness * (value - midpoint)))
