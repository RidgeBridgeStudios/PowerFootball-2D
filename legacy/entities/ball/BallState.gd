##
## BallState
##
## Abstract base for ball states. Same flyweight contract as PlayerState: one
## instance per ball, created by BallStateFactory, receiving the ball as an
## argument.
##
## The states do not integrate physics — Pseudo3DBall owns the solver. They
## describe what the ball currently *is* (rolling, held, in flight, dead) so
## that AI, audio and restart logic can query one authoritative answer.
##
## Depends on: Pseudo3DBall.
## Exposes: enter(), exit(), process(), physics_process().
##

class_name BallState
extends RefCounted

const GROUND_ROLL: StringName = &"GroundRoll"
const POSSESSION: StringName = &"Possession"
const FLIGHT: StringName = &"Flight"
const DEAD_BALL: StringName = &"DeadBall"


func enter(_ball: Pseudo3DBall) -> void:
	pass


func exit(_ball: Pseudo3DBall) -> void:
	pass


## Returns the next state name, or &"" to remain in this state.
func process(_ball: Pseudo3DBall, _delta: float) -> StringName:
	return &""


func physics_process(_ball: Pseudo3DBall, _delta: float) -> void:
	pass
