##
## PossessionState
##
## The ball is loosely under a player's control — inside their foot sensor and
## being nudged along by DribbleState. Possession here is bookkeeping only: the
## ball is never parented to the player and keeps its own momentum, so any hard
## turn or tackle separates the two naturally.
##
## Depends on: BallState, Pseudo3DBall.
## Exposes: the BallState interface.
##

class_name PossessionState
extends BallState


func process(ball: Pseudo3DBall, _delta: float) -> StringName:
	if ball.is_frozen:
		return DEAD_BALL
	if ball.is_airborne():
		return FLIGHT
	if ball.possessor == null:
		return GROUND_ROLL
	return &""
