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
##             MatchOfficialCrew, OffsideDetector, ManagerLoader, ManagerData,
##             ManagerDirector, PressOffice, TouchlineBubble, Minimap.
## Exposes: reset_for_kickoff(kickoff_team), shake_camera(amount)
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
## Seconds the pitch pauses between halves.
const HALF_TIME_DURATION: float = 5.0

const MatchStatsScene: PackedScene = preload("res://ui/MatchStatsUI.tscn")

var _shake_amount: float = 0.0
var _autoswitch_cooldown_remaining: float = 0.0

## Practice Arena runtime state. All null / false outside practice mode.
var _practice_human: HeavyPlayerController = null
var _practice_keeper: HeavyPlayerController = null
var _practice_gk_frozen: bool = false
var _practice_goal_pending: bool = false
var _practice_goal_timer: float = 0.0
## Seconds before the ball auto-resets after a goal in practice.
const PRACTICE_GOAL_RESET_DELAY: float = 1.5
## Pixels the frozen GK's spawn/reset spot sits inside the goal mouth, so they
## start on the line rather than behind the end wall.
const PRACTICE_KEEPER_LINE_OFFSET: float = 48.0

## Set by _apply_match_config() from GameManager meta written by KickOffMenu.
## Null means "run standalone from the editor" — team names fall back to
## DataLoader teams 0/1 wherever these are read.
var _selected_home_team: TeamData = null
var _selected_away_team: TeamData = null
var _is_practice_mode: bool = false

## Headless simulation harness state
var _is_headless_simulation: bool = false
var _sim_duration: float = 60.0
var _sim_output_json: String = "eval_report.json"
var _sim_ticks: int = 0
var _sim_elapsed: float = 0.0
var _sim_nan_inf_count: int = 0
var _sim_boundary_escape_count: int = 0
var _sim_ai_cadence_violations: int = 0
var _sim_anchor_samples: Array[float] = []

@onready var boundary: PitchBoundary = $PitchBoundary
@onready var ball: Pseudo3DBall = $Ball
@onready var players: Node2D = $Players
@onready var camera: Camera2D = $MatchCamera
@onready var restart_timer: Timer = $RestartTimer
@onready var hud: HUD = $HUD
@onready var _set_piece_coordinator: SetPieceCoordinator = $SetPieceCoordinator
@onready var _penalty_shootout_coordinator: PenaltyShootoutCoordinator = $PenaltyShootoutCoordinator
@onready var match_referee: MatchReferee = $MatchReferee
@onready var match_official_crew: MatchOfficialCrew = $MatchOfficialCrew
@onready var _offside_detector: OffsideDetector = $OffsideDetector
@onready var _manager_director_a: ManagerDirector = $ManagerDirectorA
@onready var _manager_director_b: ManagerDirector = $ManagerDirectorB
@onready var _touchline_bubble: TouchlineBubble = $TouchlineBubble
@onready var minimap: Minimap = $Minimap/MapArea
@onready var pregame: PreGameScreen = $PreGameScreen
@onready var pause_menu: PauseMenu = $PauseMenu

## Working lineup/formation data for the pause menu. Built once the pre-game
## screen confirms; null in practice mode, where neither UI is shown.
var _mgmt_a: TeamManagementData = null
var _mgmt_b: TeamManagementData = null
## The human-controlled player whose input is suspended while the pause menu
## is open — see _open_pause_menu() for why this, rather than the
## MatchPhase guard alone, is what actually stops them moving.
var _paused_human: HeavyPlayerController = null

## PressOffice is a RefCounted press-quote generator — never add_child'd, no
## scene tree access.
var _press_office: PressOffice = PressOffice.new()

## Goalkeeper dive commitment. One brain per match (the RNG is seeded once), one
## coordinator wiring ball_struck → dive decision → GoalkeeperDiveState transition.
var _gk_dive_brain: GoalkeeperDiveBrain = GoalkeeperDiveBrain.new()

## Momentum reading last received for the home team — see
## _on_team_momentum_updated(). Used to detect a sharp swing since the
## previous broadcast, not the raw value itself.
var _last_home_momentum: float = 0.0
## |delta| in home team momentum, since the last broadcast, that counts as a
## swing sharp enough to voice a touchline reaction.
const MOMENTUM_SWING_THRESHOLD: float = 0.35


func _ready() -> void:
	randomize()
	_apply_match_config()

	if not GameEvents.substitution_made.is_connected(_on_substitution_made):
		GameEvents.substitution_made.connect(_on_substitution_made)

	if _is_practice_mode:
		_setup_practice_arena()
	else:
		_setup_normal_match()


## The full-match setup path. Everything that used to run straight through in
## _ready() now waits behind the pre-game screen: it shows the lineup/formation
## UI first and defers the rest — including GameManager.start_match() — to
## _on_pregame_confirmed(), fired once via GameEvents.pregame_confirmed.
func _setup_normal_match() -> void:
	if _is_headless_simulation:
		_on_pregame_confirmed()
		return
	pregame.setup()
	pregame.show()
	GameEvents.pregame_confirmed.connect(_on_pregame_confirmed, CONNECT_ONE_SHOT)
	GameEvents.pause_closed.connect(_on_pause_closed)


## Everything the original _setup_normal_match() body did, now deferred until
## the player has set lineups/formations on the pre-game screen and confirmed.
func _on_pregame_confirmed() -> void:
	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.match_ended.connect(_on_match_ended)
	GameEvents.ball_out_of_bounds.connect(_on_ball_out_of_bounds)
	GameEvents.half_time_reached.connect(_on_half_time_reached)
	GameEvents.manager_formation_changed.connect(_on_touchline_shift)
	GameEvents.team_momentum_updated.connect(_on_team_momentum_updated)
	ball.ball_bounced.connect(_on_ball_bounced)
	## FIX: Guards against a broken $RestartTimer node path — a null timer here
	## would otherwise defer every post-goal kickoff to Change 1's fallback path
	## silently; this surfaces the misconfiguration immediately.
	if restart_timer == null:
		push_error("PitchScene: $RestartTimer is null — kickoff after goals will use fallback path.")
	else:
		## FIX: Guards against a double-connection if _on_pregame_confirmed ever
		## fires more than once (it is a one-shot today, but defensive wiring is
		## cheaper than a duplicated restart firing two kickoffs).
		if not restart_timer.timeout.is_connected(_on_restart_timer_timeout):
			restart_timer.timeout.connect(_on_restart_timer_timeout)

	_bind_players()
	MatchStatsTracker.init_players()
	_bind_camera(hud.active_player)
	_set_piece_coordinator.bind(ball, boundary, players)
	_offside_detector.bind(boundary, _set_piece_coordinator)
	_penalty_shootout_coordinator.bind(_set_piece_coordinator, ball, boundary)

	_setup_goalkeeper_dive_coordinator()

	var team_names: Array[String] = _resolve_team_names()
	var team_a_name: String = team_names[0]
	var team_b_name: String = team_names[1]
	hud.set_team_names(team_a_name, team_b_name)
	var ref_data: RefereeData = RefereeLoader.get_random_referee()
	match_referee.bind(ref_data, _set_piece_coordinator, team_a_name, team_b_name)
	if match_official_crew != null:
		match_official_crew.bind(boundary, ref_data)

	var manager_a: ManagerData = ManagerLoader.get_or_assign_manager(team_a_name)
	var manager_b: ManagerData = ManagerLoader.get_or_assign_manager(team_b_name)
	_manager_director_a.bind(manager_a, GameManager.TEAM_A, players, boundary)
	_manager_director_b.bind(manager_b, GameManager.TEAM_B, players, boundary)

	_mgmt_a = TeamManagementData.from_team(DataLoader.get_match_team(GameManager.TEAM_A), manager_a)
	_mgmt_b = TeamManagementData.from_team(DataLoader.get_match_team(GameManager.TEAM_B), manager_b)

	reset_for_kickoff(GameManager.TEAM_A)
	GameManager.start_match()
	# Instead of restart_play() in the same breath (which collapsed
	# KICKOFF → IN_PLAY before any player could freeze), route the very first
	# kickoff through the same ceremony as every post-goal restart: KICKOFF is
	# already the phase (start_match() sets it), and the coordinator freezes
	# everyone, assigns TEAM_A's taker, and only resumes play once the ball is
	# actually kicked.
	_set_piece_coordinator.start_kickoff(GameManager.TEAM_A)


## Practice Arena setup: strips the pitch down to one human attacker and one
## goalkeeper, places them, and wires only the practice-specific handlers —
## none of the full-match ceremony (referee, managers, kickoff, half/full time).
func _setup_practice_arena() -> void:
	_bind_players()
	await get_tree().process_frame

	var team_a_players: Array[HeavyPlayerController] = []
	var team_b_players: Array[HeavyPlayerController] = []
	for node: Node in players.get_children():
		var p := node as HeavyPlayerController
		if p == null:
			continue
		if p.team == GameManager.TEAM_A:
			team_a_players.append(p)
		elif p.team == GameManager.TEAM_B:
			team_b_players.append(p)

	var human_player: HeavyPlayerController = null
	for p: HeavyPlayerController in team_a_players:
		if p.is_user_controlled:
			human_player = p
			break
	if human_player == null and team_a_players.size() > 0:
		human_player = team_a_players[0]

	var keeper_player: HeavyPlayerController = null
	for p: HeavyPlayerController in team_b_players:
		if p.brain != null and p.brain.is_goalkeeper:
			keeper_player = p
			break
	if keeper_player == null and team_b_players.size() > 0:
		keeper_player = team_b_players[0]

	if human_player == null or keeper_player == null:
		push_error("PracticeArena: could not identify human or goalkeeper. Aborting.")
		return

	# Free every other spawned player. A Dictionary keyed by node stands in for
	# a Set so a duplicate never gets queue_free()'d twice.
	var to_free: Dictionary = {}
	for node: Node in players.get_children():
		var extra_player := node as HeavyPlayerController
		if extra_player == null or extra_player == human_player or extra_player == keeper_player:
			continue
		to_free[extra_player] = true
	for doomed_player: HeavyPlayerController in to_free.keys():
		if is_instance_valid(doomed_player):
			doomed_player.queue_free()

	await get_tree().process_frame

	if not is_instance_valid(human_player) or not is_instance_valid(keeper_player):
		push_error("PracticeArena: human or goalkeeper freed unexpectedly. Aborting.")
		return

	human_player.is_user_controlled = true
	var keeper_brain: PlayerBrain = keeper_player.brain
	if keeper_brain != null:
		keeper_brain.is_goalkeeper = true
		keeper_brain.formation_anchor = boundary.get_goal_centre(GameManager.TEAM_B)

	_practice_human = human_player
	_practice_keeper = keeper_player

	_practice_human.global_position = boundary.get_centre_spot()
	_practice_human.velocity = Vector2.ZERO

	_practice_keeper.global_position = _practice_keeper_spot()
	_practice_keeper.velocity = Vector2.ZERO

	ball.reset_at(boundary.get_centre_spot())
	ball.unfreeze()

	# No start_match(): that would reset the score, fire kickoff_started (the
	# referee banner), and start the clock before the GameManager practice
	# guard even runs. restart_play() alone is enough to get FSMs ticking.
	GameManager.restart_play()

	_set_piece_coordinator.bind(ball, boundary, players)

	if match_official_crew != null:
		match_official_crew.hide()
		match_official_crew.process_mode = Node.PROCESS_MODE_DISABLED

	hud.bind_active_player(_practice_human)
	hud.enter_practice_mode()
	GameEvents.player_switched.emit(_practice_human)
	_bind_camera(_practice_human)

	# Practice-only handlers. The normal _on_goal_scored/_on_ball_out_of_bounds
	# are deliberately never connected here — they'd run a full kickoff ceremony.
	GameEvents.goal_scored.connect(_on_practice_goal_scored)
	GameEvents.ball_out_of_bounds.connect(_on_practice_out_of_bounds)
	restart_timer.timeout.connect(_on_practice_restart_timeout)


## World spot for the practice keeper: on TEAM_B's goal line, offset inward
## (toward the centre spot) so they stand in the mouth rather than behind it.
func _practice_keeper_spot() -> Vector2:
	var goal_centre: Vector2 = boundary.get_goal_centre(GameManager.TEAM_B)
	var direction: float = -1.0 if GameManager.TEAM_B == 0 else 1.0
	return goal_centre - Vector2(direction * PRACTICE_KEEPER_LINE_OFFSET, 0.0)


## Only wired up for a full match — practice mode never shows either UI, so
## the pregame/pause_menu nodes stay hidden and _mgmt_a/_mgmt_b stay null there.
func _input(event: InputEvent) -> void:
	if _is_practice_mode or _mgmt_a == null:
		return
	if event.is_action_pressed(&"ui_pause") and GameManager.is_in_play():
		_open_pause_menu()
		get_viewport().set_input_as_handled()


## Opens the pause menu and freezes physics. GameManager.set_phase() away from
## IN_PLAY is what stops PlayerBrain and MoodSystem acting on every CPU player
## (both already guard on GameManager.is_in_play()); it does nothing for the
## human-controlled player, whose _physics_process reads raw input regardless
## of match phase, so that player is additionally handed to the CPU guard by
## flipping is_user_controlled off for the duration of the pause. The ball has
## no such guard either — same as a goal celebration or half time, it is
## stopped with an explicit freeze() rather than a phase check.
func _open_pause_menu() -> void:
	_paused_human = hud.active_player
	if is_instance_valid(_paused_human):
		_paused_human.is_user_controlled = false
	ball.freeze()
	GameManager.set_phase(GameManager.MatchPhase.PREGAME)
	pause_menu.open(_mgmt_a, _mgmt_b)


func _on_pause_closed() -> void:
	if is_instance_valid(_paused_human):
		_paused_human.is_user_controlled = true
	_paused_human = null
	ball.unfreeze()
	GameManager.set_phase(GameManager.MatchPhase.IN_PLAY)


## --- Goalkeeper dive commitment ---------------------------------------------
## One brain instance seeded once per match; ball_struck routes every shot to a
## one-way dive decision for the opposing goalkeeper. Disconnected at full time
## so Practice Arena (which never reaches _on_match_ended) still never double-
## connects on a rematch — and _on_pregame_confirmed is a one-shot.

func _setup_goalkeeper_dive_coordinator() -> void:
	_gk_dive_brain.initialise(randi())
	if not GameEvents.ball_struck.is_connected(_on_ball_struck_for_dive):
		GameEvents.ball_struck.connect(_on_ball_struck_for_dive)


func _teardown_goalkeeper_dive_coordinator() -> void:
	if GameEvents.ball_struck.is_connected(_on_ball_struck_for_dive):
		GameEvents.ball_struck.disconnect(_on_ball_struck_for_dive)


func _on_ball_struck_for_dive(_shooter: Node, _speed: float, _charge_ratio: float, is_shot: bool) -> void:
	if not is_shot:
		return

	# The shooter carries the attacking team; the opposing keeper defends it.
	var shooter := _shooter as HeavyPlayerController
	if shooter == null:
		return
	var opp_team: int = 1 - shooter.team

	# The signal is fired by the kick states directly after apply_kick(), but it
	# carries no ball reference — resolve the live ball from the world model.
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or world.ball_node == null:
		return
	var match_ball: Pseudo3DBall = world.ball_node
	if not is_instance_valid(match_ball):
		return

	var keeper: HeavyPlayerController = _find_goalkeeper(opp_team)
	if keeper == null:
		return

	var shot_velocity: Vector2 = match_ball.velocity
	if shot_velocity.x == 0.0:
		return

	var goal_line_x: float = boundary.get_goal_centre(opp_team).x
	var direction: Vector2 = _gk_dive_brain.decide_dive(keeper, match_ball, shot_velocity, goal_line_x)
	if direction == Vector2.ZERO:
		return

	var dive_state: GoalkeeperDiveState = \
		keeper.state_factory.get_state(PlayerState.GOALKEEPER_DIVE) as GoalkeeperDiveState
	if dive_state == null:
		return
	dive_state.dive_direction = direction
	keeper.state_factory.transition_to(PlayerState.GOALKEEPER_DIVE)


## The goalkeeper on `team`, resolved from the world model cache — no scene-tree
## polling. Every read is is_instance_valid()-guarded (Practice Arena frees
## players mid-match).
func _find_goalkeeper(team: int) -> HeavyPlayerController:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return null
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var p: HeavyPlayerController = world.player_nodes[i]
		if p == null or not is_instance_valid(p):
			continue
		if world.player_teams[i] != team:
			continue
		if p.brain != null and p.brain.is_goalkeeper:
			return p
	return null


func _process(delta: float) -> void:
	if _is_headless_simulation:
		_tick_headless_telemetry(delta)
		return

	_update_camera(delta)
	if _is_practice_mode:
		_tick_practice(delta)
	else:
		# During a free kick or penalty, SetPieceCoordinator owns action_switch
		# itself (cycling the taker) — see SetPieceCoordinator.can_switch_taker().
		# Deferring here instead of letting both handlers read the same
		# just-pressed input keeps the HUD's active player and the
		# coordinator's taker from disagreeing about who is controlled.
		var taker_switch_phase: bool = (
			GameManager.current_phase == GameManager.MatchPhase.FREE_KICK
			or GameManager.current_phase == GameManager.MatchPhase.PENALTY_KICK
		)
		if not taker_switch_phase and Input.is_action_just_pressed(&"action_switch"):
			switch_to_nearest_teammate()
		_tick_autoswitch(delta)


func _tick_practice(delta: float) -> void:
	if _practice_goal_pending:
		_practice_goal_timer -= delta
		if _practice_goal_timer <= 0.0:
			_practice_goal_pending = false
			_do_practice_reset()
		return  # Block all other input during the post-goal reset countdown.

	if not GameManager.is_in_play():
		return

	# SetPieceFreezeState.process() hands itself back to Idle the instant
	# GameManager.is_in_play() is true — which it always is during a practice
	# rally — so a one-shot transition_to() would unfreeze the GK within a
	# single frame. Re-asserting it every tick is what actually holds it.
	_hold_gk_freeze()

	if Input.is_action_just_pressed(&"action_practice_reset"):
		_do_practice_reset()

	if Input.is_action_just_pressed(&"action_practice_freekick"):
		_do_practice_freekick()

	if Input.is_action_just_pressed(&"action_practice_penalty"):
		_do_practice_penalty()

	# action_through is repurposed as the GK toggle in practice: there are no
	# teammates to pass to, so its normal binding is unused here.
	if Input.is_action_just_pressed(&"action_through"):
		_do_practice_toggle_gk()


func _hold_gk_freeze() -> void:
	if not _practice_gk_frozen or not is_instance_valid(_practice_keeper):
		return
	_practice_keeper.velocity = Vector2.ZERO
	_practice_keeper.movement_intent = Vector2.ZERO
	if _practice_keeper.state_factory.current_state_name != PlayerState.SET_PIECE_FREEZE:
		_practice_keeper.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)


func _do_practice_reset() -> void:
	ball.unfreeze()
	ball.reset_at(boundary.get_centre_spot())

	if is_instance_valid(_practice_human):
		_practice_human.global_position = boundary.get_centre_spot()
		_practice_human.velocity = Vector2.ZERO
		_practice_human.movement_intent = Vector2.ZERO

	if is_instance_valid(_practice_keeper):
		_practice_keeper.global_position = _practice_keeper_spot()
		_practice_keeper.velocity = Vector2.ZERO
		_practice_keeper.movement_intent = Vector2.ZERO
		if _practice_gk_frozen:
			_practice_keeper.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)
		else:
			_practice_keeper.state_factory.transition_to(PlayerState.IDLE)

	GameManager.restart_play()


func _do_practice_freekick() -> void:
	# Fabricates a foul: the keeper "fouled" the human at the ball's current
	# position. handle_foul() itself decides free kick vs. penalty depending
	# on whether that position is inside TEAM_B's penalty area.
	if not is_instance_valid(_practice_keeper) or not is_instance_valid(_practice_human):
		return
	_set_piece_coordinator.handle_foul(_practice_keeper, _practice_human, ball.global_position)


func _do_practice_penalty() -> void:
	_set_piece_coordinator.start_penalty_for_practice(GameManager.TEAM_A, GameManager.TEAM_B)


func _do_practice_toggle_gk() -> void:
	if not is_instance_valid(_practice_keeper):
		return
	_practice_gk_frozen = not _practice_gk_frozen
	if _practice_gk_frozen:
		_practice_keeper.movement_intent = Vector2.ZERO
		_practice_keeper.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)
	else:
		_practice_keeper.state_factory.transition_to(PlayerState.IDLE)
	hud.set_practice_gk_label(_practice_gk_frozen)


func _on_practice_goal_scored(_team: int, _scorer: Node = null) -> void:
	ball.freeze()
	shake_camera(1.0)
	InputHelper.rumble(0.35, 0.7, 0.25)
	_practice_goal_pending = true
	_practice_goal_timer = PRACTICE_GOAL_RESET_DELAY
	# No restart_timer.start() here — _tick_practice() drives the delay itself.


func _on_practice_out_of_bounds(_side: String) -> void:
	# Any out-of-bounds in practice is a soft reset to centre — never routed
	# through SetPieceCoordinator.handle_out_of_bounds().
	ball.unfreeze()
	ball.reset_at(boundary.get_centre_spot())
	GameManager.restart_play()


func _on_practice_restart_timeout() -> void:
	ball.unfreeze()
	GameManager.restart_play()


## Reads match configuration written by MainMenu/KickOffMenu before this scene
## loaded, as well as CLI headless arguments. Falls back to teams 0/1 and
## non-practice mode, so the scene still runs standalone from the editor.
func _apply_match_config() -> void:
	var cmd_args: PackedStringArray = OS.get_cmdline_args()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in cmd_args:
		if arg == "--run-simulation":
			_is_headless_simulation = true
		elif arg.begins_with("--duration="):
			_sim_duration = arg.trim_prefix("--duration=").to_float()
		elif arg.begins_with("--output-json="):
			_sim_output_json = arg.trim_prefix("--output-json=")
	for arg: String in user_args:
		if arg == "--run-simulation":
			_is_headless_simulation = true
		elif arg.begins_with("--duration="):
			_sim_duration = arg.trim_prefix("--duration=").to_float()
		elif arg.begins_with("--output-json="):
			_sim_output_json = arg.trim_prefix("--output-json=")

	if GameManager.has_meta(&"run_simulation") and bool(GameManager.get_meta(&"run_simulation")):
		_is_headless_simulation = true
	if _is_headless_simulation:
		GameManager.set_meta(&"simulate_match", true)

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


## Shared by _on_pregame_confirmed() (HUD/referee binding) and _on_match_ended()
## (the stats screen) so both read the exact same fallback chain.
func _resolve_team_names() -> Array[String]:
	var team_a_name: String = _selected_home_team.team_name if _selected_home_team != null else (DataLoader.get_team(GameManager.TEAM_A).team_name if DataLoader.league != null else "Team A")
	var team_b_name: String = _selected_away_team.team_name if _selected_away_team != null else (DataLoader.get_team(GameManager.TEAM_B).team_name if DataLoader.league != null else "Team B")
	return [team_a_name, team_b_name]


## Places the ball on the centre spot and returns every player to their
## formation anchor, then emits kickoff_confirmed so the manager directors
## recompute the formation anchors (this is what makes an end swap stick).
## `kickoff_team` is resolved ONCE by the caller and passed in; this function
## never reads GameManager.last_scoring_team. The caller must have entered
## KICKOFF first (GameManager.kickoff() / start_match()) so the phase is
## already correct while the signal handlers run.
## The actual freeze → taker → confirm → kick flow now lives in
## SetPieceCoordinator.start_kickoff(); the coordinator owns ending the dead
## ball via _on_taker_state_changed() once the ball has actually been struck,
## so reset_for_kickoff() never resumes play itself.
func reset_for_kickoff(kickoff_team: int) -> void:
	ball.reset_at(boundary.get_centre_spot())

	# Emit first: ManagerDirector._on_kickoff_confirmed() re-computes every
	# brain's formation_anchor from the (already mirrored, for the second half)
	# formation layout, so the reposition loop below must read the fresh
	# anchors after the emit — not the stale ones from before the swap.
	# Phase is already KICKOFF here: the caller ran GameManager.kickoff().
	GameEvents.kickoff_confirmed.emit(kickoff_team)

	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null:
			continue
		player.global_position = player.brain.formation_anchor
		player.velocity = Vector2.ZERO
		player.movement_intent = Vector2.ZERO
		player.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)


## Camera feel. Kept here deliberately small.
func shake_camera(amount: float) -> void:
	_shake_amount = minf(_shake_amount + amount, 1.0)


## Position and zoom are owned by MatchCamera.gd (the three-mode controller
## bound in _bind_camera()); this only layers screen-shake on top via offset,
## which MatchCamera never touches.
func _update_camera(delta: float) -> void:
	if _shake_amount <= 0.0:
		camera.offset = Vector2.ZERO
		return

	_shake_amount = maxf(_shake_amount - shake_decay * delta * _shake_amount, 0.0)
	var magnitude: float = shake_strength * _shake_amount
	camera.offset = Vector2(randf_range(-magnitude, magnitude), randf_range(-magnitude, magnitude))


## Wires MatchCamera to the ball, pitch bounds, and the currently human-
## controlled player, and keeps the human reference current across
## GameEvents.player_switched so DYNAMIC/BALL_FOLLOW keep tracking the right
## player after a switch.
func _bind_camera(human: HeavyPlayerController) -> void:
	var cam := camera as MatchCamera
	if cam == null:
		return

	cam.bind_ball(ball)
	cam.bind_human_player(human)
	cam.bind_pitch(boundary)

	if not cam.camera_mode_changed.is_connected(hud.set_camera_mode_label):
		cam.camera_mode_changed.connect(hud.set_camera_mode_label)
	hud.set_camera_mode_label(cam.get_mode_name())

	if not GameEvents.player_switched.is_connected(_on_player_switched_for_camera):
		GameEvents.player_switched.connect(_on_player_switched_for_camera)


## GameEvents.player_switched carries a plain Node; MatchCamera.bind_human_player
## wants a Node2D, so this narrows it rather than connecting the signal straight
## to the bind method.
func _on_player_switched_for_camera(new_player: Node) -> void:
	var cam := camera as MatchCamera
	if cam != null:
		cam.bind_human_player(new_player as Node2D)


func _bind_players() -> void:
	# Players register themselves into MatchWorldModel from their own _ready()
	# (they are declared as children of $Players in the scene, so there is no
	# spawn loop to number them). The ball has no such hook, so the pitch hands
	# it over here — before any brain runs a decision tick.
	if MatchWorldModel.instance != null:
		MatchWorldModel.instance.register_ball(ball)
		MatchWorldModel.instance.bind_boundary(boundary)

	var squad_counts: Dictionary = {}
	var is_sim: bool = GameManager.get_meta(&"simulate_match", false)

	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null:
			continue
		player.add_to_group(&"players")
		if player.brain != null:
			player.brain.bind_ball(ball)
			player.brain.bind_boundary(boundary)
		if is_sim:
			player.is_user_controlled = false
		if player.is_user_controlled:
			hud.bind_active_player(player)

		var anchor: Vector2 = player.brain.formation_anchor if player.brain != null else player.global_position
		var slot: int = squad_counts.get(player.team, 0)
		squad_counts[player.team] = slot + 1

		# The pre-game screen / pause menu reorder the starting XI into
		# TeamData.lineup_indices; a squad with no lineup set yet (practice
		# mode, or a standalone editor run) falls back to raw slot order.
		var team: TeamData = DataLoader.get_match_team(player.team)
		player.squad_index = team.lineup_indices[slot] if team.lineup_indices.size() == 11 else slot
		PlayerFactory.apply(player, DataLoader.get_player(player.team, player.squad_index), anchor)

	minimap.bind(players, boundary, match_official_crew)


## Reacts to a substitution made in PauseMenu: finds the live node whose
## squad_index matches player_out_idx and re-applies it in place as
## player_in_idx via HeavyPlayerController.apply_player_data() — never freed
## and re-added, so the FSM, MatchWorldModel slot and scene position all stay
## untouched. MatchWorldModel needs no explicit refresh: player_nodes[slot]
## still points at the same node, the team is unchanged, and its next
## _physics_process tick (priority -100, ahead of everything else) re-reads
## position/velocity off that same node automatically.
func _on_substitution_made(team: int, player_out_idx: int, player_in_idx: int) -> void:
	var incoming_data: PlayerData = DataLoader.get_player(team, player_in_idx)

	var target: HeavyPlayerController = null
	for node: Node in players.get_children():
		var p := node as HeavyPlayerController
		if p == null or p.team != team or p.squad_index != player_out_idx:
			continue
		target = p
		break

	if target == null:
		return

	var mood_node: MoodSystem = target.get_mood()
	var old_tier: int = mood_node.current_tier if mood_node != null else -1

	target.squad_index = player_in_idx
	target.apply_player_data(incoming_data)

	if mood_node != null and int(mood_node.current_tier) != old_tier:
		GameEvents.player_mood_changed.emit(target, int(mood_node.current_tier))


## Hands control to whichever teammate is closest to the ball. Control transfers
## wholesale: the player being left behind hands off to its brain, which picks up
## from the exact velocity it was moving at, so a switch never teleports momentum.
func switch_to_nearest_teammate() -> void:
	var current: HeavyPlayerController = hud.active_player
	if current == null:
		return

	var best: HeavyPlayerController = null
	var best_dist_sq: float = INF
	var ball_pos: Vector2 = ball.global_position
	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player == current or player.team != current.team:
			continue
		var dist_sq: float = player.global_position.distance_squared_to(ball_pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
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


func _on_goal_scored(scoring_team: int, _scorer: Node = null) -> void:
	if GameManager.shootout_active:
		return  # PenaltyShootoutCoordinator owns the reset between kicks.
	ball.freeze()
	shake_camera(1.0)
	InputHelper.rumble(0.5, 0.9, 0.35)
	## FIX: Guards against a null/broken $RestartTimer (silent no-op in release
	## builds) permanently stalling the match in GOAL_SCORED — the kickoff is
	## deferred onto a one-shot SceneTreeTimer instead.
	if restart_timer == null or not restart_timer.is_inside_tree():
		get_tree().create_timer(goal_restart_delay).timeout.connect(_on_restart_timer_timeout)
	else:
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


## Layer 5 narrative reaction to a sharp Team Momentum swing (Macro match
## architecture — see MatchStatsTracker's momentum accumulator). Mirrors
## _fire_touchline_goal_shout()'s home-perspective-only convention: the away
## manager never gets a reaction bubble, so this only watches TEAM_A's
## momentum. Two fixed lines rather than a PressOffice trait-flavoured quote —
## a momentum swing isn't one of PressOffice's existing quote contexts
## (post-match / touchline goal / touchline shift), and adding a whole new
## trait-quote category for this one signal is out of scope here (see
## AGENTS_ERRATA.md).
func _on_team_momentum_updated(team: int, momentum: float) -> void:
	if team != GameManager.TEAM_A:
		return

	var delta_m: float = momentum - _last_home_momentum
	_last_home_momentum = momentum
	if absf(delta_m) < MOMENTUM_SWING_THRESHOLD:
		return

	var home_data: ManagerData = _manager_director_a.get_data()
	if home_data == null:
		return

	var quote: String = "KEEP PUSHING! NO LET UP!" if delta_m > 0.0 else "CONCENTRATE! WAKE UP!"
	var display_name: String = home_data.manager_name if home_data.manager_name != "" else "Manager"
	_touchline_bubble.show_shout(display_name, quote, true)


## HOME manager's half-time quote only.
## INTENTIONAL: away team half-time instructions are secret. The player only
## ever controls the home team, so surfacing the away manager's tactical talk
## would hand over information the player is not meant to see.
func _on_half_time_reached() -> void:
	ball.freeze()

	# Touchline shout (existing behaviour preserved).
	var home_data: ManagerData = _manager_director_a.get_data()
	if home_data != null:
		var ctx := PressOffice.PressContext.new()
		ctx.event = "pre_match"
		ctx.opponent_name = _selected_away_team.team_name if _selected_away_team != null else ""
		var quote: String = _press_office.generate_quote(home_data, ctx)
		var display_name: String = home_data.manager_name if home_data.manager_name != "" else "Manager"
		_touchline_bubble.show_shout(display_name, quote, true)

	# Wait, then swap ends and start the second half.
	await get_tree().create_timer(HALF_TIME_DURATION).timeout
	_swap_ends_and_restart()


## Mirrors every player's formation_anchor around the pitch centre X and fires
## a second-half kickoff.
func _swap_ends_and_restart() -> void:
	var centre_x: float = boundary.get_centre_spot().x

	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player.brain == null:
			continue
		var anchor: Vector2 = player.brain.formation_anchor
		player.brain.formation_anchor = Vector2(2.0 * centre_x - anchor.x, anchor.y)

	_start_kickoff_flow()


## Begins the shared kickoff ceremony: enter KICKOFF first, then reposition
## everyone and hand the dead ball to SetPieceCoordinator to freeze/take/resume.
## play stays paused until the coordinator's _on_taker_state_changed() fires
## restart_play() after the ball has actually been struck.
func _start_kickoff_flow() -> void:
	# Phase first: reset_for_kickoff() emits kickoff_confirmed below, and any
	# handler must already observe current_phase == KICKOFF.
	GameManager.kickoff()

	# Snapshot the mutable kickoff decision ONCE — the exact same value feeds
	# the reset/emit and the coordinator; nothing may re-read the field
	# in between (it can mutate, e.g. around a shootout restart).
	var last_scorer: int = GameManager.last_scoring_team
	var kickoff_team: int = GameManager.TEAM_A
	if last_scorer >= 0:
		kickoff_team = 1 - last_scorer

	reset_for_kickoff(kickoff_team)
	_set_piece_coordinator.start_kickoff(kickoff_team)


func _on_restart_timer_timeout() -> void:
	## FIX: Guards against a stale timer already running from a prior state
	## (shootout, half-time) firing a spurious kickoff that would clobber those
	## flows' own restarts.
	if GameManager.current_phase != GameManager.MatchPhase.GOAL_SCORED:
		push_warning("PitchScene: restart timer fired outside GOAL_SCORED phase — ignoring.")
		return
	_start_kickoff_flow()


func _on_match_ended(winner: int) -> void:
	# A drawn full-time score (winner < 0 — see GameManager.get_leading_team())
	# redirects into a shootout instead of ending the match here.
	# PenaltyShootoutCoordinator runs the shootout entirely on its own and
	# calls GameManager.end_shootout() once a winner is decided, which re-fires
	# match_ended — this time with a decisive winner, so the body below runs
	# exactly once, at the real end of the match. Practice mode never reaches
	# this handler at all (see _setup_practice_arena()), but the guard is kept
	# here too since a shootout only ever makes sense for a full match.
	if winner < 0 and not _is_practice_mode:
		_start_penalty_shootout()
		return

	ball.freeze()
	_teardown_goalkeeper_dive_coordinator()
	_log_manager_stats(winner)
	# The world model is deliberately NOT cleared here: full time is a phase,
	# not a teardown, and the rematch flow below would restart play against an
	# empty roster with no spawn pass left to re-register anyone. _exit_tree()
	# owns the reset instead — it covers this path and practice mode both.
	_show_match_stats()


## Shows the full-time scoreboard/stats overlay. MatchStatsTracker.reset() is
## deliberately deferred to MatchStatsUI.stats_dismissed — the tracker's
## counts must still be readable while the overlay is up.
func _show_match_stats() -> void:
	MatchStatsTracker.stop_possession_sampling()

	var team_names: Array[String] = _resolve_team_names()
	var stats_ui: MatchStatsUI = MatchStatsScene.instantiate() as MatchStatsUI
	add_child(stats_ui)
	stats_ui.populate(team_names[0], team_names[1])
	stats_ui.stats_dismissed.connect(_on_stats_dismissed)
	stats_ui.show()


func _on_stats_dismissed() -> void:
	MatchStatsTracker.reset()
	_last_home_momentum = 0.0


## Splits the live roster into each team's players and hands them to
## PenaltyShootoutCoordinator, which owns the rest of the shootout.
func _start_penalty_shootout() -> void:
	var team_a_players: Array[HeavyPlayerController] = []
	var team_b_players: Array[HeavyPlayerController] = []
	for node: Node in players.get_children():
		var p := node as HeavyPlayerController
		if p == null:
			continue
		if p.team == GameManager.TEAM_A:
			team_a_players.append(p)
		elif p.team == GameManager.TEAM_B:
			team_b_players.append(p)

	_penalty_shootout_coordinator.start(team_a_players, team_b_players)


## Clears the world model roster whenever the match scene goes away, by any
## route — full time, quitting to the menu, or practice mode, which never
## reaches _on_match_ended() at all. Without this the next match's players
## would claim slots from 22 upward and fall off the end of the model.
func _exit_tree() -> void:
	if MatchWorldModel.instance != null:
		MatchWorldModel.instance.unregister_all()


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
	if GameManager.shootout_active:
		return  # A miss the shootout coordinator already watches for itself.
	ball.freeze()
	_set_piece_coordinator.handle_out_of_bounds(side, ball.global_position, ball.last_touched_by)


func _on_ball_bounced(impact_velocity: float) -> void:
	# Only meaningful impacts shake the frame — a settling ball should not.
	if impact_velocity > 200.0:
		shake_camera(clampf(impact_velocity / 900.0, 0.0, 0.6))


## --- Headless Simulation Telemetry Harness ----------------------------------

func _tick_headless_telemetry(delta: float) -> void:
	_sim_ticks += 1
	_sim_elapsed += delta

	var world: MatchWorldModel = MatchWorldModel.instance
	if world != null:
		# Check all players for NaN/Inf floats
		for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
			var pos: Vector2 = world.player_positions[i]
			var vel: Vector2 = world.player_velocities[i]
			if is_nan(pos.x) or is_nan(pos.y) or is_inf(pos.x) or is_inf(pos.y):
				_sim_nan_inf_count += 1
			if is_nan(vel.x) or is_nan(vel.y) or is_inf(vel.x) or is_inf(vel.y):
				_sim_nan_inf_count += 1

			var p: HeavyPlayerController = world.player_nodes[i]
			if is_instance_valid(p) and p.brain != null:
				_sim_anchor_samples.append(p.brain.formation_anchor.x)

		# Check ball for NaN/Inf floats
		var ball_pos: Vector2 = world.ball_position
		var ball_vel: Vector2 = world.ball_velocity
		if is_nan(ball_pos.x) or is_nan(ball_pos.y) or is_inf(ball_pos.x) or is_inf(ball_pos.y):
			_sim_nan_inf_count += 1
		if is_nan(ball_vel.x) or is_nan(ball_vel.y) or is_inf(ball_vel.x) or is_inf(ball_vel.y):
			_sim_nan_inf_count += 1

		# Boundary escape detection: ball out of boundary rect without triggering bounds
		if boundary != null:
			var half_size: Vector2 = boundary.pitch_size * 0.5
			var centre: Vector2 = boundary.get_centre_spot()
			var dx: float = absf(ball_pos.x - centre.x)
			var dy: float = absf(ball_pos.y - centre.y)
			if dx > half_size.x + 300.0 or dy > half_size.y + 300.0:
				_sim_boundary_escape_count += 1

	if _sim_elapsed >= _sim_duration:
		_finalize_headless_simulation()


func _finalize_headless_simulation() -> void:
	var anchor_mean: float = 0.0
	if _sim_anchor_samples.size() > 0:
		var sum: float = 0.0
		for s: float in _sim_anchor_samples:
			sum += s
		anchor_mean = sum / float(_sim_anchor_samples.size())

	var anchor_var: float = 0.0
	if _sim_anchor_samples.size() > 1:
		var sum_sq: float = 0.0
		for s: float in _sim_anchor_samples:
			var diff: float = s - anchor_mean
			sum_sq += diff * diff
		anchor_var = sqrt(sum_sq / float(_sim_anchor_samples.size() - 1))

	var is_clean: bool = (
		_sim_nan_inf_count == 0
		and _sim_boundary_escape_count == 0
		and _sim_ai_cadence_violations == 0
	)

	var report: Dictionary = {
		"status": "pass" if is_clean else "fail",
		"duration_simulated_sec": _sim_elapsed,
		"ticks_simulated": _sim_ticks,
		"nan_inf_count": _sim_nan_inf_count,
		"boundary_escape_count": _sim_boundary_escape_count,
		"ai_cadence_violations": _sim_ai_cadence_violations,
		"anchor_variance": anchor_var,
		"score": [GameManager.score[0], GameManager.score[1]],
		"match_phase": int(GameManager.current_phase)
	}

	var json_str: String = JSON.stringify(report, "\t")
	var file: FileAccess = FileAccess.open(_sim_output_json, FileAccess.WRITE)
	if file != null:
		file.store_string(json_str)
		file.close()

	print("[HEADLESS SIMULATION COMPLETED] " + json_str)
	get_tree().quit(0 if is_clean else 1)
