##
## CelebrateState
##
## Active during GameManager.MatchPhase.GOAL_SCORED. Allows a human-controlled
## player to run around freely, while CPU players follow celebration or dejected-retreat
## steering vectors from PlayerBrain. When GameManager transitions to the next phase
## (KICKOFF / replay / restart), it automatically returns to IDLE or SET_PIECE_FREEZE.
##
## Depends on: PlayerState, HeavyPlayerController, GameManager (autoload).
## Exposes: the PlayerState interface.
##

class_name CelebrateState
extends PlayerState


func enter(_player: HeavyPlayerController) -> void:
	pass


func exit(_player: HeavyPlayerController) -> void:
	pass


func process(_player: HeavyPlayerController, _delta: float) -> StringName:
	if GameManager.current_phase != GameManager.MatchPhase.GOAL_SCORED:
		return IDLE
	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	player.apply_kinematic_weight(player.movement_intent, delta)
