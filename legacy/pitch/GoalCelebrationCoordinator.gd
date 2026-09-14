##
## GoalCelebrationCoordinator
##
## Manages goal celebration flow, target positioning (corner flag runs / huddles),
## celebration duration, camera focus, and user skip handling.
##
## Supports:
##   1. Active Gameplay (human user on scoring team): user retains full movement and sprint
##      authority, while AI teammates flock towards the user to form a celebration huddle.
##   2. Simulation / AI Spectator Mode: the AI scorer sprints to the attacking corner flag,
##      and teammates converge there to celebrate together in a huddle.
##   3. Conceding Team: AI players retreat dejectedly towards their kickoff anchors.
##
## Depends on: PitchBoundary, HeavyPlayerController, MatchCamera, GameManager, GameEvents.
## Exposes: bind(boundary, players_node, camera), start_celebration(scoring_team, scorer, on_complete),
##          skip_celebration(), is_celebrating(), get_celebration_anchor(), get_celebration_lead()
##

class_name GoalCelebrationCoordinator
extends Node

signal celebration_started(team: int, scorer: Node, target_pos: Vector2)
signal celebration_finished(was_skipped: bool)

## Duration of celebration in seconds before proceeding to replay or kickoff
@export var celebration_duration: float = 3.5

var _boundary: PitchBoundary = null
var _players_node: Node2D = null
var _camera: MatchCamera = null

var _is_celebrating: bool = false
var _celebration_timer: float = 0.0
var _scoring_team: int = -1
var _scorer_node: Node = null
var _scorer_controller: HeavyPlayerController = null
var _user_player: HeavyPlayerController = null
var _celebration_anchor: Vector2 = Vector2.ZERO
var _on_complete_callback: Callable = Callable()

var _players_list: Array[HeavyPlayerController] = []
var _shout_cooldown: float = 0.0

const CORNER_INSET: float = 48.0
const CELEBRATION_SHOUTS: Array[String] = [
	"GOAL!",
	"VAMOS!",
	"SIUUU!",
	"GET IN!",
	"WHAT A STRIKE!",
	"YESSS!"
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(p_boundary: PitchBoundary, players_node: Node2D, camera: MatchCamera) -> void:
	_boundary = p_boundary
	_players_node = players_node
	_camera = camera
	_refresh_players_list()


func _refresh_players_list() -> void:
	_players_list.clear()
	if _players_node == null:
		return
	for child: Node in _players_node.get_children():
		var player := child as HeavyPlayerController
		if player != null:
			_players_list.append(player)


func is_celebrating() -> bool:
	return _is_celebrating


func get_celebration_anchor() -> Vector2:
	return _celebration_anchor


func get_celebration_lead() -> HeavyPlayerController:
	if _user_player != null and is_instance_valid(_user_player):
		return _user_player
	if _scorer_controller != null and is_instance_valid(_scorer_controller):
		return _scorer_controller
	return null


func start_celebration(scoring_team: int, scorer: Node = null, on_complete: Callable = Callable()) -> void:
	if _is_celebrating:
		return

	_refresh_players_list()
	_is_celebrating = true
	_celebration_timer = 0.0
	_shout_cooldown = 0.2
	_scoring_team = scoring_team
	_scorer_node = scorer
	_scorer_controller = scorer as HeavyPlayerController
	_on_complete_callback = on_complete

	# Check if human player is on the scoring team
	_user_player = null
	for player: HeavyPlayerController in _players_list:
		if player != null and is_instance_valid(player) and player.team == _scoring_team and player.is_user_controlled:
			_user_player = player
			break

	# Fallback scorer if null or own-goal
	if _scorer_controller == null or _scorer_controller.team != _scoring_team:
		for player: HeavyPlayerController in _players_list:
			if player != null and is_instance_valid(player) and player.team == _scoring_team:
				if player.brain != null and not player.brain.is_goalkeeper:
					_scorer_controller = player
					break

	# Calculate celebratory corner flag target
	_celebration_anchor = _calculate_corner_target()

	# Transition all active players to CELEBRATE state
	for player: HeavyPlayerController in _players_list:
		if player != null and is_instance_valid(player) and player.state_factory != null:
			player.state_factory.transition_to(PlayerState.CELEBRATE)

	# Scorer initial action text shout
	if _scorer_controller != null and is_instance_valid(_scorer_controller):
		_scorer_controller.show_action_text(CELEBRATION_SHOUTS[randi() % CELEBRATION_SHOUTS.size()])

	GameEvents.celebration_started.emit(scoring_team, scorer)
	celebration_started.emit(scoring_team, scorer, _celebration_anchor)


func _calculate_corner_target() -> Vector2:
	if _boundary == null:
		return Vector2.ZERO

	var half: Vector2 = _boundary.pitch_size * 0.5
	var centre: Vector2 = _boundary.get_centre_spot()
	var defends_left: bool = (_scoring_team == 0) if not _boundary.sides_flipped else (_scoring_team != 0)
	var attack_dir: float = 1.0 if defends_left else -1.0
	var y_sign: float = 1.0
	if _scorer_controller != null and is_instance_valid(_scorer_controller):
		y_sign = 1.0 if _scorer_controller.global_position.y >= centre.y else -1.0
	elif _user_player != null and is_instance_valid(_user_player):
		y_sign = 1.0 if _user_player.global_position.y >= centre.y else -1.0

	return centre + Vector2(
		attack_dir * (half.x - CORNER_INSET),
		y_sign * (half.y - CORNER_INSET)
	)


func _physics_process(delta: float) -> void:
	if not _is_celebrating:
		return

	_celebration_timer += delta

	# Periodic celebratory shouts from teammates near the leader
	_shout_cooldown -= delta
	if _shout_cooldown <= 0.0:
		_shout_cooldown = randf_range(0.8, 1.6)
		_trigger_random_huddle_shout()

	if _celebration_timer >= celebration_duration:
		_finish_celebration(false)


func _trigger_random_huddle_shout() -> void:
	var lead: HeavyPlayerController = get_celebration_lead()
	if lead == null or not is_instance_valid(lead):
		return

	for player: HeavyPlayerController in _players_list:
		if player != null and is_instance_valid(player) and player != lead and player.team == _scoring_team:
			var dist_sq: float = player.global_position.distance_squared_to(lead.global_position)
			if dist_sq < 10000.0:  # within 100px of leader
				player.show_action_text(CELEBRATION_SHOUTS[randi() % CELEBRATION_SHOUTS.size()])
				break


func skip_celebration() -> void:
	if not _is_celebrating:
		return
	_finish_celebration(true)


func _finish_celebration(was_skipped: bool) -> void:
	if not _is_celebrating:
		return

	_is_celebrating = false
	GameEvents.celebration_ended.emit()
	celebration_finished.emit(was_skipped)

	var cb: Callable = _on_complete_callback
	_on_complete_callback = Callable()
	if cb.is_valid():
		cb.call()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_celebrating:
		return
	if not event.is_pressed() or event.is_echo():
		return

	var is_skip_key: bool = (event is InputEventKey) and (
		event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE
	)
	var is_skip_mouse: bool = (event is InputEventMouseButton) and (event.button_index == MOUSE_BUTTON_LEFT)
	var is_skip_action: bool = event.is_action_pressed(&"action_ui_accept") or event.is_action_pressed(&"action_cancel") or event.is_action_pressed(&"action_pass") or event.is_action_pressed(&"action_kick")

	if is_skip_key or is_skip_mouse or is_skip_action:
		get_viewport().set_input_as_handled()
		skip_celebration()
