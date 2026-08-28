##
## TackleState
##
## A committed lunge with a success window, in the spirit of FIFA 12's tactical
## defending: contact inside the window wins the ball, contact outside it (or no
## contact at all) leaves the defender stumbling and out of position.
##
##   0.0 .. WINDUP            planting, no hitbox
##   WINDUP .. WINDUP+WINDOW  live window — ball contact wins possession
##   after                    recovery, movement input ignored
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, GameEvents.
## Exposes: the PlayerState interface.
##

class_name TackleState
extends PlayerState

## Seconds before the tackle goes live.
const WINDUP: float = 0.08
## Length of the successful-contact window.
const WINDOW: float = 0.2
## Seconds of stumble after a miss, during which input is ignored.
const RECOVERY: float = 0.45
## Lunge impulse along the facing direction.
const LUNGE_SPEED: float = 190.0
## How hard a won ball is knocked clear of the loser.
const DISPOSSESS_IMPULSE: float = 150.0

var _elapsed: float = 0.0
var _resolved: bool = false


func enter(player: HeavyPlayerController) -> void:
	_elapsed = 0.0
	_resolved = false
	# Commit the body forward. The lunge is an impulse, not a steering change:
	# once you have dived in, you are going where you were pointed.
	player.apply_external_impulse(player.facing_direction * LUNGE_SPEED)
	player.is_sprinting = false


func process(player: HeavyPlayerController, delta: float) -> StringName:
	_elapsed += delta

	if not _resolved and _elapsed >= WINDUP and _elapsed <= WINDUP + WINDOW:
		if _try_win_ball(player):
			_resolved = true
			return DRIBBLE

	if _elapsed >= WINDUP + WINDOW + RECOVERY:
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# No steering during a tackle — the lunge and friction alone decide where the
	# defender ends up. This is what makes a mistimed challenge expensive.
	player.apply_kinematic_weight(Vector2.ZERO, delta)


func _try_win_ball(player: HeavyPlayerController) -> bool:
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball == null or ball.is_airborne():
		return false

	var loser: Node2D = ball.possessor
	ball.apply_kick(player.facing_direction * DISPOSSESS_IMPULSE, 0.0)
	ball.set_possessor(player)

	if loser != null and loser != player:
		GameEvents.tackle_won.emit(player, loser)
		# TODO: roll a foul check here against the tackler's aggression and the
		# angle of approach, then emit GameEvents.foul_committed on a failed roll.

	if player.is_user_controlled:
		InputHelper.rumble(0.4, 0.7, 0.15)

	return true
