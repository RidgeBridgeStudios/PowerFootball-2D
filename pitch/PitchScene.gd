##
## PitchScene
##
## Match scene root. It wires the pieces together — ball, players, boundary,
## goals, camera, HUD — and owns restarts: kickoff placement, the pause after a
## goal, and full time. It reacts to GameEvents rather than being called by the
## systems that raise them.
##
## Collision matrix (see shared/CollisionLayers.gd for the authoritative table):
##   1 PitchWorld       walls + goal frames   masks players (2) and ball (3)
##   2 PlayerBodies     player bodies         masks world (1) and players (2)
##   3 BallPhysicsBody  ball body             masks world (1) ONLY
##   4 FootSensorArea   foot Area2D           masks ball (3)
##   5 AerialHitboxZone shoulder Area2D       masks ball (3)
## The ball never masks players: a hard ball/player contact would zero player
## velocity in the move_and_slide solver and flatten the momentum model.
##
## Depends on: GameManager, GameEvents, PitchBoundary, Pseudo3DBall,
##             HeavyPlayerController, PlayerBrain, SetPieceCoordinator,
##             DataLoader, PlayerFactory, RefereeLoader, MatchReferee,
##             ManagerLoader, ManagerData, ManagerDirector, PressOffice,
##             TouchlineBubble.
## Exposes: reset_for_kickoff(), shake_camera(amount)
##

class_name PitchScene
extends Node2D

## Seconds the celebration holds before the ball is placed for the restart.
@export var goal_restart_delay: float = 2.5
## Camera shake decay, in units per second.
@export var shake_decay: float = 6.0
## Maximum camera offset in pixels at full shake.
@export var shake_strength: float = 8.0

## Minimum distance advantage a teammate must have over the controlled player
## before auto-switch fires. Prevents triggering for trivial proximity differences.
const AUTOSWITCH_ADVANTAGE_PX: float = 160.0
## The controlled player must also be at least this far from the ball for
## auto-switch to be considered. If they're close, they're in the right place.
const AUTOSWITCH_MIN_BALL_DIST: float = 200.0
## Seconds before auto-switch can fire again. Stops the switch flickering.
const AUTOSWITCH_COOLDOWN: float = 3.0

var _shake_amount: float = 0.0
var _autoswitch_cooldown_remaining: float = 0.0

## Set by _apply_match_config() from GameManager meta written by KickOffMenu.
## Null means "run standalone from the editor" — team names fall back to
## DataLoader teams 0/1 wherever these are read.
var _selected_home_team: TeamData = null
var _selected_away_team: TeamData = null
var _is_practice_mode: bool = false

@onready var boundary: PitchBoundary = $PitchBoundary
@onready var ball: Pseudo3DBall = $Ball
@onready var players: Node2D = $Players
@onready var camera: Camera2D = $MatchCamera
@onready var restart_timer: Timer = $RestartTimer
@onready var hud: HUD = $HUD
@onready var _set_piece_coordinator: SetPieceCoordinator = $SetPieceCoordinator
@onready var match_referee: MatchReferee = $MatchReferee
@onready var _manager_director_a: ManagerDirector = $ManagerDirectorA
@onready var _manager_director_b: ManagerDirector = $ManagerDirectorB
@onready var _touchline_bubble: TouchlineBubble = $TouchlineBubble

## PressOffice is a RefCounted press-quote generator — never add_child'd, no
## scene tree access.
var _press_office: PressOffice = PressOffice.new()


func _ready() -> void:
	randomize()
	_apply_match_config()

	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.match_ended.connect(_on_match_ended)
	GameEvents.ball_out_of_bounds.connect(_on_ball_out_of_bounds)
	GameEvents.half_time_reached.connect(_on_half_time_reached)
	GameEvents.manager_formation_changed.connect(_on_touchline_shift)
	ball.ball_bounced.connect(_on_ball_bounced)
	restart_timer.timeout.connect(_on_restart_timer_timeout)

	_bind_players()
	_set_piece_coordinator.bind(ball, boundary, players)

	var team_a_name: String = _selected_home_team.team_name if _selected_home_team != null else (DataLoader.get_team(GameManager.TEAM_A).team_name if DataLoader.league != null else "Team A")
	var team_b_name: String = _selected_away_team.team_name if _selected_away_team != null else (DataLoader.get_team(GameManager.TEAM_B).team_name if DataLoader.league != null else "Team B")
	var ref_data: RefereeData = RefereeLoader.get_random_referee()
	match_referee.bind(ref_data, _set_piece_coordinator, team_a_name, team_b_name)

	var manager_a: ManagerData = ManagerLoader.get_or_assign_manager(team_a_name)
	var manager_b: ManagerData = ManagerLoader.get_or_assign_manager(team_b_name)
	_manager_director_a.bind(manager_a, GameManager.TEAM_A, players, boundary)
	_manager_director_b.bind(manager_b, GameManager.TEAM_B, players, boundary)

	reset_for_kickoff()
	GameManager.start_match()
	GameManager.restart_play()


func _process(delta: float) -> void:
	_update_camera(delta)
	if Input.is_action_just_pressed(&"action_switch"):
		switch_to_nearest_teammate()
	_tick_autoswitch(delta)


## Reads match configuration written by MainMenu/KickOffMenu before this scene
## loaded. Falls back to teams 0/1 and non-practice mode, so the scene still
## runs standalone from the editor during development.
func _apply_match_config() -> void:
	if GameManager.has_meta(&"home_team_index") and GameManager.has_meta(&"away_team_index"):
		# TODO: wire these into _bind_players()/PlayerFactory once team
		# selection needs to change which squads actually spawn — for now the
		# selected teams only rename the referee/manager binding below, the
		# scene's own two Player nodes still use team 0/1's squads.
		var home_idx: int = GameManager.get_meta(&"home_team_index")
		var away_idx: int = GameManager.get_meta(&"away_team_index")
		_selected_home_team = DataLoader.get_team(home_idx)
		_selected_away_team = DataLoader.get_team(away_idx)

	_is_practice_mode = GameManager.get_meta(&"practice_mode", false)
	# TODO: practice mode should disable the away team's AI and place the
	# active player at the centre circle facing an empty goal — stubbed until
	# practice has its own pitch setup path.


## Places the ball on the centre spot and returns every player to their
## formation anchor.
##
## TODO: unify with SetPieceCoordinator. Kickoff deliberately stays on this
## older, simpler path rather than being routed through the coordinator: it
## has no "out of bounds" or "foul" trigger to react to, always uses the same
## fixed centre-spot placement, and — unlike the other restarts — happens
## before any players exist to freeze/assign a taker from on the very first
## call. Folding it in would mean special-casing the coordinator for a case it
## does not otherwise need to handle; left as-is until there is a real reason
## (e.g. a kickoff-specific taker/ready-up UI) to share the machinery.
func reset_for_kickoff() -> void:
	ball.reset_at(boundary.get_centre_spot())

	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null:
			continue
		if player.brain != null and player.brain.formation_anchor != Vector2.ZERO:
			player.global_position = player.brain.formation_anchor
		player.velocity = Vector2.ZERO

	var kickoff_team: int = GameManager.TEAM_A
	if GameManager.last_scoring_team >= 0:
		kickoff_team = 1 - GameManager.last_scoring_team
	GameEvents.kickoff_confirmed.emit(kickoff_team)


## Camera feel. Kept here deliberately small.
## TODO: extract into a CameraRig node alongside dynamic zoom (pull out when play
## is stretched, push in near the box) once there are more than two players.
func shake_camera(amount: float) -> void:
	_shake_amount = minf(_shake_amount + amount, 1.0)


func _update_camera(delta: float) -> void:
	# Follow the ball, damped, so the pitch stays readable and the camera never
	# snaps. The high-angle view is otherwise static by design.
	var target: Vector2 = ball.global_position.lerp(boundary.get_centre_spot(), 0.35)
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-3.0 * delta))

	if _shake_amount <= 0.0:
		camera.offset = Vector2.ZERO
		return

	_shake_amount = maxf(_shake_amount - shake_decay * delta * _shake_amount, 0.0)
	var magnitude: float = shake_strength * _shake_amount
	camera.offset = Vector2(randf_range(-magnitude, magnitude), randf_range(-magnitude, magnitude))


func _bind_players() -> void:
	var squad_counts: Dictionary = {}

	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null:
			continue
		player.add_to_group(&"players")
		if player.brain != null:
			player.brain.bind_ball(ball)
			player.brain.bind_boundary(boundary)
		if player.is_user_controlled:
			hud.bind_active_player(player)

		var anchor: Vector2 = player.brain.formation_anchor if player.brain != null else player.global_position
		player.squad_index = squad_counts.get(player.team, 0)
		squad_counts[player.team] = player.squad_index + 1
		PlayerFactory.apply(player, DataLoader.get_player(player.team, player.squad_index), anchor)


## Hands control to whichever teammate is closest to the ball. Control transfers
## wholesale: the player being left behind hands off to its brain, which picks up
## from the exact velocity it was moving at, so a switch never teleports momentum.
func switch_to_nearest_teammate() -> void:
	var current: HeavyPlayerController = hud.active_player
	if current == null:
		return

	var best: HeavyPlayerController = null
	var best_distance: float = INF
	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player == current or player.team != current.team:
			continue
		var distance: float = player.global_position.distance_to(ball.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player

	if best == null:
		return

	current.is_user_controlled = false
	current.movement_intent = Vector2.ZERO
	best.is_user_controlled = true
	hud.bind_active_player(best)
	GameEvents.player_switched.emit(best)


## Switches control away from the current player automatically when a
## teammate is clearly the better candidate to intercept the ball — the
## current player is crowding out of position, not merely not-closest.
func _tick_autoswitch(delta: float) -> void:
	_autoswitch_cooldown_remaining = maxf(_autoswitch_cooldown_remaining - delta, 0.0)
	if _autoswitch_cooldown_remaining > 0.0:
		return
	if not GameManager.is_in_play():
		return

	var current: HeavyPlayerController = hud.active_player
	if current == null:
		return

	# Never auto-switch away from the goalkeeper.
	var current_brain: PlayerBrain = current.brain
	if current_brain != null and current_brain.is_goalkeeper:
		return

	var my_dist: float = current.global_position.distance_to(ball.global_position)

	# Only consider switching if the controlled player is far from the ball.
	if my_dist < AUTOSWITCH_MIN_BALL_DIST:
		return

	# Find the best teammate: closest to ball, same team, not goalkeeper,
	# and must beat the controlled player by at least AUTOSWITCH_ADVANTAGE_PX.
	var best: HeavyPlayerController = null
	var best_dist: float = my_dist - AUTOSWITCH_ADVANTAGE_PX  # Must beat this threshold

	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player == current or player.team != current.team:
			continue
		var pbrain: PlayerBrain = player.brain
		if pbrain != null and pbrain.is_goalkeeper:
			continue
		var d: float = player.global_position.distance_to(ball.global_position)
		if d < best_dist:
			best_dist = d
			best = player

	if best == null:
		return

	# A qualifying teammate exists — auto-switch.
	_autoswitch_cooldown_remaining = AUTOSWITCH_COOLDOWN
	current.is_user_controlled = false
	current.movement_intent = Vector2.ZERO
	best.is_user_controlled = true
	hud.bind_active_player(best)
	GameEvents.player_switched.emit(best)


func _on_goal_scored(scoring_team: int) -> void:
	ball.freeze()
	shake_camera(1.0)
	InputHelper.rumble(0.5, 0.9, 0.35)
	restart_timer.start(goal_restart_delay)
	_fire_touchline_goal_shout(scoring_team)


## The HOME manager's touchline reaction is always shown — whether their team
## scored or conceded. The away manager never gets a goal-reaction bubble; the
## touchline shout is a home-perspective feature.
func _fire_touchline_goal_shout(scoring_team: int) -> void:
	var home_data: ManagerData = _manager_director_a.get_data()
	if home_data == null:
		return

	var ctx := PressOffice.PressContext.new()
	var is_home_team: bool = (scoring_team == GameManager.TEAM_A)
	ctx.event = "touchline_goal" if is_home_team else "touchline_goal_conceded"

	var quote: String = _press_office.generate_quote(home_data, ctx)
	var display_name: String = home_data.manager_name if home_data.manager_name != "" else "Manager"
	_touchline_bubble.show_shout(display_name, quote, true)


func _on_touchline_shift(team: int, _new_formation: String) -> void:
	var director: ManagerDirector = _manager_director_a if team == GameManager.TEAM_A else _manager_director_b
	var data: ManagerData = director.get_data()
	if data == null:
		return

	var is_home: bool = (team == GameManager.TEAM_A)
	var ctx := PressOffice.PressContext.new()
	ctx.event = "touchline_shift"

	var quote: String = _press_office.generate_quote(data, ctx)
	var display_name: String = data.manager_name if data.manager_name != "" else "Manager"
	_touchline_bubble.show_shout(display_name, quote, is_home)


## HOME manager's half-time quote only.
## INTENTIONAL: away team half-time instructions are secret. The player only
## ever controls the home team, so surfacing the away manager's tactical talk
## would hand over information the player is not meant to see.
func _on_half_time_reached() -> void:
	var home_data: ManagerData = _manager_director_a.get_data()
	if home_data == null:
		return

	var ctx := PressOffice.PressContext.new()
	# Reuse "pre_match" context — it generates motivational mid-match
	# instructions cleanly without needing a new context type.
	ctx.event = "pre_match"
	ctx.opponent_name = _selected_away_team.team_name if _selected_away_team != null else ""

	var quote: String = _press_office.generate_quote(home_data, ctx)
	var display_name: String = home_data.manager_name if home_data.manager_name != "" else "Manager"
	_touchline_bubble.show_shout(display_name, quote, true)


func _on_restart_timer_timeout() -> void:
	reset_for_kickoff()
	ball.unfreeze()
	GameManager.kickoff()
	GameManager.restart_play()


func _on_match_ended(winner: int) -> void:
	ball.freeze()
	_log_manager_stats(winner)
	# TODO: full-time screen and a rematch flow; for now the pitch simply stops.


## Writes each team's manager career stats back to ManagerData and persists
## the whole pool. winner is TEAM_A/TEAM_B, or -1 for a draw.
func _log_manager_stats(winner: int) -> void:
	var directors: Array = [_manager_director_a, _manager_director_b]
	for i: int in range(directors.size()):
		var m: ManagerData = directors[i].get_data()
		if m == null:
			continue
		m.matches_managed += 1
		m.goals_scored += GameManager.score[i]
		m.goals_conceded += GameManager.score[1 - i]
		if winner == i:
			m.wins += 1
		elif winner < 0:
			m.draws += 1
		else:
			m.losses += 1
		GameEvents.manager_stats_updated.emit(m)
	ManagerLoader.save_managers()


func _on_ball_out_of_bounds(side: String) -> void:
	ball.freeze()
	_set_piece_coordinator.handle_out_of_bounds(side, ball.global_position, ball.last_touched_by)


func _on_ball_bounced(impact_velocity: float) -> void:
	# Only meaningful impacts shake the frame — a settling ball should not.
	if impact_velocity > 200.0:
		shake_camera(clampf(impact_velocity / 900.0, 0.0, 0.6))
