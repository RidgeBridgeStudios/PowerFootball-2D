##
## GoalkeeperDiveState
##
## The physical dive body: a one-way lateral commitment along the goal line.
## Once entered the keeper cannot change direction or steer — the dive is
## irrevocable for its full duration, then control hands back to Idle and the
## normal goalkeeper positioning brain resumes.
##
## Motion is driven through HeavyPlayerController.apply_kinematic_weight() (the
## only legal velocity path) with an accel/decel envelope: the first 60% of the
## dive accelerates toward the target Y, the rest bleeds off so the keeper
## settles rather than slamming to a stop on the line.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, GameManager.
## Exposes: the PlayerState interface plus dive_direction (set by the caller
##          before/at transition).
##

class_name GoalkeeperDiveState
extends PlayerState

## Lateral reach of a committed dive, in pixels along the goal-line Y axis.
const DIVE_REACH: float = 140.0
## Seconds the full dive takes from commitment to settle.
const DIVE_DURATION: float = 0.55
## First fraction of the duration spent accelerating before decelerating.
const ACCEL_PHASE: float = 0.60

## Maximum radius and height for intercepting/saving a ball during a dive.
const DIVE_SAVE_RADIUS: float = 38.0
const DIVE_SAVE_MAX_HEIGHT: float = 70.0

## Ball speed (px/s) above which a save is parried rather than held. A keeper
## does not catch a shot struck this hard — they get a hand to it and turn it
## away.
const PARRY_SPEED_THRESHOLD: float = 650.0
## Fraction of the incoming pace a parry retains.
const PARRY_SPEED_RETENTION: float = 0.45
## How far the parry is turned away from the incoming line, toward the nearest
## touchline. 1.0 sends it square across the face of goal; this angles it
## clearly wide without hurling it out of play every time. The point is that a
## parry goes toward the corner flag, NOT straight back into the slot for the
## striker to tap in — which is what a pure reversal did.
const PARRY_LATERAL_BIAS: float = 0.85

## Seconds this dive waits before the body commits, set by the coordinator from
## GoalkeeperDiveBrain.reaction_delay(). The keeper is already in the state
## during this window — beaten for reactions is beaten, not undecided — but is
## not yet moving or saving.
var reaction_delay: float = 0.0

## The lateral dive direction, normalised, set by the coordinator before the
## transition. x is always 0.0 (dives track the Y goal line); y is ±1.0.
var dive_direction: Vector2 = Vector2.ZERO

var dive_duration: float = DIVE_DURATION
var _elapsed: float = 0.0
var _dive_target: Vector2 = Vector2.ZERO


func enter(player: HeavyPlayerController) -> void:
	# A dive without a chosen side is a programming error — enter must not be
	# reached without a direction.
	assert(dive_direction != Vector2.ZERO)

	# Dive target stays on the keeper's own goal line (X locked), sliding
	# laterally along Y by the reach. The X used is the keeper's current
	# position — the brain has already projected the crossing point against the
	# line, and the keeper dives from where they stand, not toward the line.
	_dive_target = Vector2(
		player.global_position.x,
		player.global_position.y + dive_direction.y * DIVE_REACH
	)
	_elapsed = 0.0


func process(player: HeavyPlayerController, _delta: float) -> StringName:
	# A dead-ball phase interrupts the dive immediately: the keeper must reset
	# for the restart rather than finish an obsolete dive.
	if GameManager.current_phase != GameManager.MatchPhase.IN_PLAY:
		return IDLE

	# Intercept and catch the ball if it enters dive reach during the lunge
	var world: MatchWorldModel = MatchWorldModel.instance
	if world != null and world.ball_node != null and is_instance_valid(world.ball_node):
		var match_ball: Pseudo3DBall = world.ball_node
		# Nothing is saved before the keeper has actually reacted.
		if _elapsed >= reaction_delay \
				and not match_ball.is_frozen and match_ball.position_z <= DIVE_SAVE_MAX_HEIGHT:
			var dist_sq: float = player.global_position.distance_squared_to(match_ball.global_position)
			if dist_sq <= DIVE_SAVE_RADIUS * DIVE_SAVE_RADIUS:
				if match_ball.velocity.length() > PARRY_SPEED_THRESHOLD:
					_parry(player, match_ball)
					return IDLE
				var hold_state := player.state_factory.get_state(PlayerState.GOALKEEPER_HOLD) as GoalkeeperHoldState
				if hold_state != null:
					hold_state.was_diving_save = true
					hold_state.was_shot = true
				return GOALKEEPER_HOLD

	if _elapsed >= dive_duration + reaction_delay:
		return IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	_elapsed += delta

	# Reaction window: the keeper is committed to this side but has not moved
	# yet. Hand a zero intent to the controller so it decelerates normally —
	# this state still never writes velocity itself.
	if _elapsed < reaction_delay:
		player.apply_kinematic_weight(Vector2.ZERO, delta)
		return

	var phase_ratio: float = (_elapsed - reaction_delay) / dive_duration

	# Accel in the first ACCEL_PHASE, decel after — a lunge that falls away,
	# not a constant-speed slide.
	var speed_mult: float = 1.0
	if phase_ratio < ACCEL_PHASE:
		speed_mult = phase_ratio / ACCEL_PHASE
	else:
		speed_mult = 1.0 - ((phase_ratio - ACCEL_PHASE) / (1.0 - ACCEL_PHASE))
	speed_mult = clampf(speed_mult, 0.0, 1.0)

	# Seek the dive target: direction from the keeper toward _dive_target, its
	# length the enveloped deflection. apply_kinematic_weight treats the vector's
	# length as stick deflection (0..1) and its heading as the target direction,
	# so the keeper accelerates along the dive axis and eases off as the envelope
	# decays — no input, no AI steering, no movement_intent reads.
	var to_target: Vector2 = _dive_target - player.global_position
	if to_target.is_zero_approx():
		player.apply_kinematic_weight(Vector2.ZERO, delta)
		return
	var seek: Vector2 = to_target.normalized() * speed_mult
	player.apply_kinematic_weight(seek, delta)


## Turns a hard shot away toward the nearer touchline instead of holding it or
## rebounding it back down the middle. Routes the deflection through
## Pseudo3DBall.apply_kick() so the ball's own physics owns the result.
func _parry(player: HeavyPlayerController, match_ball: Pseudo3DBall) -> void:
	var incoming: Vector2 = match_ball.velocity
	var speed: float = incoming.length() * PARRY_SPEED_RETENTION
	if speed <= 0.0:
		return

	# Away from goal along the shot's own axis, plus a strong push toward
	# whichever touchline the keeper is nearer to.
	var world: MatchWorldModel = MatchWorldModel.instance
	var lateral_sign: float = signf(player.global_position.y)
	if world != null:
		var pitch_size: Vector2 = world.get_pitch_size()
		if pitch_size.y > 0.0:
			lateral_sign = signf(player.global_position.y - world.get_pitch_rect().get_center().y)
	if is_zero_approx(lateral_sign):
		lateral_sign = 1.0

	var away: Vector2 = Vector2(-signf(incoming.x), 0.0)
	if is_zero_approx(away.x):
		away.x = 1.0
	var parry_dir: Vector2 = (away + Vector2(0.0, lateral_sign * PARRY_LATERAL_BIAS)).normalized()

	match_ball.apply_kick(parry_dir * speed, 0.0, player)
	player.show_action_text("PARRY", Color(0.55, 0.85, 1.0))

