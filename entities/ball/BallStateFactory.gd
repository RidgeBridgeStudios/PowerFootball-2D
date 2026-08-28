##
## BallStateFactory
##
## Owns the ball's finite state machine. Pseudo3DBall calls physics_update()
## from its physics tick, before the Z and XY solvers run, so a state can veto
## or seed motion for the frame.
##
## Depends on: BallState subclasses, Pseudo3DBall (as parent node).
## Exposes: transition_to(), current_state_name, signal state_changed(from, to)
##

class_name BallStateFactory
extends Node

signal state_changed(from_state: StringName, to_state: StringName)

@export var initial_state: StringName = BallState.GROUND_ROLL
@export var debug_transitions: bool = false

var current_state: BallState = null
var current_state_name: StringName = &""
var time_in_state: float = 0.0

var _states: Dictionary[StringName, BallState] = {}

@onready var ball: Pseudo3DBall = get_parent() as Pseudo3DBall


func _ready() -> void:
	set_physics_process(false)
	_states[BallState.GROUND_ROLL] = GroundRollState.new()
	_states[BallState.POSSESSION] = PossessionState.new()
	_states[BallState.FLIGHT] = FlightState.new()
	_states[BallState.DEAD_BALL] = DeadBallState.new()
	transition_to(initial_state)


func _process(delta: float) -> void:
	if current_state == null or ball == null:
		return
	time_in_state += delta
	var next: StringName = current_state.process(ball, delta)
	if next != &"" and next != current_state_name:
		transition_to(next)


func physics_update(delta: float) -> void:
	if current_state == null or ball == null:
		return
	current_state.physics_process(ball, delta)


func transition_to(state_name: StringName) -> void:
	if not _states.has(state_name):
		push_error("BallStateFactory: unknown state '%s'" % state_name)
		return

	var previous: StringName = current_state_name
	if current_state != null:
		current_state.exit(ball)

	current_state = _states[state_name]
	current_state_name = state_name
	time_in_state = 0.0
	current_state.enter(ball)

	if debug_transitions:
		print("[BALL FSM] %s -> %s" % [previous, state_name])
	state_changed.emit(previous, state_name)


func is_in_state(state_name: StringName) -> bool:
	return current_state_name == state_name
