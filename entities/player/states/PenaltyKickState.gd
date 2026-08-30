##
## PenaltyKickState
##
## A specialised, deterministic variant of ChargeKickState for penalties: the
## taker cannot move during the runup, only aim with the right stick, and power
## is fixed rather than charged. A penalty is about picking a side and
## committing, not about mashing a power meter — full power would also reproduce
## the high-charge trajectory jitter ChargeKickState's TODO already flags as a
## deliberately un-modelled scenario, which is exactly what a fixed 0.85 avoids.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, InputHelper,
##             GameEvents, GameManager.
## Exposes: the PlayerState interface plus charge_ratio (read by the HUD meter;
##          here it tracks runup progress rather than shot power).
##

class_name PenaltyKickState
extends PlayerState

## Seconds of locked runup before the kick fires.
const RUNUP_DELAY: float = 0.8
## Fixed shot power, 0.0-1.0 — deliberately below max power. See class doc.
const FIXED_POWER: float = 0.85
const SHOT_SPEED: float = 620.0

## 0.0-1.0 runup progress, read by PlayerStateFactory.get_charge_ratio() for
## the HUD meter (reused here as a "kick imminent" indicator, not a power bar).
var charge_ratio: float = 0.0

var _elapsed: float = 0.0
var _aim: Vector2 = Vector2.ZERO
var _struck: bool = false


func enter(player: HeavyPlayerController) -> void:
	_elapsed = 0.0
	_struck = false
	charge_ratio = 0.0
	_aim = player.facing_direction


func exit(_player: HeavyPlayerController) -> void:
	charge_ratio = 0.0


func process(player: HeavyPlayerController, delta: float) -> StringName:
	if _struck:
		return DRIBBLE if player.get_ball_in_foot_range() != null else IDLE

	_elapsed += delta
	charge_ratio = clampf(_elapsed / RUNUP_DELAY, 0.0, 1.0)

	# Aim can be adjusted right up until the kick fires; only movement is locked.
	if player.is_user_controlled:
		var aim: Vector2 = InputHelper.get_aim_vector()
		if aim != Vector2.ZERO:
			_aim = aim

	if _elapsed >= RUNUP_DELAY:
		_strike(player)

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# The runup is scripted, not driven by movement_intent — no steering authority.
	player.apply_kinematic_weight(Vector2.ZERO, delta)


func _strike(player: HeavyPlayerController) -> void:
	_struck = true
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball == null:
		# Swung and missed. TODO: this should not be possible once the taker is
		# reliably placed on the spot; if it happens anyway, restarting play is
		# the safe fallback rather than leaving the phase stuck.
		GameManager.restart_play()
		return

	var aim: Vector2 = _aim if _aim != Vector2.ZERO else player.facing_direction
	var speed: float = SHOT_SPEED * FIXED_POWER
	ball.apply_kick(aim.normalized() * speed, 0.0, player)
	player.show_action_text("SHOT")
	GameEvents.ball_struck.emit(player, speed, FIXED_POWER, true)

	if player.is_user_controlled:
		InputHelper.rumble(0.25, 0.6, 0.15)

	# TODO: only restart immediately when the shot is clearly dead (saved,
	# wide, or scored). A save or post rebound should stay live for a
	# follow-up instead of insta-restarting — deferred per the brief.
	GameManager.restart_play()
