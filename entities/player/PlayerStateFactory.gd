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


## Returns the flyweight state instance for `state_name`, or null when unknown.
## Lets a caller configure a state (e.g. set GoalkeeperDiveState.dive_direction)
## before transition_to() runs its enter(). States stay one instance per player,
## so this never allocates.
func get_state(state_name: StringName) -> PlayerState:
	return _states.get(state_name, null)


## 0.0-1.0 charge for the HUD power meter; 0.0 whenever no kick is winding up.
## ShotLockState, ThrowInState and PenaltyKickState also expose a charge_ratio
## field (shot lock-on power, throw distance, and runup progress respectively)
## so the same meter reads for them.
func get_charge_ratio() -> float:
	var charging := current_state as ChargeKickState
	if charging != null:
		return charging.charge_ratio

	var locking := current_state as ShotLockState
	if locking != null:
		return locking.charge_ratio

	var throwing := current_state as ThrowInState
	if throwing != null:
		return throwing.charge_ratio

	var penalty := current_state as PenaltyKickState
	if penalty != null:
		return penalty.charge_ratio

	return 0.0


func _register_states() -> void:
	_states[PlayerState.IDLE] = IdleState.new()
	_states[PlayerState.MOVE] = MoveState.new()
	_states[PlayerState.DRIBBLE] = DribbleState.new()
	_states[PlayerState.CHARGE_KICK] = ChargeKickState.new()
	_states[PlayerState.SHOT_LOCK] = ShotLockState.new()
	_states[PlayerState.TACKLE] = TackleState.new()
	_states[PlayerState.AERIAL] = AerialState.new()
	_states[PlayerState.SET_PIECE_FREEZE] = SetPieceFreezeState.new()
	_states[PlayerState.THROW_IN] = ThrowInState.new()
	_states[PlayerState.PENALTY_KICK] = PenaltyKickState.new()
	_states[PlayerState.GOALKEEPER_DIVE] = GoalkeeperDiveState.new()
	_states[PlayerState.GOALKEEPER_HOLD] = GoalkeeperHoldState.new()
	_states[PlayerState.CELEBRATE] = CelebrateState.new()
