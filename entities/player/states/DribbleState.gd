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

## Fraction of top speed the touch imparts to the ball.
## At 0.60 the ball stays close to the player's feet at a walk and drifts
## a comfortable 1–2 player-widths ahead at a sprint.
const TOUCH_SPEED_RATIO: float = 0.60
## Seconds between dribble touches. Shorter interval + lower speed ratio =
## finer ball control. 0.14 s gives ~7 Hz re-touch cadence — tight without
## feeling "on a rail".
const TOUCH_INTERVAL: float = 0.14
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
	if ball != null:
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
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)

	var common: StringName = check_common_transitions(player)
	if common != &"":
		return common

	var ball_in_range: Pseudo3DBall = player.get_ball_in_foot_range()

	if ball_in_range != null:
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

	var carry_target: Vector2 = player.global_position + carry_dir * CARRY_OFFSET
	var offset: Vector2 = carry_target - ball.global_position

	# --- Selective damping: kill lateral/reverse drift, preserve forward -----
	# Project the ball's current velocity onto the carry direction; damp only
	# the perpendicular remainder so the magnet never brakes a ball that is
	# already rolling the right way.
	var forward_component: Vector2 = carry_dir * ball.velocity.dot(carry_dir)
	var lateral_component: Vector2 = ball.velocity - forward_component
	ball.velocity = forward_component + lateral_component * LATERAL_DAMPING

	# --- Magnet pull: blend toward offset-derived velocity -------------------
	var pull_velocity: Vector2 = offset * MAGNET_STRENGTH
	ball.velocity = ball.velocity.lerp(pull_velocity, MAGNET_BLEND)

	# --- Timed touch impulse: unchanged logic --------------------------------
	# apply_kick() below replaces ball.velocity outright, so running it after
	# the magnet block means a touch tick always wins over the magnet pull, as
	# intended — the touch is a deliberate strike, not a correction.

	if _touch_cooldown > 0.0:
		return

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

	var touch_speed: float = player.get_current_top_speed() * TOUCH_SPEED_RATIO
	if player.is_sprinting:
		touch_speed *= SPRINT_TOUCH_BONUS

	ball.apply_kick(touch_direction * touch_speed, 0.0, player)
	ball.set_possessor(player)
	_touch_cooldown = TOUCH_INTERVAL

	# TODO: scale touch distance by a per-player `close_control` attribute and add
	# a shielding variant when the stick points away from the nearest defender.
