##
## PlayerStateFactory
##
## Owns the player's finite state machine: builds one instance of every state,
## routes lifecycle calls to the active one, and performs transitions.
##
## The parent HeavyPlayerController drives physics_update() explicitly inside its
## own _physics_process so that a state writes velocity in the same tick that
## move_and_slide() consumes it. Transition evaluation runs on the frame tick.
##
## Depends on: PlayerState subclasses, HeavyPlayerController (as parent node).
## Exposes: transition_to(), current_state_name, get_charge_ratio(),
##          signal state_changed(from, to)
##

class_name PlayerStateFactory
extends Node

signal state_changed(from_state: StringName, to_state: StringName)

@export var initial_state: StringName = PlayerState.IDLE
## Prints every transition. Invaluable while tuning the weight model.
@export var debug_transitions: bool = false

var current_state: PlayerState = null
var current_state_name: StringName = &""
## Seconds spent in the current state — states read it for their timing windows.
var time_in_state: float = 0.0

var _states: Dictionary[StringName, PlayerState] = {}

@onready var player: HeavyPlayerController = get_parent() as HeavyPlayerController


func _ready() -> void:
	# The parent calls physics_update() directly; no callback of our own.
	set_physics_process(false)
	_register_states()
	transition_to(initial_state)


func _process(delta: float) -> void:
	if current_state == null or player == null:
		return
	time_in_state += delta
	var next: StringName = current_state.process(player, delta)
	if next != &"" and next != current_state_name:
		transition_to(next)


## Called by HeavyPlayerController inside its physics tick.
func physics_update(delta: float) -> void:
	if current_state == null or player == null:
		return
	current_state.physics_process(player, delta)


func transition_to(state_name: StringName) -> void:
	if not _states.has(state_name):
		push_error("PlayerStateFactory: unknown state '%s'" % state_name)
		return

	var previous: StringName = current_state_name
	if current_state != null:
		current_state.exit(player)

	current_state = _states[state_name]
	current_state_name = state_name
	time_in_state = 0.0
	current_state.enter(player)

	if debug_transitions:
		print("[FSM] %s -> %s" % [previous, state_name])
	state_changed.emit(previous, state_name)


func is_in_state(state_name: StringName) -> bool:
	return current_state_name == state_name


## 0.0-1.0 charge for the HUD power meter; 0.0 whenever no kick is winding up.
func get_charge_ratio() -> float:
	var charging := current_state as ChargeKickState
	return charging.charge_ratio if charging != null else 0.0


func _register_states() -> void:
	_states[PlayerState.IDLE] = IdleState.new()
	_states[PlayerState.MOVE] = MoveState.new()
	_states[PlayerState.DRIBBLE] = DribbleState.new()
	_states[PlayerState.CHARGE_KICK] = ChargeKickState.new()
	_states[PlayerState.TACKLE] = TackleState.new()
	_states[PlayerState.AERIAL] = AerialState.new()
