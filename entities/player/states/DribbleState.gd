##
## DribbleState
##
## Loose possession, Sensible Soccer style. The ball is never parented or
## snapped to the player: it is nudged forward with micro-impulses whenever it
## drifts inside the foot sensor. Turn sharply or sprint too hard and the ball
## runs away from you — that separation is the mechanic, not a bug.
## Magnetism layer: every physics tick a velocity-correction pull is applied to
## keep the ball anchored near the carry target (CARRY_OFFSET px ahead of the
## player), on top of the timed touch impulse below. MAGNET_STRENGTH and
## MAGNET_BLEND are intentionally strong — better to feel magnetic than to let
## the ball slip through the body between touches. POSSESSION_DAMPING kills
## residual ball momentum each tick while possessed. A short POSSESSION_GRACE
## window prevents jitter-drops when the ball briefly leaves the foot sensor.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall.
## Exposes: the PlayerState interface.
##

class_name DribbleState
extends PlayerState

## --- Magnetism constants ----------------------------------------------------

## Pixels ahead of the player centre the ball is pulled toward.
const CARRY_OFFSET: float = 18.0

## Scales offset-in-pixels to a correction velocity in px/s.
## At 14.0, a 10 px gap → 140 px/s pull. Deliberately strong.
const MAGNET_STRENGTH: float = 14.0

## Lerp weight applied per physics tick to blend toward the magnet velocity.
## 0.55 means ~3 ticks to fully lock the ball to the carry position.
const MAGNET_BLEND: float = 0.55

## Fraction of the ball's own velocity kept each tick while possessed.
## 0.72 removes 28%/tick — kills free spin within ~10 frames at 60 Hz.
const POSSESSION_DAMPING: float = 0.72

## Seconds the ball may stay outside the foot sensor before possession drops.
## Prevents jitter-drops from momentary physics separations at high speed.
const POSSESSION_GRACE: float = 0.08

## --- Touch constants (unchanged from previous version) ---------------------

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

	# --- Magnetism: runs every tick regardless of touch cooldown -------------
	# Pseudo3DBall extends CharacterBody2D, so its velocity property is
	# `velocity` (not RigidBody2D's `linear_velocity`).

	var carry_target: Vector2 = player.global_position + player.facing_direction * CARRY_OFFSET
	var offset: Vector2 = carry_target - ball.global_position

	# Damp free ball momentum first, then blend toward the magnet pull.
	ball.velocity *= POSSESSION_DAMPING
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
	# Blend facing_direction toward the desired intent. At low speed the blend
	# is 0 — the ball follows the body's current heading. At full pace, up to
	# 30° of re-direction per touch is allowed, matching how a heavy player
	# realistically redirects the ball.
	var touch_direction: Vector2 = player.facing_direction
	if player.movement_intent.length() > 0.05:
		var desired: Vector2 = player.movement_intent.normalized()
		var blend: float = clampf(player.get_speed_ratio() * 0.5, 0.0, 0.5)
		touch_direction = player.facing_direction.lerp(desired, 1.0 - blend).normalized()

	var touch_speed: float = player.get_current_top_speed() * TOUCH_SPEED_RATIO
	if player.is_sprinting:
		touch_speed *= SPRINT_TOUCH_BONUS

	ball.apply_kick(touch_direction * touch_speed, 0.0, player)
	ball.set_possessor(player)
	_touch_cooldown = TOUCH_INTERVAL

	# TODO: scale touch distance by a per-player `close_control` attribute and add
	# a shielding variant when the stick points away from the nearest defender.
