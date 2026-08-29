##
## SetPieceCoordinator
##
## The single brain for every dead-ball restart except kickoff (see PitchScene
## for why kickoff still runs through its own, simpler path). PitchScene hands
## it out-of-bounds and foul events; it works out which restart applies, freezes
## every player but the taker, places the ball, positions the defending side at
## a legal distance, and waits for the taker to confirm before releasing play.
##
## Deliberately knows nothing about the scene tree beyond what bind() gives it,
## so it can be reasoned about (and later tested) independently of PitchScene's
## layout.
##
## Depends on: GameManager, GameEvents (autoloads), PitchBoundary, Pseudo3DBall,
##             HeavyPlayerController, PlayerState (state name constants).
## Exposes: bind(ball, boundary, players), handle_out_of_bounds(), handle_foul(),
##          get_taker()
##

class_name SetPieceCoordinator
extends Node

## Pixels from the goal line to the penalty spot.
@export var penalty_spot_offset: float = 320.0
## How far the corner ball sits in from the touchline/end-line intersection.
@export var corner_flag_inset: float = 16.0
## Minimum distance defenders are pushed back to for a free kick or penalty.
@export var wall_distance: float = 176.0
## Fallback delay before a set piece auto-activates if nobody confirms it —
## the only path a CPU taker uses, since it never presses action_kick itself.
@export var confirmation_timeout: float = 4.0
## Seconds a CPU taker "thinks" before a set piece auto-activates.
@export var cpu_confirmation_delay: float = 1.0

## Penalty box dimensions, matching Phase 4 of the brief: 320px deep, 400px
## either side of the goal's centre line.
const PENALTY_AREA_DEPTH: float = 320.0
const PENALTY_AREA_HALF_WIDTH: float = 400.0

## How far inside the touchline a throw-in ball is placed, so it does not sit
## on top of the boundary sensor that just fired.
const THROW_IN_INSET: float = 24.0

var _ball: Pseudo3DBall
var _boundary: PitchBoundary
var _players: Node2D

var _current_taker: HeavyPlayerController = null
var _previous_active_player: HeavyPlayerController = null
var _awaiting_confirmation: bool = false

@onready var _confirmation_timer: Timer = $ConfirmationTimer


func _ready() -> void:
	_confirmation_timer.timeout.connect(_on_confirmation_timer_timeout)


func bind(ball: Pseudo3DBall, boundary: PitchBoundary, players: Node2D) -> void:
	_ball = ball
	_boundary = boundary
	_players = players


func _process(_delta: float) -> void:
	if not _awaiting_confirmation or _current_taker == null:
		return
	if _current_taker.is_user_controlled and Input.is_action_just_pressed(&"action_kick"):
		_confirmation_timer.stop()
		_activate_set_piece()


func get_taker() -> HeavyPlayerController:
	return _current_taker


## side: "touchline_top" / "touchline_bottom" / "end_line_goal_kick" / "end_line_corner"
## (see PitchBoundary._on_ball_crossed_boundary for how the side/attacker split
## is decided). last_toucher may be null if nobody touched the ball last.
func handle_out_of_bounds(side: String, exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void:
	if _boundary == null or _ball == null or _players == null:
		return

	match side:
		"touchline_top", "touchline_bottom":
			_start_throw_in(exit_pos, last_toucher)
		"end_line_goal_kick":
			_start_goal_kick(exit_pos, last_toucher)
		"end_line_corner":
			_start_corner_kick(exit_pos, last_toucher)


func handle_foul(fouler: HeavyPlayerController, victim: HeavyPlayerController, foul_pos: Vector2) -> void:
	if _boundary == null or fouler == null or victim == null:
		return

	var attacking_team: int = victim.team
	var defending_team: int = fouler.team

	if _is_in_penalty_area(foul_pos, defending_team):
		_start_penalty(attacking_team, defending_team)
	else:
		_start_free_kick(attacking_team, foul_pos)


## --- Restart setup -----------------------------------------------------------

func _start_throw_in(exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void:
	var team: int = _opposing_team_of(last_toucher)
	var rect: Rect2 = _boundary.get_pitch_rect()
	var clamped_x: float = clampf(exit_pos.x, rect.position.x, rect.position.x + rect.size.x)
	# A hair inside the line rather than exactly on it, so the placed ball does
	# not sit inside the touchline sensor and immediately retrigger it.
	var touchline_y: float = (
		rect.position.y + THROW_IN_INSET
		if exit_pos.y < _boundary.get_centre_spot().y
		else rect.position.y + rect.size.y - THROW_IN_INSET
	)
	var position: Vector2 = Vector2(clamped_x, touchline_y)

	_begin_set_piece(GameManager.MatchPhase.THROW_IN, team, position)


func _start_goal_kick(exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void:
	# The attacker's own team touched it last, so the defending team gets the kick.
	var defending_team: int = _opposing_team_of(last_toucher)
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var inward: float = 1.0 if defending_team == 0 else -1.0
	var side_sign: float = 1.0 if exit_pos.y >= _boundary.get_centre_spot().y else -1.0
	var position: Vector2 = goal_centre + Vector2(inward * 150.0, side_sign * 80.0)

	_begin_set_piece(GameManager.MatchPhase.GOAL_KICK, defending_team, position)


func _start_corner_kick(exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void:
	# The defender touched it last, so the attacking team (the opponent of
	# whichever goal this end line belongs to) gets the corner.
	var defending_team: int = last_toucher.team if last_toucher != null else 0
	var attacking_team: int = 1 - defending_team
	var half: Vector2 = _boundary.pitch_size * 0.5
	var centre: Vector2 = _boundary.get_centre_spot()
	var x_sign: float = 1.0 if exit_pos.x >= centre.x else -1.0
	var y_sign: float = 1.0 if exit_pos.y >= centre.y else -1.0
	var position: Vector2 = centre + Vector2(
		x_sign * (half.x - corner_flag_inset),
		y_sign * (half.y - corner_flag_inset),
	)

	_begin_set_piece(GameManager.MatchPhase.CORNER_KICK, attacking_team, position)


func _start_free_kick(team: int, foul_pos: Vector2) -> void:
	GameManager.start_free_kick(team, foul_pos, true)
	_setup_taking_side(GameManager.MatchPhase.FREE_KICK, team, foul_pos)
	_build_defensive_wall(foul_pos, 1 - team)


## Public entry point for the Practice Arena. Computes the penalty spot for
## `defending_team`'s goal and runs the full penalty setup.
func start_penalty_for_practice(attacking_team: int, defending_team: int) -> void:
	_start_penalty(attacking_team, defending_team)


func _start_penalty(attacking_team: int, defending_team: int) -> void:
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var attack_direction: float = 1.0 if defending_team == 0 else -1.0
	var position: Vector2 = goal_centre + Vector2(penalty_spot_offset * attack_direction, 0.0)

	GameManager.start_penalty(attacking_team, position)
	_setup_taking_side(GameManager.MatchPhase.PENALTY_KICK, attacking_team, position)


## Shared setup for the three restarts whose GameManager call only needs
## (phase, team, position) — throw-ins, goal kicks and corners.
func _begin_set_piece(phase: int, team: int, position: Vector2) -> void:
	GameManager.start_set_piece(phase, team, position)
	_setup_taking_side(phase, team, position)


## Common tail of every restart: freeze the pitch, park the ball, pick a taker,
## push the opposition back, and wait for the go-ahead.
func _setup_taking_side(phase: int, team: int, position: Vector2) -> void:
	_freeze_all_players()
	_ball.reset_at(position)
	_assign_taker(team)
	_position_defending_players(phase)
	_await_taker_confirmation()


## --- Player handling ----------------------------------------------------------

func _freeze_all_players() -> void:
	_previous_active_player = null
	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null:
			continue
		if player.is_user_controlled:
			_previous_active_player = player
		player.is_user_controlled = false
		player.movement_intent = Vector2.ZERO
		player.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)


func _assign_taker(team: int) -> void:
	var spot: Vector2 = GameManager.set_piece_position
	var best: HeavyPlayerController = null
	var best_distance: float = INF

	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player.team != team:
			continue
		var distance: float = player.global_position.distance_to(spot)
		if distance < best_distance:
			best_distance = distance
			best = player

	_current_taker = best
	if _current_taker == null:
		return

	_current_taker.global_position = spot
	_current_taker.velocity = Vector2.ZERO
	_current_taker.state_factory.transition_to(PlayerState.IDLE)

	# The taker is human-controlled only when the set piece belongs to the
	# team the human was already controlling; otherwise it stays a CPU restart
	# and control returns to the human's own player once play resumes.
	if _previous_active_player != null and _previous_active_player.team == team:
		_current_taker.is_user_controlled = true
		# Reuse the existing player-switch channel so the HUD (power meter,
		# stamina bar) and action_switch follow the new controlled player
		# rather than going stale on whoever it was tracking before.
		GameEvents.player_switched.emit(_current_taker)


## Moves opposing CPU players back to a legal distance. Full wall-building
## tactics are out of scope (see _build_defensive_wall) — this only guarantees
## nobody stands on top of the ball.
func _position_defending_players(phase: int) -> void:
	if _current_taker == null:
		return

	var defending_team: int = 1 - _current_taker.team
	var spot: Vector2 = GameManager.set_piece_position
	var min_distance: float = wall_distance
	if phase == GameManager.MatchPhase.CORNER_KICK or phase == GameManager.MatchPhase.GOAL_KICK:
		min_distance = penalty_spot_offset

	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player.team != defending_team or player == _current_taker:
			continue
		var offset: Vector2 = player.global_position - spot
		if offset.length() >= min_distance:
			continue
		var direction: Vector2 = offset.normalized() if offset.length() > 0.001 else Vector2.RIGHT
		player.global_position = spot + direction * min_distance


## --- Confirmation and activation ----------------------------------------------

func _await_taker_confirmation() -> void:
	if _current_taker == null:
		return
	_awaiting_confirmation = true
	var delay: float = confirmation_timeout if _current_taker.is_user_controlled else cpu_confirmation_delay
	_confirmation_timer.start(delay)


func _on_confirmation_timer_timeout() -> void:
	if _awaiting_confirmation:
		_activate_set_piece()


func _activate_set_piece() -> void:
	_awaiting_confirmation = false
	if _current_taker == null:
		return

	_ball.reset_at(GameManager.set_piece_position)
	_ball.unfreeze()

	_current_taker.state_factory.state_changed.connect(_on_taker_state_changed)

	match GameManager.current_phase:
		GameManager.MatchPhase.THROW_IN:
			_current_taker.state_factory.transition_to(PlayerState.THROW_IN)
		GameManager.MatchPhase.PENALTY_KICK:
			_current_taker.state_factory.transition_to(PlayerState.PENALTY_KICK)
		_:
			_current_taker.state_factory.transition_to(PlayerState.CHARGE_KICK)


## Fires once the taker's kicking state hands off (ball struck or thrown),
## rather than at the moment we force them into it — that is the point at
## which the set piece has actually been "taken".
func _on_taker_state_changed(from_state: StringName, _to_state: StringName) -> void:
	var taking_states: Array[StringName] = [PlayerState.CHARGE_KICK, PlayerState.THROW_IN, PlayerState.PENALTY_KICK]
	if not taking_states.has(from_state):
		return

	_current_taker.state_factory.state_changed.disconnect(_on_taker_state_changed)
	GameEvents.set_piece_taken.emit(_current_taker)
	GameManager.restart_play()

	if not _current_taker.is_user_controlled and _previous_active_player != null and is_instance_valid(_previous_active_player):
		_previous_active_player.is_user_controlled = true
		GameEvents.player_switched.emit(_previous_active_player)

	_current_taker = null


## --- Penalty area -------------------------------------------------------------

func _is_in_penalty_area(pos: Vector2, defending_team: int) -> bool:
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var direction: float = 1.0 if defending_team == 0 else -1.0
	var local: Vector2 = pos - goal_centre
	var depth: float = local.x * direction

	return depth >= 0.0 and depth <= PENALTY_AREA_DEPTH and absf(local.y) <= PENALTY_AREA_HALF_WIDTH


## --- Defensive wall (scaffold only) --------------------------------------------

func _build_defensive_wall(free_kick_pos: Vector2, _defending_team: int) -> void:
	## TODO: select the 2-4 nearest defenders of defending_team, position them
	## wall_distance pixels from free_kick_pos along the kick direction vector,
	## spaced 60px apart perpendicular to that vector. _position_defending_players()
	## already pushes them back to a legal distance in a straight line from the
	## ball; this needs to additionally line them up between the ball and goal.
	## For now: emit the signal so the HUD can still show the wall-building hint.
	GameEvents.defensive_wall_requested.emit(free_kick_pos)


func _opposing_team_of(player: HeavyPlayerController) -> int:
	if player == null:
		return 0
	return 1 - player.team
