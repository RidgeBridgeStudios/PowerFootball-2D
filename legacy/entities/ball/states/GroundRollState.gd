##
## GroundRollState
##
## Free ball on the deck, decaying under pitch friction. The default state: any
## ball nobody is touching and that is not in the air ends up here.
##
## Depends on: BallState, Pseudo3DBall.
## Exposes: the BallState interface.
##

class_name GroundRollState
extends BallState


func process(ball: Pseudo3DBall, _delta: float) -> StringName:
	if ball.is_frozen:
		return DEAD_BALL
	if ball.is_airborne():
		return FLIGHT
	if ball.possessor != null:
		return POSSESSION
	return &""
