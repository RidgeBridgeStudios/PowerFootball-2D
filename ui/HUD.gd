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
## active player is in SLUMP or STREAK — silent during NORMAL.
##
## Depends on: GameManager, GameEvents, HeavyPlayerController, MoodSystem,
##             MatchReferee.
## Exposes: bind_active_player(player)
##

class_name HUD
extends CanvasLayer

## Charge below this leaves the power meter hidden, so a tapped pass does not
## flash the bar.
const METER_VISIBILITY_THRESHOLD: float = 0.02
## Seconds the set piece banner stays fully visible before it fades.
const BANNER_HOLD_TIME: float = 1.5
const BANNER_FADE_TIME: float = 0.4

var active_player: HeavyPlayerController = null

var _banner_tween: Tween = null
var _wall_hint_tween: Tween = null
var _sub_banner_tween: Tween = null

## Built programmatically in _ready() — HUD.tscn has no spare label slot for
## this, and the set piece banner it visually echoes is reserved for restarts.
var _sub_banner_label: Label = null

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
@onready var practice_hints_panel: PanelContainer = $Root/PracticeHintsPanel
@onready var _practice_gk_label: Label = $Root/PracticeHintsPanel/VBox/GKLabel


func _ready() -> void:
	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.kickoff_started.connect(_on_kickoff_started)
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


func _process(_delta: float) -> void:
	if not practice_hints_panel.visible:
		score_label.text = GameManager.get_score_string()
		clock_label.text = GameManager.get_clock_string()
	_update_power_meter()
	_update_stamina_bar()


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

	var bar: ProgressBar = active_player.stamina_bar
	bar.value = active_player.get_stamina_ratio()
	# Red once sprint is locked out, so exhaustion reads at a glance.
	bar.modulate = Color(0.9, 0.3, 0.25) if active_player.sprint_locked else Color(0.95, 0.95, 0.95)


func _on_goal_scored(team: int) -> void:
	status_label.text = "GOAL — TEAM %s" % ("A" if team == GameManager.TEAM_A else "B")


func _on_kickoff_started() -> void:
	status_label.text = "KICKOFF"
	# TODO: replace this with a short tween-out banner rather than clearing text
	# on the next event.

	# Show referee name briefly at match start.
	var ref_node: MatchReferee = _find_referee()
	if ref_node != null and ref_node.current_data != null:
		_show_set_piece_banner("Referee: " + ref_node.current_data.referee_name)


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
