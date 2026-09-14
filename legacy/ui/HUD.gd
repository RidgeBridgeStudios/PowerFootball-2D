##
## HUD
##
## Match readout: score, clock, the shot power meter, and the world-space stamina
## bar under the active player. It reads GameManager for state and listens on
## GameEvents for match flow — no gameplay system knows the HUD exists.
##
## The power meter is only visible while a kick is charging (or a throw-in /
## penalty is winding up — PlayerStateFactory.get_charge_ratio() covers all
## three); the stamina bar lives on the player scene (world space, so it tracks
## the sprite) and is driven from here for whichever player is currently
## controlled. The set piece banner announces each new dead-ball restart and
## fades itself out; the wall hint layers a short extra line on top of it when
## the human is defending a free kick. The mood label shows only while the
## active player is in SLUMP or STREAK — silent during NORMAL. The shootout
## scoreboard overlay tracks GameManager.shootout_active every frame and shows
## each team's name, running score and a 5-dot kick history.
##
## Depends on: GameManager, GameEvents, HeavyPlayerController, MoodSystem,
##             MatchReferee, PenaltyShootoutCoordinator.
## Exposes: bind_active_player(player), set_team_names(a, b), set_sim_speed_panel_visible(is_visible)
##

class_name HUD
extends CanvasLayer

## Charge below this leaves the power meter hidden, so a tapped pass does not
## flash the bar.
const METER_VISIBILITY_THRESHOLD: float = 0.02
## Seconds the set piece banner stays fully visible before it fades.
const BANNER_HOLD_TIME: float = 1.5
const BANNER_FADE_TIME: float = 0.4

## Dots shown per team on the shootout scoreboard overlay. Sudden-death kicks
## past this count still update the score readout, just without a dot of
## their own — see _on_shootout_kick_result().
const SHOOTOUT_DOTS_PER_TEAM: int = 5

var active_player: HeavyPlayerController = null

var _banner_tween: Tween = null
var _wall_hint_tween: Tween = null
var _sub_banner_tween: Tween = null

## Built programmatically in _ready() — HUD.tscn has no spare label slot for
## this, and the set piece banner it visually echoes is reserved for restarts.
var _sub_banner_label: Label = null

## Set once by PitchScene.set_team_names() at kickoff; used only by the
## shootout overlay, which has no other way to learn the selected team names.
var _team_a_name: String = "Team A"
var _team_b_name: String = "Team B"

## Shootout scoreboard overlay — built programmatically for the same reason as
## _sub_banner_label above. Visibility tracks GameManager.shootout_active every
## frame rather than a single phase value, because current_phase cycles through
## PENALTY_KICK/IN_PLAY for the live moments inside each individual kick.
var _shootout_overlay: PanelContainer = null
var _shootout_team_a_label: Label = null
var _shootout_team_b_label: Label = null
var _shootout_score_label: Label = null
var _shootout_dots_a: Array[Label] = []
var _shootout_dots_b: Array[Label] = []
var _shootout_overlay_was_active: bool = false

@onready var score_label: Label = $Root/TopBar/ScoreLabel
@onready var clock_label: Label = $Root/TopBar/ClockLabel
@onready var camera_mode_label: Label = $Root/CameraModeLabel
@onready var status_label: Label = $Root/StatusLabel
@onready var power_meter: ProgressBar = $Root/PowerMeter
@onready var set_piece_banner: Label = $Root/SetPieceBanner
@onready var wall_hint_label: Label = $Root/WallHintLabel
@onready var mood_label: Label = $Root/MoodLabel
@onready var nameplate_panel: PanelContainer = $Root/NameplatePanel
@onready var nameplate_number_label: Label = $Root/NameplatePanel/NameplateBox/NumberLabel
@onready var nameplate_name_label: Label = $Root/NameplatePanel/NameplateBox/NameLabel
@onready var nameplate_stamina_bar: ProgressBar = $Root/NameplatePanel/NameplateBox/HudStaminaBar
@onready var nameplate_fatigue_label: Label = $Root/NameplatePanel/NameplateBox/FatigueLabel
@onready var practice_hints_panel: PanelContainer = $Root/PracticeHintsPanel
@onready var _practice_gk_label: Label = $Root/PracticeHintsPanel/VBox/GKLabel

@onready var sim_speed_panel: PanelContainer = $Root/SimSpeedPanel
@onready var sim_speed_value_label: Label = $Root/SimSpeedPanel/VBox/HeaderBox/SpeedValueLabel
@onready var sim_speed_slider: HSlider = $Root/SimSpeedPanel/VBox/SpeedSlider
@onready var replay_toggle_btn: Button = $Root/SimSpeedPanel/VBox/HeaderBox/ReplayToggleBtn
@onready var stamina_toggle_btn: Button = $Root/SimSpeedPanel/VBox/HeaderBox/StaminaToggleBtn
@onready var speed_1x_btn: Button = $Root/SimSpeedPanel/VBox/PresetRow/Speed1xBtn
@onready var speed_2x_btn: Button = $Root/SimSpeedPanel/VBox/PresetRow/Speed2xBtn
@onready var speed_4x_btn: Button = $Root/SimSpeedPanel/VBox/PresetRow/Speed4xBtn
@onready var speed_8x_btn: Button = $Root/SimSpeedPanel/VBox/PresetRow/Speed8xBtn
@onready var speed_16x_btn: Button = $Root/SimSpeedPanel/VBox/PresetRow/Speed16xBtn

@onready var replay_overlay: Control = $Root/ReplayOverlay
@onready var replay_badge_panel: PanelContainer = $Root/ReplayOverlay/ReplayBadgePanel
@onready var replay_skip_btn: Button = $Root/ReplayOverlay/SkipButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.kickoff_started.connect(_on_kickoff_started)
	GameEvents.match_phase_changed.connect(_on_match_phase_changed)
	GameEvents.match_ended.connect(_on_match_ended)
	GameEvents.player_switched.connect(_on_player_switched)
	GameEvents.player_mood_changed.connect(_on_player_mood_changed)

	GameEvents.goal_kick_started.connect(_on_goal_kick_started)
	GameEvents.corner_kick_started.connect(_on_corner_kick_started)
	GameEvents.throw_in_started.connect(_on_throw_in_started)
	GameEvents.free_kick_started.connect(_on_free_kick_started)
	GameEvents.penalty_started.connect(_on_penalty_started)
	GameEvents.defensive_wall_requested.connect(_on_defensive_wall_requested)
	GameEvents.substitution_made.connect(_on_substitution_made)
	GameEvents.yellow_card_shown.connect(_on_yellow_card_shown)
	GameEvents.red_card_shown.connect(_on_red_card_shown)
	GameEvents.offside_called.connect(_on_offside_called)
	GameEvents.shootout_kick_result.connect(_on_shootout_kick_result)
	GameEvents.half_time_started.connect(_on_half_time_started)
	GameEvents.half_time_ended.connect(_on_half_time_ended)
	GameEvents.stoppage_time_announced.connect(_on_stoppage_time_announced)
	GameEvents.simulation_speed_changed.connect(_on_simulation_speed_changed)
	GameEvents.goal_replays_toggled.connect(_on_goal_replays_toggled)
	GameEvents.replay_started.connect(_on_replay_started)
	GameEvents.replay_ended.connect(_on_replay_ended)


	power_meter.min_value = 0.0
	power_meter.max_value = 1.0
	power_meter.value = 0.0
	power_meter.visible = false
	status_label.text = ""

	set_piece_banner.modulate.a = 0.0
	set_piece_banner.visible = false
	wall_hint_label.visible = false
	mood_label.text = ""
	mood_label.visible = false
	nameplate_panel.visible = false

	var hud_bar_bg := StyleBoxFlat.new()
	hud_bar_bg.bg_color = Color(0.06, 0.06, 0.09, 0.8)
	hud_bar_bg.corner_radius_top_left = 3
	hud_bar_bg.corner_radius_top_right = 3
	hud_bar_bg.corner_radius_bottom_left = 3
	hud_bar_bg.corner_radius_bottom_right = 3
	nameplate_stamina_bar.add_theme_stylebox_override("background", hud_bar_bg)

	var hud_bar_fill := StyleBoxFlat.new()
	hud_bar_fill.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	hud_bar_fill.corner_radius_top_left = 3
	hud_bar_fill.corner_radius_top_right = 3
	hud_bar_fill.corner_radius_bottom_left = 3
	hud_bar_fill.corner_radius_bottom_right = 3
	nameplate_stamina_bar.add_theme_stylebox_override("fill", hud_bar_fill)

	_sub_banner_label = Label.new()
	_sub_banner_label.name = "SubBannerLabel"
	_sub_banner_label.layout_mode = 1
	_sub_banner_label.anchors_preset = 5
	_sub_banner_label.anchor_left = 0.5
	_sub_banner_label.anchor_right = 0.5
	_sub_banner_label.offset_left = -220.0
	_sub_banner_label.offset_top = 160.0
	_sub_banner_label.offset_right = 220.0
	_sub_banner_label.offset_bottom = 184.0
	_sub_banner_label.grow_horizontal = 2
	_sub_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_banner_label.add_theme_font_size_override("font_size", 18)
	_sub_banner_label.modulate.a = 0.0
	_sub_banner_label.visible = false
	$Root.add_child(_sub_banner_label)

	_build_shootout_overlay()
	_setup_sim_speed_panel()


func _process(_delta: float) -> void:
	if not practice_hints_panel.visible:
		score_label.text = GameManager.get_score_string()
		clock_label.text = GameManager.get_clock_string()
	_update_power_meter()
	_update_stamina_bar()
	_update_shootout_overlay()


## Called once by PitchScene at kickoff, alongside its other bind() calls —
## the HUD has no other way to learn the selected team names, and this avoids
## re-deriving them a second time from GameManager meta / DataLoader here.
func set_team_names(team_a_name: String, team_b_name: String) -> void:
	_team_a_name = team_a_name
	_team_b_name = team_b_name


## Called once from PitchScene._setup_practice_arena() to switch the HUD into
## practice mode: show hints, hide the match-only score/clock readout.
func enter_practice_mode() -> void:
	practice_hints_panel.visible = true

	# Applied at runtime rather than baked into the .tscn so it always wins
	# over any global theme applied to PanelContainer.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.05, 0.72)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	practice_hints_panel.add_theme_stylebox_override("panel", panel_style)

	score_label.visible = false
	clock_label.visible = false


## Called by PitchScene (via MatchCamera.camera_mode_changed) whenever the
## camera mode changes, so the player always sees which mode is active.
func set_camera_mode_label(mode_name: String) -> void:
	camera_mode_label.text = "CAM: " + mode_name


## Called by PitchScene whenever the GK active/frozen toggle changes.
func set_practice_gk_label(frozen: bool) -> void:
	if _practice_gk_label == null:
		return
	_practice_gk_label.text = "[X / Q]  GK: %s" % ("FROZEN" if frozen else "ACTIVE")


## Points the HUD at the player the human is currently controlling. Called on
## spawn and again on every GameEvents.player_switched.
func bind_active_player(player: HeavyPlayerController) -> void:
	if active_player == player:
		return

	# Only the controlled player shows a stamina bar; the rest stay clean.
	if active_player != null and is_instance_valid(active_player):
		active_player.stamina_bar.visible = false

	active_player = player
	if active_player != null:
		active_player.stamina_bar.visible = true
		var mood_node: MoodSystem = active_player.get_mood()
		if mood_node != null:
			_refresh_mood_label(mood_node.current_tier)
		else:
			_refresh_mood_label(MoodSystem.Tier.NORMAL)
	_refresh_nameplate()


## Shirt number and name live on the PlayerData resource PlayerFactory stashes
## in meta (see PlayerFactory.apply) rather than on the controller itself.
func _refresh_nameplate() -> void:
	if active_player == null or not is_instance_valid(active_player):
		nameplate_panel.visible = false
		return

	var data: PlayerData = active_player.get_meta(&"player_data", null) as PlayerData
	if data == null:
		nameplate_panel.visible = false
		return

	nameplate_number_label.text = str(data.shirt_number)
	nameplate_name_label.text = data.player_name
	nameplate_panel.visible = true
	_update_hud_stamina_readout()


func _update_power_meter() -> void:
	if active_player == null or not is_instance_valid(active_player):
		power_meter.visible = false
		return

	var charge: float = active_player.state_factory.get_charge_ratio()
	power_meter.value = charge
	power_meter.visible = charge > METER_VISIBILITY_THRESHOLD


func _update_stamina_bar() -> void:
	if active_player == null or not is_instance_valid(active_player):
		return

	_update_hud_stamina_readout()


func _update_hud_stamina_readout() -> void:
	if active_player == null or not is_instance_valid(active_player):
		return

	var ratio: float = active_player.get_stamina_ratio()
	var tier: HeavyPlayerController.FatigueTier = active_player.get_fatigue_tier()

	nameplate_stamina_bar.value = ratio

	var tier_color: Color
	var tier_name: String
	if active_player.sprint_locked or tier == HeavyPlayerController.FatigueTier.EXHAUSTED:
		tier_color = Color(0.95, 0.25, 0.25)
		tier_name = "EXHAUSTED"
	elif tier == HeavyPlayerController.FatigueTier.TIRED:
		tier_color = Color(1.0, 0.75, 0.15)
		tier_name = "TIRED"
	else:
		tier_color = Color(0.24, 0.86, 0.41)
		tier_name = "FRESH"

	nameplate_stamina_bar.modulate = tier_color
	nameplate_fatigue_label.text = "%d%% %s" % [int(ratio * 100.0), tier_name]
	nameplate_fatigue_label.add_theme_color_override("font_color", tier_color)


func _on_goal_scored(team: int, scorer: Node = null) -> void:
	var team_name: String = _team_a_name if team == GameManager.TEAM_A else _team_b_name
	var scorer_player := scorer as HeavyPlayerController
	var p_data: PlayerData = scorer_player.get_meta(&"player_data", null) as PlayerData if (scorer_player != null and scorer_player.has_meta(&"player_data")) else null
	if p_data != null and p_data.player_name != "":
		status_label.text = "GOAL! %s (%s)" % [p_data.player_name, team_name]
	else:
		status_label.text = "GOAL — %s" % team_name


func _on_kickoff_started() -> void:
	status_label.text = "KICKOFF"

	# Show referee name briefly at match start.
	var ref_node: MatchReferee = _find_referee()
	if ref_node != null and ref_node.current_data != null:
		_show_set_piece_banner("Referee: " + ref_node.current_data.referee_name)


## Clears the "KICKOFF" / "GOAL — TEAM X" status text once the restart has
## actually been taken and play is live again — otherwise it sits under the
## scoreboard for the rest of the match (see _on_kickoff_started above).
func _on_match_phase_changed(phase: int) -> void:
	if phase == GameManager.MatchPhase.IN_PLAY:
		status_label.text = ""
	elif phase == GameManager.MatchPhase.HALF_TIME:
		status_label.text = "HALF TIME"


func _on_half_time_started() -> void:
	status_label.text = "HALF TIME"
	_show_set_piece_banner("HALF TIME")


func _on_half_time_ended() -> void:
	status_label.text = "2ND HALF"
	_show_set_piece_banner("SECOND HALF")


func _on_stoppage_time_announced(added_minutes: int, _half: int) -> void:
	status_label.text = "ADDED TIME: +%d MIN" % added_minutes
	_show_set_piece_banner("+%d MIN ADDED TIME" % added_minutes)


## PitchScene is the parent of the CanvasLayer parent — walk up two levels.
func _find_referee() -> MatchReferee:
	var scene: Node = get_parent()
	if scene == null:
		return null
	return scene.get_node_or_null("MatchReferee") as MatchReferee


func _on_match_ended(winner: int) -> void:
	if winner < 0:
		status_label.text = "FULL TIME — DRAW"
	else:
		status_label.text = "FULL TIME — TEAM %s WINS" % ("A" if winner == GameManager.TEAM_A else "B")


func _on_player_switched(new_player: Node) -> void:
	bind_active_player(new_player as HeavyPlayerController)


func _on_player_mood_changed(player: Node, tier: int) -> void:
	if active_player == null or player != active_player:
		return
	_refresh_mood_label(tier)


## NORMAL shows nothing — the indicator is only for a player standing out from
## the pack, not a running readout of everyone's baseline state.
func _refresh_mood_label(tier: int) -> void:
	match tier:
		MoodSystem.Tier.SLUMP:
			mood_label.text = "▼ SLUMP"
			mood_label.modulate = Color(0.85, 0.25, 0.25)
			mood_label.visible = true
		MoodSystem.Tier.STREAK:
			mood_label.text = "▲ STREAK"
			mood_label.modulate = Color(1.0, 0.80, 0.10)
			mood_label.visible = true
		_:
			mood_label.text = ""
			mood_label.visible = false


func _on_goal_kick_started(_team: int, _position: Vector2) -> void:
	_show_set_piece_banner("GOAL KICK")


func _on_corner_kick_started(_team: int, _position: Vector2) -> void:
	_show_set_piece_banner("CORNER KICK")


func _on_throw_in_started(_team: int, _position: Vector2) -> void:
	_show_set_piece_banner("THROW-IN")


func _on_free_kick_started(_team: int, _position: Vector2, is_direct: bool) -> void:
	_show_set_piece_banner("FREE KICK — DIRECT" if is_direct else "FREE KICK — INDIRECT")


func _on_penalty_started(_team: int, _position: Vector2) -> void:
	_show_set_piece_banner("PENALTY")


## Only the human defending that free kick sees the hint — an attacking or
## uninvolved human has nothing to build.
func _on_defensive_wall_requested(_free_kick_pos: Vector2) -> void:
	if active_player == null or not is_instance_valid(active_player):
		return
	var defending_team: int = 1 - GameManager.set_piece_team
	if active_player.team != defending_team:
		return
	_show_wall_hint()


func _on_yellow_card_shown(player: Node, _team: int) -> void:
	var data: PlayerData = (player as HeavyPlayerController).get_meta(&"player_data", null) as PlayerData
	if data == null:
		return
	_show_set_piece_banner("[Y] YELLOW CARD — #%d %s" % [data.shirt_number, data.player_name])


func _on_red_card_shown(player: Node, _team: int, is_second_yellow: bool) -> void:
	var data: PlayerData = (player as HeavyPlayerController).get_meta(&"player_data", null) as PlayerData
	if data == null:
		return
	var label: String = "[R] RED CARD (2nd yellow)" if is_second_yellow else "[R] RED CARD"
	_show_set_piece_banner("%s — #%d %s" % [label, data.shirt_number, data.player_name])


func _on_offside_called(_offside_player: Node, _defending_team: int, _position: Vector2) -> void:
	_show_set_piece_banner("OFFSIDE")


func _show_set_piece_banner(text: String) -> void:
	set_piece_banner.text = text
	set_piece_banner.visible = true
	set_piece_banner.modulate.a = 1.0

	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()

	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_HOLD_TIME)
	_banner_tween.tween_property(set_piece_banner, "modulate:a", 0.0, BANNER_FADE_TIME)
	_banner_tween.tween_callback(func() -> void: set_piece_banner.visible = false)


func _on_substitution_made(team: int, player_out_idx: int, player_in_idx: int) -> void:
	var out_data: PlayerData = DataLoader.get_player(team, player_out_idx)
	var in_data: PlayerData = DataLoader.get_player(team, player_in_idx)
	_show_sub_banner("↓ #%d %s   ↑ #%d %s" % [
		out_data.shirt_number, out_data.player_name,
		in_data.shirt_number, in_data.player_name,
	])


## Alpha 0→1→0 over 2s total: 0.3s in, 1.4s held, 0.3s out.
func _show_sub_banner(text: String) -> void:
	_sub_banner_label.text = text
	_sub_banner_label.visible = true
	_sub_banner_label.modulate.a = 0.0

	if _sub_banner_tween != null and _sub_banner_tween.is_valid():
		_sub_banner_tween.kill()

	_sub_banner_tween = create_tween()
	_sub_banner_tween.tween_property(_sub_banner_label, "modulate:a", 1.0, 0.3)
	_sub_banner_tween.tween_interval(1.4)
	_sub_banner_tween.tween_property(_sub_banner_label, "modulate:a", 0.0, 0.3)
	_sub_banner_tween.tween_callback(func() -> void: _sub_banner_label.visible = false)


## --- Penalty shootout overlay -------------------------------------------------

func _build_shootout_overlay() -> void:
	_shootout_overlay = PanelContainer.new()
	_shootout_overlay.name = "ShootoutOverlay"
	_shootout_overlay.layout_mode = 1
	_shootout_overlay.anchors_preset = 5
	_shootout_overlay.anchor_left = 0.5
	_shootout_overlay.anchor_right = 0.5
	_shootout_overlay.offset_left = -160.0
	_shootout_overlay.offset_right = 160.0
	_shootout_overlay.offset_top = 40.0
	_shootout_overlay.offset_bottom = 130.0
	_shootout_overlay.grow_horizontal = 2
	_shootout_overlay.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.05, 0.78)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_bottom = 6.0
	_shootout_overlay.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_shootout_overlay.add_child(vbox)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	_shootout_team_a_label = Label.new()
	_shootout_team_a_label.add_theme_font_size_override("font_size", 16)
	header.add_child(_shootout_team_a_label)

	_shootout_score_label = Label.new()
	_shootout_score_label.add_theme_font_size_override("font_size", 18)
	_shootout_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shootout_score_label.custom_minimum_size = Vector2(56.0, 0.0)
	header.add_child(_shootout_score_label)

	_shootout_team_b_label = Label.new()
	_shootout_team_b_label.add_theme_font_size_override("font_size", 16)
	header.add_child(_shootout_team_b_label)

	_shootout_dots_a = _build_shootout_dot_row(vbox)
	_shootout_dots_b = _build_shootout_dot_row(vbox)

	$Root.add_child(_shootout_overlay)


func _build_shootout_dot_row(parent: VBoxContainer) -> Array[Label]:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)

	var dots: Array[Label] = []
	for i: int in range(SHOOTOUT_DOTS_PER_TEAM):
		var dot := Label.new()
		dot.text = "○"
		dot.modulate = Color(0.6, 0.6, 0.6)
		dot.add_theme_font_size_override("font_size", 16)
		row.add_child(dot)
		dots.append(dot)
	return dots


## Polled every frame rather than driven off match_phase_changed: current_phase
## cycles through PENALTY_KICK/IN_PLAY for the live moments inside each
## individual kick, so only GameManager.shootout_active stays true for the
## whole shootout. The rising edge (was false, now true) is what resets the
## overlay for a fresh shootout.
func _update_shootout_overlay() -> void:
	var active: bool = GameManager.shootout_active
	if active and not _shootout_overlay_was_active:
		_reset_shootout_overlay()
	_shootout_overlay_was_active = active
	_shootout_overlay.visible = active


func _reset_shootout_overlay() -> void:
	_shootout_team_a_label.text = _team_a_name
	_shootout_team_b_label.text = _team_b_name
	_shootout_score_label.text = "0 – 0"
	for dot: Label in _shootout_dots_a:
		dot.text = "○"
		dot.modulate = Color(0.6, 0.6, 0.6)
	for dot: Label in _shootout_dots_b:
		dot.text = "○"
		dot.modulate = Color(0.6, 0.6, 0.6)


func _on_shootout_kick_result(team: int, kick_index: int, scored: bool) -> void:
	var dots: Array[Label] = _shootout_dots_a if team == GameManager.TEAM_A else _shootout_dots_b
	if kick_index >= 0 and kick_index < dots.size():
		dots[kick_index].text = "●" if scored else "○"
		dots[kick_index].modulate = Color(0.25, 0.85, 0.3) if scored else Color(0.85, 0.25, 0.25)

	var coordinator: PenaltyShootoutCoordinator = _find_shootout_coordinator()
	if coordinator != null:
		_shootout_score_label.text = "%d – %d" % [
			coordinator.shootout_score[GameManager.TEAM_A],
			coordinator.shootout_score[GameManager.TEAM_B],
		]


## PitchScene is the parent of the CanvasLayer parent — walk up two levels,
## same as _find_referee() above.
func _find_shootout_coordinator() -> PenaltyShootoutCoordinator:
	var scene: Node = get_parent()
	if scene == null:
		return null
	return scene.get_node_or_null("PenaltyShootoutCoordinator") as PenaltyShootoutCoordinator


func _show_wall_hint() -> void:
	wall_hint_label.text = "Build wall: [G / D-Pad Up]"
	wall_hint_label.visible = true
	wall_hint_label.modulate.a = 1.0

	if _wall_hint_tween != null and _wall_hint_tween.is_valid():
		_wall_hint_tween.kill()

	_wall_hint_tween = create_tween()
	_wall_hint_tween.tween_interval(BANNER_HOLD_TIME)
	_wall_hint_tween.tween_property(wall_hint_label, "modulate:a", 0.0, BANNER_FADE_TIME)
	_wall_hint_tween.tween_callback(func() -> void: wall_hint_label.visible = false)


## --- Match Simulation Speed Panel (CPU vs CPU) --------------------------------

func _setup_sim_speed_panel() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.05, 0.88)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.24, 0.86, 0.41, 0.3)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_bottom = 6.0
	sim_speed_panel.add_theme_stylebox_override("panel", panel_style)

	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	badge_style.border_width_left = 1
	badge_style.border_width_top = 1
	badge_style.border_width_right = 1
	badge_style.border_width_bottom = 1
	badge_style.border_color = Color(1.0, 0.25, 0.25, 0.6)
	badge_style.corner_radius_top_left = 6
	badge_style.corner_radius_top_right = 6
	badge_style.corner_radius_bottom_left = 6
	badge_style.corner_radius_bottom_right = 6
	badge_style.content_margin_left = 10.0
	badge_style.content_margin_right = 10.0
	badge_style.content_margin_top = 4.0
	badge_style.content_margin_bottom = 4.0
	replay_badge_panel.add_theme_stylebox_override("panel", badge_style)

	speed_1x_btn.pressed.connect(func() -> void: GameManager.set_simulation_speed(1.0))
	speed_2x_btn.pressed.connect(func() -> void: GameManager.set_simulation_speed(2.0))
	speed_4x_btn.pressed.connect(func() -> void: GameManager.set_simulation_speed(4.0))
	speed_8x_btn.pressed.connect(func() -> void: GameManager.set_simulation_speed(8.0))
	speed_16x_btn.pressed.connect(func() -> void: GameManager.set_simulation_speed(16.0))

	replay_toggle_btn.pressed.connect(_on_replay_toggle_btn_pressed)
	stamina_toggle_btn.pressed.connect(_on_stamina_toggle_btn_pressed)
	replay_skip_btn.pressed.connect(_on_replay_skip_btn_pressed)

	sim_speed_slider.value_changed.connect(_on_speed_slider_value_changed)

	var is_sim: bool = GameManager.get_meta(&"simulate_match", false)
	set_sim_speed_panel_visible(is_sim)
	_refresh_replay_toggle_display()
	_refresh_stamina_toggle_display()


func set_sim_speed_panel_visible(is_visible: bool) -> void:
	sim_speed_panel.visible = is_visible
	if is_visible:
		_refresh_speed_display(GameManager.get_simulation_speed())
		_refresh_replay_toggle_display()
		_refresh_stamina_toggle_display()


func _on_speed_slider_value_changed(val: float) -> void:
	GameManager.set_simulation_speed(val)


func _on_simulation_speed_changed(speed: float) -> void:
	_refresh_speed_display(speed)


func _on_goal_replays_toggled(_enabled: bool) -> void:
	_refresh_replay_toggle_display()


func _on_replay_toggle_btn_pressed() -> void:
	GameManager.set_goal_replays_enabled(not GameManager.is_goal_replays_enabled())


func _on_stamina_toggle_btn_pressed() -> void:
	var current: bool = GameManager.get_meta(&"stamina_bars_always_visible", true)
	GameManager.set_meta(&"stamina_bars_always_visible", not current)
	_refresh_stamina_toggle_display()


func _refresh_replay_toggle_display() -> void:
	var enabled: bool = GameManager.is_goal_replays_enabled()
	replay_toggle_btn.text = "REPLAY: ON" if enabled else "REPLAY: OFF"
	replay_toggle_btn.modulate = Color(0.24, 0.86, 0.41) if enabled else Color(0.6, 0.6, 0.6)


func _refresh_stamina_toggle_display() -> void:
	var always_on: bool = GameManager.get_meta(&"stamina_bars_always_visible", true)
	stamina_toggle_btn.text = "STAMINA: ON" if always_on else "STAMINA: AUTO"
	stamina_toggle_btn.modulate = Color(0.24, 0.86, 0.41) if always_on else Color(0.6, 0.6, 0.6)


func _on_replay_started(_team: int, _scorer: Node = null) -> void:
	replay_overlay.visible = true


func _on_replay_ended() -> void:
	replay_overlay.visible = false


func _on_replay_skip_btn_pressed() -> void:
	var coordinator: GoalReplayCoordinator = _find_goal_replay_coordinator()
	if coordinator != null:
		coordinator.skip_replay()


func _find_goal_replay_coordinator() -> GoalReplayCoordinator:
	var scene: Node = get_parent()
	if scene == null:
		return null
	return scene.get_node_or_null("GoalReplayCoordinator") as GoalReplayCoordinator


func _refresh_speed_display(speed: float) -> void:
	if is_equal_approx(speed, roundf(speed)):
		sim_speed_value_label.text = "%dx" % int(speed)
	else:
		sim_speed_value_label.text = "%.1fx" % speed

	sim_speed_slider.set_value_no_signal(speed)

	var active_color := Color(0.24, 0.86, 0.41)
	var inactive_color := Color(0.85, 0.85, 0.85)
	speed_1x_btn.modulate = active_color if is_equal_approx(speed, 1.0) else inactive_color
	speed_2x_btn.modulate = active_color if is_equal_approx(speed, 2.0) else inactive_color
	speed_4x_btn.modulate = active_color if is_equal_approx(speed, 4.0) else inactive_color
	speed_8x_btn.modulate = active_color if is_equal_approx(speed, 8.0) else inactive_color
	speed_16x_btn.modulate = active_color if is_equal_approx(speed, 16.0) else inactive_color


func _unhandled_input(event: InputEvent) -> void:
	if replay_overlay.visible:
		if event.is_pressed() and not event.is_echo():
			var is_skip_key: bool = (event is InputEventKey) and ((event as InputEventKey).keycode == KEY_SPACE or (event as InputEventKey).keycode == KEY_ENTER or (event as InputEventKey).keycode == KEY_ESCAPE)
			var is_skip_act: bool = event.is_action_pressed(&"action_ui_accept") or event.is_action_pressed(&"action_cancel")
			if is_skip_key or is_skip_act:
				_on_replay_skip_btn_pressed()
				get_viewport().set_input_as_handled()
				return


	if not sim_speed_panel.visible:
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_1:
			GameManager.set_simulation_speed(1.0)
			get_viewport().set_input_as_handled()
		KEY_2:
			GameManager.set_simulation_speed(2.0)
			get_viewport().set_input_as_handled()
		KEY_3:
			GameManager.set_simulation_speed(4.0)
			get_viewport().set_input_as_handled()
		KEY_4:
			GameManager.set_simulation_speed(8.0)
			get_viewport().set_input_as_handled()
		KEY_5:
			GameManager.set_simulation_speed(16.0)
			get_viewport().set_input_as_handled()
		KEY_R:
			_on_replay_toggle_btn_pressed()
			get_viewport().set_input_as_handled()
		KEY_S:
			_on_stamina_toggle_btn_pressed()
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT, KEY_MINUS, KEY_KP_SUBTRACT:
			var current: float = GameManager.get_simulation_speed()
			var new_spd: float = 1.0
			if current > 8.0:
				new_spd = 8.0
			elif current > 4.0:
				new_spd = 4.0
			elif current > 2.0:
				new_spd = 2.0
			elif current > 1.0:
				new_spd = 1.0
			GameManager.set_simulation_speed(new_spd)
			get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT, KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			var cur: float = GameManager.get_simulation_speed()
			var nxt_spd: float = 16.0
			if cur < 2.0:
				nxt_spd = 2.0
			elif cur < 4.0:
				nxt_spd = 4.0
			elif cur < 8.0:
				nxt_spd = 8.0
			elif cur < 16.0:
				nxt_spd = 16.0
			GameManager.set_simulation_speed(nxt_spd)
			get_viewport().set_input_as_handled()


