##
## GoalReplayCoordinator
##
## Cinematic coordinator managing match goal replays (Football Manager style).
## Continuously records a rolling circular buffer of physics and visual states for the
## ball and all 22 players during live play (IN_PLAY). When a goal is scored and replays
## are enabled, it plays back the buildup sequence, sets the broadcast replay overlay,
## preserves and restores simulation speed scales, and provides instantaneous skipping.
##
## Memory discipline:
##   - Zero heap allocations in hot physics recording loops (_physics_process).
##   - Preallocated fixed snapshot buffer of ReplayPlayerSnapshot and ReplayFrame.
##
## Depends on: Pseudo3DBall, HeavyPlayerController, PlayerVisual, MatchCamera,
##             PitchBoundary, GameManager, GameEvents.
## Exposes: bind(ball, players_node, camera, boundary), start_replay(scoring_team, scorer),
##          skip_replay(), stop_replay(), is_replaying(), is_recording(),
##          signal replay_started, signal replay_finished.
##

class_name GoalReplayCoordinator
extends Node

signal replay_started(team: int, scorer: Node)
signal replay_finished(was_skipped: bool)

## Internal struct holding per-player snapshot data.
class PlayerSnapshot:
	var pos: Vector2 = Vector2.ZERO
	var facing: Vector2 = Vector2.RIGHT
	var z: float = 0.0
	var is_user: bool = false
	var is_possessor: bool = false
	var is_valid: bool = false

## Internal struct holding full match frame snapshot data.
class FrameSnapshot:
	var ball_pos: Vector2 = Vector2.ZERO
	var ball_z: float = 0.0
	var ball_basis: Basis = Basis.IDENTITY
	var ball_vel: Vector2 = Vector2.ZERO
	var players: Array[PlayerSnapshot] = []

	func _init(player_count: int) -> void:
		players.clear()
		for i: int in range(player_count):
			players.append(PlayerSnapshot.new())

## 480 frames @ 60 Hz = 8.0 seconds of match history.
const MAX_RECORD_FRAMES: int = 480
## Maximum players tracked (11 home + 11 away).
const MAX_TRACKED_PLAYERS: int = 22
## Playback speed during replay (1.0 = normal real-time broadcast speed).
const REPLAY_PLAYBACK_SPEED: float = 1.0

var _ball: Pseudo3DBall = null
var _players_node: Node2D = null
var _camera: MatchCamera = null
var _boundary: PitchBoundary = null
var _players_list: Array[HeavyPlayerController] = []

## Preallocated circular ring buffer
var _ring_buffer: Array[FrameSnapshot] = []
var _write_head: int = 0
var _recorded_count: int = 0

## Active replay playback state
var _is_replaying: bool = false
var _replay_start_head: int = 0
var _replay_total_frames: int = 0
var _replay_playback_step: int = 0
var _previous_simulation_speed: float = 1.0
var _scoring_team: int = -1
var _scorer_node: Node = null

## Post-replay resumption callback
var _on_complete_callback: Callable = Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_ring_buffer()


func _init_ring_buffer() -> void:
	_ring_buffer.clear()
	for i: int in range(MAX_RECORD_FRAMES):
		_ring_buffer.append(FrameSnapshot.new(MAX_TRACKED_PLAYERS))
	_write_head = 0
	_recorded_count = 0


## Binds all match participants and pitch components.
func bind(
	p_ball: Pseudo3DBall,
	players_node: Node2D,
	camera: MatchCamera,
	boundary: PitchBoundary
) -> void:
	_ball = p_ball
	_players_node = players_node
	_camera = camera
	_boundary = boundary
	_refresh_players_list()


func _refresh_players_list() -> void:
	_players_list.clear()
	if _players_node == null:
		return
	for child: Node in _players_node.get_children():
		var player := child as HeavyPlayerController
		if player != null:
			_players_list.append(player)


func is_replaying() -> bool:
	return _is_replaying


func is_recording() -> bool:
	return not _is_replaying and GameManager.current_phase == GameManager.MatchPhase.IN_PLAY


func can_replay() -> bool:
	return GameManager.is_goal_replays_enabled() and _recorded_count >= 30 and not _is_replaying


func _physics_process(_delta: float) -> void:
	if _is_replaying:
		_process_replay_playback()
	elif is_recording():
		_record_current_frame()


## Hot path: zero allocations inside this function.
func _record_current_frame() -> void:
	if _ball == null:
		return

	var frame: FrameSnapshot = _ring_buffer[_write_head]
	frame.ball_pos = _ball.global_position
	frame.ball_z = _ball.position_z
	frame.ball_basis = _ball._ball_basis
	frame.ball_vel = _ball.velocity

	var p_count: int = mini(_players_list.size(), MAX_TRACKED_PLAYERS)
	for i: int in range(p_count):
		var player: HeavyPlayerController = _players_list[i]
		var p_snap: PlayerSnapshot = frame.players[i]
		if player != null and is_instance_valid(player):
			p_snap.is_valid = true
			p_snap.pos = player.global_position
			p_snap.facing = player.facing_direction
			p_snap.z = player.current_z
			p_snap.is_user = player.is_user_controlled
			p_snap.is_possessor = (_ball.possessor == player)
		else:
			p_snap.is_valid = false

	_write_head = (_write_head + 1) % MAX_RECORD_FRAMES
	_recorded_count = mini(_recorded_count + 1, MAX_RECORD_FRAMES)


## Starts playing back the recorded goal buildup sequence.
func start_replay(scoring_team: int, scorer: Node = null, on_complete: Callable = Callable()) -> void:
	if _is_replaying or _recorded_count < 30:
		if on_complete.is_valid():
			on_complete.call()
		return

	_is_replaying = true
	_scoring_team = scoring_team
	_scorer_node = scorer
	_on_complete_callback = on_complete

	# Preserve simulation speed and drop to normal 1.0x for watchable replay
	_previous_simulation_speed = GameManager.get_simulation_speed()
	Engine.time_scale = REPLAY_PLAYBACK_SPEED

	# Replay up to the last 360-480 frames (~6.0-8.0 seconds of buildup)
	_replay_total_frames = mini(_recorded_count, MAX_RECORD_FRAMES)
	_replay_start_head = (_write_head - _replay_total_frames + MAX_RECORD_FRAMES) % MAX_RECORD_FRAMES
	_replay_playback_step = 0

	# Suspend physics execution on entities during replay
	if _ball != null:
		_ball.is_frozen = true
	for player: HeavyPlayerController in _players_list:
		if player != null and is_instance_valid(player):
			player.set_physics_process(false)

	GameEvents.replay_started.emit(scoring_team, scorer)
	replay_started.emit(scoring_team, scorer)


func _process_replay_playback() -> void:
	if not _is_replaying:
		return

	if _replay_playback_step >= _replay_total_frames:
		_finish_replay(false)
		return

	var ring_idx: int = (_replay_start_head + _replay_playback_step) % MAX_RECORD_FRAMES
	var frame: FrameSnapshot = _ring_buffer[ring_idx]

	# Apply snapshot to ball
	if _ball != null:
		_ball.global_position = frame.ball_pos
		_ball.position_z = frame.ball_z
		_ball._ball_basis = frame.ball_basis
		_ball.velocity = frame.ball_vel
		_ball.render_visuals()

	# Apply snapshot to players
	var p_count: int = mini(_players_list.size(), MAX_TRACKED_PLAYERS)
	for i: int in range(p_count):
		var player: HeavyPlayerController = _players_list[i]
		var p_snap: PlayerSnapshot = frame.players[i]
		if player != null and is_instance_valid(player) and p_snap.is_valid:
			player.global_position = p_snap.pos
			player.facing_direction = p_snap.facing
			player.current_z = p_snap.z
			if player.visual != null:
				player.visual.sync_physics(p_snap.facing, p_snap.z, p_snap.is_user, p_snap.is_possessor)

	_replay_playback_step += 1


## Skips replay immediately and advances to kickoff restart.
func skip_replay() -> void:
	if not _is_replaying:
		return
	_finish_replay(true)


func stop_replay() -> void:
	if not _is_replaying:
		return
	_finish_replay(false)


func _finish_replay(was_skipped: bool) -> void:
	if not _is_replaying:
		return

	_is_replaying = false

	# Re-enable physical entities
	for player: HeavyPlayerController in _players_list:
		if player != null and is_instance_valid(player):
			player.set_physics_process(true)

	# Restore previous match simulation speed
	GameManager.set_simulation_speed(_previous_simulation_speed)

	# Reset recording buffer so replay of replay does not accumulate
	_recorded_count = 0

	GameEvents.replay_ended.emit()
	replay_finished.emit(was_skipped)

	var callback: Callable = _on_complete_callback
	_on_complete_callback = Callable()
	if callback.is_valid():
		callback.call()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_replaying:
		return
	if not event.is_pressed() or event.is_echo():
		return

	var is_skip_key: bool = (event is InputEventKey) and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE)
	var is_skip_mouse: bool = (event is InputEventMouseButton) and (event.button_index == MOUSE_BUTTON_LEFT)
	var is_skip_action: bool = event.is_action_pressed(&"action_ui_accept") or event.is_action_pressed(&"action_cancel")

	if is_skip_key or is_skip_mouse or is_skip_action:
		get_viewport().set_input_as_handled()
		skip_replay()

