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
## A miss that still lands the tackler this close to an opponent is judged a
## foul rather than a clean whiff — a proxy for "the challenge took the man".
const FOUL_CONTACT_RADIUS: float = 40.0

var _elapsed: float = 0.0
var _resolved: bool = false
var _foul_checked: bool = false


func enter(player: HeavyPlayerController) -> void:
	_elapsed = 0.0
	_resolved = false
	_foul_checked = false
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

	# The live window has closed without winning the ball: a lunge that still
	# landed the tackler on top of an opponent is a mistimed, foul-worthy
	# challenge rather than a clean miss.
	if not _resolved and not _foul_checked and _elapsed > WINDUP + WINDOW:
		_foul_checked = true
		_check_mistimed_foul(player)

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
	ball.apply_kick(player.facing_direction * DISPOSSESS_IMPULSE, 0.0, player)
	ball.set_possessor(player)

	if loser != null and loser != player:
		GameEvents.tackle_won.emit(player, loser)

	if player.is_user_controlled:
		InputHelper.rumble(0.4, 0.7, 0.15)

	return true


func _check_mistimed_foul(player: HeavyPlayerController) -> void:
	var victim: HeavyPlayerController = _find_nearby_opponent(player)
	if victim == null:
		return
	GameEvents.foul_committed.emit(player, victim, player.global_position)
	# TODO: weight this by the tackler's aggression/composure and the approach
	# angle once PlayerBrain exposes them, so fouls scale with attributes
	# rather than being a flat proximity check.


func _find_nearby_opponent(player: HeavyPlayerController) -> HeavyPlayerController:
	var closest: HeavyPlayerController = null
	var closest_distance: float = FOUL_CONTACT_RADIUS
	for node: Node in player.get_tree().get_nodes_in_group(&"players"):
		var other := node as HeavyPlayerController
		if other == null or other == player or other.team == player.team:
			continue
		var distance: float = player.global_position.distance_to(other.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = other
	return closest
