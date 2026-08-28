##
## DeadBallState
##
## Ball is out of play: kickoff, goal celebration, throw-in, half time. Motion
## is frozen and possession cleared until the match phase restarts play.
##
## Depends on: BallState, Pseudo3DBall.
## Exposes: the BallState interface.
##

class_name DeadBallState
extends BallState


func enter(ball: Pseudo3DBall) -> void:
	ball.freeze()
	ball.release_possession()


func exit(ball: Pseudo3DBall) -> void:
	ball.unfreeze()


func process(ball: Pseudo3DBall, _delta: float) -> StringName:
	if not ball.is_frozen:
		return GROUND_ROLL
	return &""
