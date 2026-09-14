##
## FlightState
##
## Ball is off the turf: crosses, lobs, clearances and the bounce chain that
## follows. Pseudo3DBall integrates the arc; this state just marks the ball as
## airborne so aerial challenges and audio can react to it.
##
## Depends on: BallState, Pseudo3DBall.
## Exposes: the BallState interface.
##

class_name FlightState
extends BallState


func enter(ball: Pseudo3DBall) -> void:
	ball.release_possession()


func process(ball: Pseudo3DBall, _delta: float) -> StringName:
	if ball.is_frozen:
		return DEAD_BALL
	if not ball.is_airborne():
		return POSSESSION if ball.possessor != null else GROUND_ROLL
	return &""

	# TODO: apply a spin/curve term to velocity here once shots carry swerve —
	# a per-kick lateral acceleration is the cheapest convincing model.
