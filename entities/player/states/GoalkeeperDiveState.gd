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

	if _elapsed >= dive_duration:
		return IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	_elapsed += delta

	var phase_ratio: float = _elapsed / dive_duration

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
