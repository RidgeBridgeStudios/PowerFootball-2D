##
## MatchOfficialCrew
##
## Officiating crew manager orchestrating the Center Referee, two Assistant Referees
## (Linesmen), the 4th Official, and the Whistle Synthesizer.
## Responds to GameEvents match flow, fouls, cards, offsides, and substitutions with
## coordinated kinematic movements, gestures, flag signaling, LED board presentation,
## and procedural audio whistle cues.
##
## Zero physical collision interference: pure visual Node2D layer.
##
## Depends on: GameEvents, MatchWorldModel, PitchBoundary, RefereeData,
##             CenterRefereeVisual, AssistantRefereeVisual, FourthOfficialVisual,
##             WhistleSynthesizer.
## Exposes: bind(boundary, referee_data), get_center_ref(), get_linesmen(),
##          get_fourth_official()
##

class_name MatchOfficialCrew
extends Node2D

@onready var center_ref: CenterRefereeVisual = $CenterReferee
@onready var linesman_top: AssistantRefereeVisual = $LinesmanTop
@onready var linesman_bottom: AssistantRefereeVisual = $LinesmanBottom
@onready var fourth_official: FourthOfficialVisual = $FourthOfficial
@onready var whistle_synth: WhistleSynthesizer = $WhistleSynthesizer

var _boundary: PitchBoundary = null
var _referee_data: RefereeData = null
var _signals_connected: bool = false


func _ready() -> void:
	z_index = 2
	_ensure_child_nodes()
	_connect_signals()


func _ensure_child_nodes() -> void:
	if center_ref == null:
		center_ref = CenterRefereeVisual.new()
		center_ref.name = "CenterReferee"
		add_child(center_ref)

	if linesman_top == null:
		linesman_top = AssistantRefereeVisual.new()
		linesman_top.name = "LinesmanTop"
		add_child(linesman_top)

	if linesman_bottom == null:
		linesman_bottom = AssistantRefereeVisual.new()
		linesman_bottom.name = "LinesmanBottom"
		add_child(linesman_bottom)

	if fourth_official == null:
		fourth_official = FourthOfficialVisual.new()
		fourth_official.name = "FourthOfficial"
		add_child(fourth_official)

	if whistle_synth == null:
		whistle_synth = WhistleSynthesizer.new()
		whistle_synth.name = "WhistleSynthesizer"
		add_child(whistle_synth)


func bind(boundary: PitchBoundary, data: RefereeData) -> void:
	_boundary = boundary
	_referee_data = data
	_ensure_child_nodes()

	center_ref.bind(_boundary, _referee_data)
	linesman_top.bind(_boundary, true)       ## AR1: Top touchline, right half
	linesman_bottom.bind(_boundary, false)   ## AR2: Bottom touchline, left half
	fourth_official.bind(_boundary)

	_connect_signals()


func _connect_signals() -> void:
	if _signals_connected:
		return
	_signals_connected = true

	if not GameEvents.referee_awarded_foul.is_connected(_on_referee_awarded_foul):
		GameEvents.referee_awarded_foul.connect(_on_referee_awarded_foul)
	if not GameEvents.referee_played_on.is_connected(_on_referee_played_on):
		GameEvents.referee_played_on.connect(_on_referee_played_on)
	if not GameEvents.yellow_card_shown.is_connected(_on_yellow_card_shown):
		GameEvents.yellow_card_shown.connect(_on_yellow_card_shown)
	if not GameEvents.red_card_shown.is_connected(_on_red_card_shown):
		GameEvents.red_card_shown.connect(_on_red_card_shown)
	if not GameEvents.offside_called.is_connected(_on_offside_called):
		GameEvents.offside_called.connect(_on_offside_called)
	if not GameEvents.ball_out_of_bounds.is_connected(_on_ball_out_of_bounds):
		GameEvents.ball_out_of_bounds.connect(_on_ball_out_of_bounds)
	if not GameEvents.substitution_made.is_connected(_on_substitution_made):
		GameEvents.substitution_made.connect(_on_substitution_made)
	if not GameEvents.goal_scored.is_connected(_on_goal_scored):
		GameEvents.goal_scored.connect(_on_goal_scored)
	if not GameEvents.kickoff_started.is_connected(_on_kickoff_started):
		GameEvents.kickoff_started.connect(_on_kickoff_started)
	if not GameEvents.half_time_reached.is_connected(_on_half_time_reached):
		GameEvents.half_time_reached.connect(_on_half_time_reached)
	if not GameEvents.match_ended.is_connected(_on_match_ended):
		GameEvents.match_ended.connect(_on_match_ended)
	if not GameEvents.free_kick_started.is_connected(_on_free_kick_started):
		GameEvents.free_kick_started.connect(_on_free_kick_started)
	if not GameEvents.penalty_started.is_connected(_on_penalty_started):
		GameEvents.penalty_started.connect(_on_penalty_started)
	if not GameEvents.stoppage_time_announced.is_connected(_on_stoppage_time_announced):
		GameEvents.stoppage_time_announced.connect(_on_stoppage_time_announced)


## --- GameEvents Handlers ---------------------------------------------------

func _on_referee_awarded_foul(_ref: Node, _fouler: Node, _victim: Node, foul_pos: Vector2) -> void:
	whistle_synth.play_hard_blast(center_ref.global_position)
	center_ref.respond_to_foul(foul_pos)


func _on_referee_played_on(_ref: Node, _fouler: Node, _victim: Node, _foul_pos: Vector2) -> void:
	# Subtle gesture: ref waves arms forward for advantage
	center_ref.gesture_restart(center_ref.global_position + Vector2(100.0, 0.0))


func _on_yellow_card_shown(player: Node, _team: int) -> void:
	var player_node := player as Node2D
	var target_pos: Vector2 = player_node.global_position if player_node != null else center_ref.global_position
	whistle_synth.play_hard_blast(center_ref.global_position)
	center_ref.present_yellow_card(target_pos)


func _on_red_card_shown(player: Node, _team: int, _is_second_yellow: bool) -> void:
	var player_node := player as Node2D
	var target_pos: Vector2 = player_node.global_position if player_node != null else center_ref.global_position
	whistle_synth.play_hard_blast(center_ref.global_position)
	center_ref.present_red_card(target_pos)


func _on_offside_called(offside_player: Node, defending_team: int, position: Vector2) -> void:
	whistle_synth.play_hard_blast(center_ref.global_position)
	center_ref.respond_to_foul(position)

	# The defending team on right (+X) is Team 1 -> top linesman (AR1) flags.
	# The defending team on left (-X) is Team 0 -> bottom linesman (AR2) flags.
	if defending_team == 1:
		linesman_top.signal_offside()
	else:
		linesman_bottom.signal_offside()


func _on_ball_out_of_bounds(side: String) -> void:
	var world: MatchWorldModel = MatchWorldModel.instance
	var ball_pos: Vector2 = world.ball_position if world != null else Vector2.ZERO
	var dir_x: float = world.ball_velocity.x if world != null else 1.0

	match side:
		"touchline_top":
			linesman_top.signal_throw_in(dir_x)
		"touchline_bottom":
			linesman_bottom.signal_throw_in(dir_x)
		"end_line_corner":
			if ball_pos.x >= 0.0:
				linesman_top.signal_corner(ball_pos)
			else:
				linesman_bottom.signal_corner(ball_pos)
		"end_line_goal_kick":
			if ball_pos.x >= 0.0:
				linesman_top.signal_goal_kick()
			else:
				linesman_bottom.signal_goal_kick()


func _on_substitution_made(team: int, player_out_idx: int, player_in_idx: int) -> void:
	fourth_official.present_substitution(team, player_out_idx, player_in_idx)


func _on_stoppage_time_announced(added_minutes: int, _half: int) -> void:
	if fourth_official != null:
		fourth_official.present_stoppage_time(added_minutes)


func _on_goal_scored(_team: int, _scorer: Node = null) -> void:
	whistle_synth.play_hard_blast(center_ref.global_position)
	var center_spot: Vector2 = _boundary.get_centre_spot() if _boundary != null else Vector2.ZERO
	center_ref.gesture_restart(center_spot)


func _on_kickoff_started() -> void:
	whistle_synth.play_kickoff_blast(center_ref.global_position)
	center_ref.reset_position()


func _on_half_time_reached() -> void:
	whistle_synth.play_double_blast(center_ref.global_position)


func _on_match_ended(_winner: int) -> void:
	whistle_synth.play_triple_blast(center_ref.global_position)


func _on_free_kick_started(_team: int, position: Vector2, _is_direct: bool) -> void:
	whistle_synth.play_short_blast(center_ref.global_position)
	center_ref.respond_to_foul(position)


func _on_penalty_started(_team: int, position: Vector2) -> void:
	whistle_synth.play_hard_blast(center_ref.global_position)
	center_ref.respond_to_foul(position)


## --- Minimap & External Accessors ------------------------------------------

func get_center_ref() -> CenterRefereeVisual:
	return center_ref


func get_linesmen() -> Array[AssistantRefereeVisual]:
	return [linesman_top, linesman_bottom]


func get_fourth_official() -> FourthOfficialVisual:
	return fourth_official
