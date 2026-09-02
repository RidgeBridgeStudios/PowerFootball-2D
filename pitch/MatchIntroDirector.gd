##
## MatchIntroDirector
##
## Cinematic coordinator managing the pre-match opening sequence.
## Orchestrates the walk-in from the tunnel, the ceremonial lineup facing the camera,
## the broadcast presentation graphics synchronization, and dynamic dispersal to
## tactical kickoff formation anchors.
##
## Kinematic discipline:
##   - Zero physical interference: all players are held in SET_PIECE_FREEZE during intro.
##   - Smooth kinematic motion and positioning.
##   - Immediate, clean skip capability at any frame.
##
## Depends on: PitchBoundary, Pseudo3DBall, HeavyPlayerController, MatchCamera,
##             MatchReferee, MatchOfficialCrew, MatchIntroUI, WhistleSynthesizer,
##             TeamData, RefereeData, ManagerData, GameEvents, GameManager.
## Exposes: bind(boundary, ball, players_node, camera, ref, crew, ui, whistle),
##          start_intro(team_a, team_b, ref_data, mgr_a, mgr_b), skip_intro(),
##          is_intro_active(), signal intro_completed.
##

class_name MatchIntroDirector
extends Node

signal intro_completed

enum IntroStage {
	INACTIVE = 0,
	WALK_IN = 1,
	LINEUP_CEREMONY = 2,
	DISPERSE_TO_ANCHORS = 3,
	COMPLETED = 4
}

const SPEED_WALK_IN: float = 125.0
const SPEED_DISPERSE: float = 230.0
const LINEUP_Y: float = -65.0
const PLAYER_SPACING: float = 34.0

var _boundary: PitchBoundary = null
var _ball: Pseudo3DBall = null
var _players_node: Node2D = null
var _camera: MatchCamera = null
var _referee: MatchReferee = null
var _official_crew: MatchOfficialCrew = null
var _intro_ui: MatchIntroUI = null
var _whistle_synth: WhistleSynthesizer = null

var _stage: IntroStage = IntroStage.INACTIVE
var _stage_timer: float = 0.0
var _active_tweens: Array[Tween] = []

var _team_a_players: Array[HeavyPlayerController] = []
var _team_b_players: Array[HeavyPlayerController] = []

var _lineup_targets_a: Array[Vector2] = []
var _lineup_targets_b: Array[Vector2] = []
var _ref_lineup_target: Vector2 = Vector2(0.0, LINEUP_Y)
var _ar1_lineup_target: Vector2 = Vector2(-18.0, LINEUP_Y)
var _ar2_lineup_target: Vector2 = Vector2(18.0, LINEUP_Y)
var _fourth_lineup_target: Vector2 = Vector2(0.0, LINEUP_Y - 24.0)

var _ceremony_step: int = 0
var _ceremony_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(
	boundary: PitchBoundary,
	p_ball: Pseudo3DBall,
	players_node: Node2D,
	camera: MatchCamera,
	ref: MatchReferee,
	crew: MatchOfficialCrew,
	ui: MatchIntroUI,
	whistle: WhistleSynthesizer
) -> void:
	_boundary = boundary
	_ball = p_ball
	_players_node = players_node
	_camera = camera
	_referee = ref
	_official_crew = crew
	_intro_ui = ui
	_whistle_synth = whistle

	if _intro_ui != null and not _intro_ui.skip_requested.is_connected(skip_intro):
		_intro_ui.skip_requested.connect(skip_intro)


func is_intro_active() -> bool:
	return _stage != IntroStage.INACTIVE and _stage != IntroStage.COMPLETED


func start_intro(
	team_a: TeamData,
	team_b: TeamData,
	ref_data: RefereeData,
	mgr_a: ManagerData,
	mgr_b: ManagerData
) -> void:
	_kill_all_tweens()
	_collect_team_rosters()
	_compute_lineup_slots()

	_stage = IntroStage.WALK_IN
	_stage_timer = 0.0
	_ceremony_step = 0
	_ceremony_timer = 0.0

	GameEvents.match_intro_started.emit()

	# 1. Spawn players and officials at tunnel entrance (outside top touchline)
	var tunnel_y: float = -490.0
	if _boundary != null:
		tunnel_y = _boundary.get_pitch_rect().position.y - 40.0

	# Team A in single file on left
	for i: int in range(_team_a_players.size()):
		var p_a: HeavyPlayerController = _team_a_players[i]
		p_a.global_position = Vector2(-36.0, tunnel_y - float(i) * 32.0)
		p_a.velocity = Vector2.ZERO
		p_a.movement_intent = Vector2.ZERO
		p_a.facing_direction = Vector2.DOWN
		p_a.is_user_controlled = false
		p_a.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)

	# Team B in single file on right
	for i: int in range(_team_b_players.size()):
		var p_b: HeavyPlayerController = _team_b_players[i]
		p_b.global_position = Vector2(36.0, tunnel_y - float(i) * 32.0)
		p_b.velocity = Vector2.ZERO
		p_b.movement_intent = Vector2.ZERO
		p_b.facing_direction = Vector2.DOWN
		p_b.is_user_controlled = false
		p_b.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)

	# Match officials leading the procession
	if _official_crew != null:
		var center_ref: CenterRefereeVisual = _official_crew.get_center_ref()
		if center_ref != null:
			center_ref.global_position = Vector2(0.0, tunnel_y)

		var linesmen: Array[AssistantRefereeVisual] = _official_crew.get_linesmen()
		if linesmen.size() >= 2:
			if linesmen[0] != null:
				linesmen[0].global_position = Vector2(-18.0, tunnel_y - 20.0)
			if linesmen[1] != null:
				linesmen[1].global_position = Vector2(18.0, tunnel_y - 20.0)

		var fourth_off: FourthOfficialVisual = _official_crew.get_fourth_official()
		if fourth_off != null:
			fourth_off.global_position = Vector2(0.0, tunnel_y - 36.0)

	# Ball carried near the lead referee
	if _ball != null:
		_ball.freeze()
		_ball.reset_at(Vector2(0.0, tunnel_y + 12.0))

	# Camera cinematic tracking on tunnel walk-in
	if _camera != null:
		_camera.set_cinematic_override(Vector2(0.0, tunnel_y + 120.0), 1.15)

	# UI setup
	if _intro_ui != null:
		_intro_ui.setup(team_a, team_b, ref_data, mgr_a, mgr_b)
		_intro_ui.show_intro_phase(MatchIntroUI.IntroCardPhase.FIXTURE_TITLE)

	# Start walk-in tween sequence
	_animate_walk_in()


func _collect_team_rosters() -> void:
	_team_a_players.clear()
	_team_b_players.clear()

	if _players_node == null:
		return

	for node: Node in _players_node.get_children():
		var p := node as HeavyPlayerController
		if p == null or not is_instance_valid(p):
			continue
		if p.team == GameManager.TEAM_A:
			_team_a_players.append(p)
		elif p.team == GameManager.TEAM_B:
			_team_b_players.append(p)


func _compute_lineup_slots() -> void:
	_lineup_targets_a.clear()
	_lineup_targets_b.clear()

	_ref_lineup_target = Vector2(0.0, LINEUP_Y)
	_ar1_lineup_target = Vector2(-18.0, LINEUP_Y)
	_ar2_lineup_target = Vector2(18.0, LINEUP_Y)
	_fourth_lineup_target = Vector2(0.0, LINEUP_Y - 26.0)

	for i: int in range(_team_a_players.size()):
		var slot_x_a: float = -46.0 - float(i) * PLAYER_SPACING
		_lineup_targets_a.append(Vector2(slot_x_a, LINEUP_Y))

	for i: int in range(_team_b_players.size()):
		var slot_x_b: float = 46.0 + float(i) * PLAYER_SPACING
		_lineup_targets_b.append(Vector2(slot_x_b, LINEUP_Y))


func _animate_walk_in() -> void:
	var walk_dur: float = 3.6
	var tween: Tween = create_tween()
	_active_tweens.append(tween)
	tween.set_parallel(true)

	# 1. Match Officials walk to line
	if _official_crew != null:
		var center_ref: CenterRefereeVisual = _official_crew.get_center_ref()
		if center_ref != null:
			tween.tween_property(center_ref, "global_position", _ref_lineup_target, walk_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		var linesmen: Array[AssistantRefereeVisual] = _official_crew.get_linesmen()
		if linesmen.size() >= 2:
			if linesmen[0] != null:
				tween.tween_property(linesmen[0], "global_position", _ar1_lineup_target, walk_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if linesmen[1] != null:
				tween.tween_property(linesmen[1], "global_position", _ar2_lineup_target, walk_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		var fourth_off: FourthOfficialVisual = _official_crew.get_fourth_official()
		if fourth_off != null:
			tween.tween_property(fourth_off, "global_position", _fourth_lineup_target, walk_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2. Match Ball follows lead referee
	if _ball != null:
		tween.tween_property(_ball, "global_position", Vector2(0.0, LINEUP_Y + 16.0), walk_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3. Team A players walk and spread into line
	for i: int in range(_team_a_players.size()):
		var p_a: HeavyPlayerController = _team_a_players[i]
		if not is_instance_valid(p_a):
			continue
		var target_a: Vector2 = _lineup_targets_a[i] if i < _lineup_targets_a.size() else Vector2(-46.0 - float(i) * 32.0, LINEUP_Y)
		tween.tween_property(p_a, "global_position", target_a, walk_dur + float(i) * 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4. Team B players walk and spread into line
	for i: int in range(_team_b_players.size()):
		var p_b: HeavyPlayerController = _team_b_players[i]
		if not is_instance_valid(p_b):
			continue
		var target_b: Vector2 = _lineup_targets_b[i] if i < _lineup_targets_b.size() else Vector2(46.0 + float(i) * 32.0, LINEUP_Y)
		tween.tween_property(p_b, "global_position", target_b, walk_dur + float(i) * 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 5. Camera tracks smoothly down to lineup position
	if _camera != null:
		tween.tween_method(func(pos: Vector2) -> void:
			if _camera != null:
				_camera.set_cinematic_override(pos, 1.25)
		, Vector2(0.0, -320.0), Vector2(0.0, LINEUP_Y), walk_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# On complete walk-in -> transition to Lineup Ceremony
	tween.chain().tween_callback(_on_walk_in_finished)


func _on_walk_in_finished() -> void:
	if _stage != IntroStage.WALK_IN:
		return
	_stage = IntroStage.LINEUP_CEREMONY
	_ceremony_step = 0
	_ceremony_timer = 0.0

	# Align all players facing down toward broadcast camera
	for p: HeavyPlayerController in _team_a_players:
		if is_instance_valid(p):
			p.facing_direction = Vector2.DOWN
			p.velocity = Vector2.ZERO
			p.movement_intent = Vector2.ZERO

	for p: HeavyPlayerController in _team_b_players:
		if is_instance_valid(p):
			p.facing_direction = Vector2.DOWN
			p.velocity = Vector2.ZERO
			p.movement_intent = Vector2.ZERO

	if _camera != null:
		_camera.set_cinematic_override(Vector2(0.0, LINEUP_Y), 1.30)

	# Show Referee Personality Card
	if _intro_ui != null:
		_intro_ui.show_intro_phase(MatchIntroUI.IntroCardPhase.MATCH_OFFICIALS)


func _process(delta: float) -> void:
	if _stage == IntroStage.LINEUP_CEREMONY:
		_tick_ceremony(delta)


func _tick_ceremony(delta: float) -> void:
	_ceremony_timer += delta

	# Card sequence timings:
	# 0.0s -> MATCH_OFFICIALS
	# 2.4s -> HOME_LINEUP
	# 4.8s -> AWAY_LINEUP
	# 7.2s -> BREAK TO POSITIONS
	if _ceremony_step == 0 and _ceremony_timer >= 2.4:
		_ceremony_step = 1
		if _intro_ui != null:
			_intro_ui.show_intro_phase(MatchIntroUI.IntroCardPhase.HOME_LINEUP)
	elif _ceremony_step == 1 and _ceremony_timer >= 4.8:
		_ceremony_step = 2
		if _intro_ui != null:
			_intro_ui.show_intro_phase(MatchIntroUI.IntroCardPhase.AWAY_LINEUP)
	elif _ceremony_step == 2 and _ceremony_timer >= 7.2:
		_ceremony_step = 3
		_break_to_positions()


func _break_to_positions() -> void:
	if _stage != IntroStage.LINEUP_CEREMONY:
		return

	_stage = IntroStage.DISPERSE_TO_ANCHORS
	_kill_all_tweens()

	# Whistle cue
	if _whistle_synth != null and _official_crew != null:
		var ref_pos: Vector2 = _official_crew.get_center_ref().global_position if _official_crew.get_center_ref() != null else Vector2.ZERO
		_whistle_synth.play_kickoff_blast(ref_pos)

	if _intro_ui != null:
		_intro_ui.show_intro_phase(MatchIntroUI.IntroCardPhase.KICKOFF_READY)

	var disperse_dur: float = 2.4
	var tween: Tween = create_tween()
	_active_tweens.append(tween)
	tween.set_parallel(true)

	# 1. Move ball to centre spot
	var centre_spot: Vector2 = _boundary.get_centre_spot() if _boundary != null else Vector2.ZERO
	if _ball != null:
		tween.tween_property(_ball, "global_position", centre_spot, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2. Officials disperse to match positions
	if _official_crew != null and _boundary != null:
		var rect: Rect2 = _boundary.get_pitch_rect()
		var center_ref: CenterRefereeVisual = _official_crew.get_center_ref()
		if center_ref != null:
			tween.tween_property(center_ref, "global_position", centre_spot + Vector2(-60.0, -40.0), disperse_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		var linesmen: Array[AssistantRefereeVisual] = _official_crew.get_linesmen()
		if linesmen.size() >= 2:
			if linesmen[0] != null:
				var ar1_spot := Vector2(rect.size.x * 0.25, rect.position.y - 18.0)
				tween.tween_property(linesmen[0], "global_position", ar1_spot, disperse_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if linesmen[1] != null:
				var ar2_spot := Vector2(-rect.size.x * 0.25, rect.end.y + 18.0)
				tween.tween_property(linesmen[1], "global_position", ar2_spot, disperse_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		var fourth_off: FourthOfficialVisual = _official_crew.get_fourth_official()
		if fourth_off != null:
			var fourth_spot := Vector2(0.0, rect.position.y - 36.0)
			tween.tween_property(fourth_off, "global_position", fourth_spot, disperse_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3. Team A and Team B players jog to their formation anchors
	for p: HeavyPlayerController in _team_a_players:
		if not is_instance_valid(p):
			continue
		var anchor_a: Vector2 = p.brain.formation_anchor if p.brain != null else p.global_position
		tween.tween_property(p, "global_position", anchor_a, disperse_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	for p: HeavyPlayerController in _team_b_players:
		if not is_instance_valid(p):
			continue
		var anchor_b: Vector2 = p.brain.formation_anchor if p.brain != null else p.global_position
		tween.tween_property(p, "global_position", anchor_b, disperse_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 4. Camera returns smoothly to default gameplay overview
	if _camera != null:
		tween.tween_method(func(pos: Vector2) -> void:
			if _camera != null:
				_camera.set_cinematic_override(pos, 1.05)
		, Vector2(0.0, LINEUP_Y), centre_spot, disperse_dur * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Finish after dispersal
	tween.chain().tween_callback(_complete_intro)


func _complete_intro() -> void:
	if _stage == IntroStage.COMPLETED:
		return
	_stage = IntroStage.COMPLETED
	_kill_all_tweens()

	if _camera != null:
		_camera.clear_cinematic_override()

	if _intro_ui != null:
		_intro_ui.hide_intro()

	GameEvents.match_intro_finished.emit()
	intro_completed.emit()


func skip_intro() -> void:
	if _stage == IntroStage.INACTIVE or _stage == IntroStage.COMPLETED:
		return

	_stage = IntroStage.COMPLETED
	_kill_all_tweens()

	# Snap ball to centre spot
	var centre_spot: Vector2 = _boundary.get_centre_spot() if _boundary != null else Vector2.ZERO
	if _ball != null:
		_ball.reset_at(centre_spot)

	# Snap officials to match positions
	if _official_crew != null and _boundary != null:
		var rect: Rect2 = _boundary.get_pitch_rect()
		var center_ref: CenterRefereeVisual = _official_crew.get_center_ref()
		if center_ref != null:
			center_ref.global_position = centre_spot + Vector2(-60.0, -40.0)

		var linesmen: Array[AssistantRefereeVisual] = _official_crew.get_linesmen()
		if linesmen.size() >= 2:
			if linesmen[0] != null:
				linesmen[0].global_position = Vector2(rect.size.x * 0.25, rect.position.y - 18.0)
			if linesmen[1] != null:
				linesmen[1].global_position = Vector2(-rect.size.x * 0.25, rect.end.y + 18.0)

		var fourth_off: FourthOfficialVisual = _official_crew.get_fourth_official()
		if fourth_off != null:
			fourth_off.global_position = Vector2(0.0, rect.position.y - 36.0)

	# Snap all players to formation anchors
	for p: HeavyPlayerController in _team_a_players:
		if is_instance_valid(p) and p.brain != null:
			p.global_position = p.brain.formation_anchor
			p.velocity = Vector2.ZERO
			p.movement_intent = Vector2.ZERO
			p.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)

	for p: HeavyPlayerController in _team_b_players:
		if is_instance_valid(p) and p.brain != null:
			p.global_position = p.brain.formation_anchor
			p.velocity = Vector2.ZERO
			p.movement_intent = Vector2.ZERO
			p.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)

	if _camera != null:
		_camera.clear_cinematic_override()

	if _intro_ui != null:
		_intro_ui.hide_intro()

	GameEvents.match_intro_skipped.emit()
	GameEvents.match_intro_finished.emit()
	intro_completed.emit()


func _kill_all_tweens() -> void:
	for tw: Tween in _active_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_active_tweens.clear()
