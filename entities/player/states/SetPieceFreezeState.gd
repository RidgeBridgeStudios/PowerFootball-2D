##
## SetPieceFreezeState
##
## Every non-taker player enters this state while a set piece is being set up
## and taken. It halts the player immediately, then ignores all input — human
## and CPU alike — until GameManager leaves the dead-ball phase, at which point
## it hands back to Idle on its own. SetPieceCoordinator does not need to
## un-freeze players explicitly: calling GameManager.restart_play() is enough.
##
## Depends on: PlayerState, HeavyPlayerController, GameManager (autoload).
## Exposes: the PlayerState interface.
##

class_name SetPieceFreezeState
extends PlayerState


func enter(player: HeavyPlayerController) -> void:
	player.velocity = Vector2.ZERO
	player.movement_intent = Vector2.ZERO
	player.is_sprinting = false


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# Friction only — no acceleration, no input authority.
	player.apply_kinematic_weight(Vector2.ZERO, delta)


func process(_player: HeavyPlayerController, _delta: float) -> StringName:
	if GameManager.is_in_play():
		return IDLE
	return &""
