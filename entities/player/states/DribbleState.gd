##
## DribbleState
##
## Loose possession, Sensible Soccer style. The ball is never parented or
## snapped to the player: it is nudged forward with micro-impulses whenever it
## drifts inside the foot sensor. Turn sharply or sprint too hard and the ball
## runs away from you — that separation is the mechanic, not a bug.
## Magnetism layer: every physics tick a velocity-correction pull keeps the ball
## at CARRY_OFFSET px ahead of the player along the travel direction. The magnet
## is intentionally strong — a 10px gap produces a 550 px/s correction so a
## sprinting player never outruns it. Only lateral/reverse momentum is damped;
## forward momentum is not braked.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall.
## Exposes: the PlayerState interface.
##

class_name DribbleState
extends PlayerState

## --- Magnetism constants ----------------------------------------------------

## Pixels ahead of the player (along travel direction) the ball is pulled toward.
## NOTE: unused by live logic — kept as a fallback reference value only. The
## carry target now derives its offset from `close_control` dynamically (see
## physics_process) so high-control players keep the ball tighter.
const CARRY_OFFSET: float = 22.0

## Scales gap-in-pixels to correction px/s. 55.0 → 550 px/s per 10px gap.
## Strong enough that even a sprinting player (up to 304 px/s) cannot outrun
## the correction within a physics tick.
const MAGNET_STRENGTH: float = 55.0

## Lerp weight applied per physics tick to blend toward the magnet velocity.
## 0.85 locks the ball onto the carry target within ~1 frame at 60 Hz.
const MAGNET_BLEND: float = 0.85

## Fraction of the ball's lateral (perpendicular-to-travel) velocity kept each
## tick while possessed. Only sideways/reverse drift is damped — forward
## momentum along the carry direction is left untouched so the magnet never
## fights the ball's own momentum.
const LATERAL_DAMPING: float = 0.6

## Seconds the ball may stay outside the foot sensor before possession drops.
## Prevents jitter-drops from momentary physics separations at high speed.
const POSSESSION_GRACE: float = 0.10

## --- Touch constants ---------------------------------------------------------

## Sprint multiplier on touch speed. The ball still drifts looser at pace,
## but by one body length — not three.
const SPRINT_TOUCH_BONUS: float = 1.15
## Close control: dribbling costs a slice of top speed.
const DRIBBLE_SPEED_PENALTY: float = 0.9

## --- State vars -------------------------------------------------------------

var _touch_cooldown: float = 0.0
var _grace_timer: float = 0.0
## The ball this dribble session is tracking. Cached on enter so the magnet
## still has a target even on a tick where the ball is momentarily outside
## the foot sensor (grace window).
var _possessed_ball: Pseudo3DBall = null


func enter(player: HeavyPlayerController) -> void:
	_touch_cooldown = 0.0
	_grace_timer = 0.0
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball != null and player.can_carry_ball():
		ball.set_possessor(player)
		_possessed_ball = ball
		player.possession_gained.emit()
	else:
		_possessed_ball = null


func exit(player: HeavyPlayerController) -> void:
	if _possessed_ball != null and _possessed_ball.possessor == player:
		_possessed_ball.release_possession()
	_possessed_ball = null
	player.possession_lost.emit()


func process(player: HeavyPlayerController, delta: float) -> StringName:
	# CPU players: exit dribble when the brain has decided to shoot or pass.
	# The brain's _steer_for_action() already handles the kick execution inline —
	# DribbleState only needs to step aside so the next frame's movement is correct.
	if not player.is_user_controlled:
		var brain: PlayerBrain = player.get_node_or_null("PlayerBrain") as PlayerBrain
		if brain != null:
			if brain.current_action == &"AttemptShoot" or brain.current_action == &"Pass":
				return PlayerState.MOVE

	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)

	var common: StringName = check_common_transitions(player)
	if common != &"":
		return common

	var ball_in_range: Pseudo3DBall = player.get_ball_in_foot_range()

	if ball_in_range != null and player.can_carry_ball():
		# Ball is inside the sensor — reset grace, keep tracking.
		_grace_timer = 0.0
		if _possessed_ball == null:
			_possessed_ball = ball_in_range
			ball_in_range.set_possessor(player)
	else:
		# Ball has left the sensor. Check grace window before dropping.
		if _possessed_ball != null and _possessed_ball.possessor == player:
			_grace_timer += delta
			if _grace_timer >= POSSESSION_GRACE:
				# Grace expired — genuine loss of possession.
				return MOVE if player.movement_intent.length() > 0.05 else IDLE
		else:
			# No possessor link at all — drop immediately.
			return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	player.apply_kinematic_weight(player.movement_intent * DRIBBLE_SPEED_PENALTY, delta)

	var ball: Pseudo3DBall = _possessed_ball
	if ball == null or ball.is_airborne():
		return

	# --- Carry direction: where the player is physically travelling ----------
	# Use velocity.normalized() (actual travel) rather than facing_direction
	# (intent, can lag a frame during a turn). Fall back to facing_direction
	# at rest, where velocity carries no useful heading.
	var carry_dir: Vector2 = player.velocity.normalized() \
		if player.velocity.length() > 10.0 \
		else player.facing_direction

	var world: MatchWorldModel = MatchWorldModel.instance
	var shield_dir: Vector2 = carry_dir
	if world != null:
		var nearest_opp: Vector2 = world.nearest_opponent_position(
			player.global_position, player.team)
		var to_opp: Vector2 = (nearest_opp - player.global_position).normalized()
		if player.movement_intent.normalized().dot(to_opp) < -0.3:
			shield_dir = -to_opp

	var dynamic_offset: float = lerpf(28.0, 16.0, player.get_close_control())
	var carry_target: Vector2 = player.global_position + shield_dir * dynamic_offset

	# --- Branch: touch frames skip the magnet entirely -----------------------
	# A touch tick already overwrites ball.velocity via apply_kick(), so the
	# magnet correction (selective damping + lerp) would be pure wasted work
	# on that frame. Branch on cooldown so each frame runs exactly one block:
	# either the touch impulse, or the magnet pull — never both.
	if _touch_cooldown <= 0.0:
		_apply_touch(player, carry_dir, shield_dir)
	else:
		_apply_magnet(ball, carry_dir, carry_target)
		_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)


func _apply_magnet(ball: Pseudo3DBall, carry_dir: Vector2, carry_target: Vector2) -> void:
	# --- Selective damping: kill lateral/reverse drift, preserve forward -----
	# Project the ball's current velocity onto the carry direction; damp only
	# the perpendicular remainder so the magnet never brakes a ball that is
	# already rolling the right way.
	var forward_component: Vector2 = carry_dir * ball.velocity.dot(carry_dir)
	var lateral_component: Vector2 = ball.velocity - forward_component
	ball.velocity = forward_component + lateral_component * LATERAL_DAMPING

	# --- Magnet pull: blend toward offset-derived velocity -------------------
	var offset: Vector2 = carry_target - ball.global_position
	var pull_velocity: Vector2 = offset * MAGNET_STRENGTH
	ball.velocity = ball.velocity.lerp(pull_velocity, MAGNET_BLEND)


func _apply_touch(player: HeavyPlayerController, carry_dir: Vector2, shield_dir: Vector2) -> void:
	var ball: Pseudo3DBall = _possessed_ball
	var control: float = player.get_close_control() if player.has_method(&"get_close_control") else 0.65
	var effective_touch_ratio: float = lerpf(0.85, 0.50, 1.0 - control)
	var effective_interval: float = lerpf(0.10, 0.20, 1.0 - control)

	# Push the ball along the running line rather than the stick line: a heavy
	# player cannot redirect the ball faster than they can redirect themselves.
	# Blend carry_dir toward the desired intent. At low speed the blend is 0 —
	# the ball follows the body's current heading. At full pace, up to 30° of
	# re-direction per touch is allowed, matching how a heavy player
	# realistically redirects the ball.
	var touch_direction: Vector2 = carry_dir
	if player.movement_intent.length() > 0.05:
		var desired: Vector2 = player.movement_intent.normalized()
		var blend: float = clampf(player.get_speed_ratio() * 0.5, 0.0, 0.5)
		touch_direction = carry_dir.lerp(desired, 1.0 - blend).normalized()

	# When actively shielding (shield_dir was diverted away from carry_dir),
	# push the ball slightly behind ourselves toward the shielded position
	# rather than continuing straight along the carry direction.
	if shield_dir != carry_dir:
		touch_direction = touch_direction.lerp(shield_dir, 0.4).normalized()

	var touch_speed: float = player.get_current_top_speed() * effective_touch_ratio
	if player.is_sprinting:
		touch_speed *= SPRINT_TOUCH_BONUS

	ball.apply_kick(touch_direction * touch_speed, 0.0, player)
	ball.set_possessor(player)
	_touch_cooldown = effective_interval
