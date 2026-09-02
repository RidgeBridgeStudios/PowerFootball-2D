##
## MatchIntroUI
##
## High-production broadcast TV presentation overlay displayed during the
## pre-match opening sequence.
## Features:
##   - Fixture Header & Competition Title Banner
##   - Match Officials & Referee Card: name, nationality, experience, and personality trait gauges
##     (Strictness, Consistency, Composure, Reputation) with analytical personality badge
##   - Home & Away Starting XI Lineup Cards: manager, formation shape, kit color accents,
##     11 starters with shirt numbers, position roles, and captaincy badges
##   - Interactive / Controller-friendly Skip Intro Button
##   - Step / Phase progression indicators
##
## Depends on: TeamData, PlayerData, RefereeData, ManagerData, GameEvents.
## Exposes: setup(team_a, team_b, ref, mgr_a, mgr_b), show_intro_phase(phase_idx),
##          hide_intro(), signal skip_requested.
##

class_name MatchIntroUI
extends CanvasLayer

signal skip_requested

enum IntroCardPhase {
	FIXTURE_TITLE = 0,
	MATCH_OFFICIALS = 1,
	HOME_LINEUP = 2,
	AWAY_LINEUP = 3,
	KICKOFF_READY = 4
}

const ACCENT_GREEN: Color = Color(0.24, 0.86, 0.41, 1.0)
const GOLD_COLOR: Color = Color(1.0, 0.82, 0.15, 1.0)
const CARD_BG_COLOR: Color = Color(0.05, 0.07, 0.06, 0.92)
const BORDER_COLOR: Color = Color(0.24, 0.86, 0.41, 0.35)

var _team_a_data: TeamData = null
var _team_b_data: TeamData = null
var _referee_data: RefereeData = null
var _manager_a_data: ManagerData = null
var _manager_b_data: ManagerData = null

var _current_phase: IntroCardPhase = IntroCardPhase.FIXTURE_TITLE
var _card_tween: Tween = null
var _is_active: bool = false

@onready var root_control: Control = $Root
@onready var fixture_banner: PanelContainer = $Root/FixtureBanner
@onready var fixture_title_label: Label = $Root/FixtureBanner/VBox/TitleLabel
@onready var fixture_subtitle_label: Label = $Root/FixtureBanner/VBox/SubtitleLabel

@onready var card_container: PanelContainer = $Root/CardContainer
@onready var officials_card: VBoxContainer = $Root/CardContainer/OfficialsCard
@onready var home_lineup_card: VBoxContainer = $Root/CardContainer/HomeLineupCard
@onready var away_lineup_card: VBoxContainer = $Root/CardContainer/AwayLineupCard
@onready var kickoff_ready_card: VBoxContainer = $Root/CardContainer/KickoffReadyCard

@onready var skip_button: Button = $Root/SkipButton
@onready var step_indicator_box: HBoxContainer = $Root/StepIndicatorBox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_control.modulate.a = 0.0
	root_control.visible = false
	skip_button.pressed.connect(_on_skip_pressed)
	_setup_card_styles()


func _setup_card_styles() -> void:
	var style_banner := StyleBoxFlat.new()
	style_banner.bg_color = Color(0.04, 0.05, 0.04, 0.94)
	style_banner.border_width_bottom = 2
	style_banner.border_color = ACCENT_GREEN
	style_banner.corner_radius_bottom_left = 8
	style_banner.corner_radius_bottom_right = 8
	style_banner.content_margin_left = 24.0
	style_banner.content_margin_right = 24.0
	style_banner.content_margin_top = 10.0
	style_banner.content_margin_bottom = 10.0
	fixture_banner.add_theme_stylebox_override("panel", style_banner)

	var style_card := StyleBoxFlat.new()
	style_card.bg_color = CARD_BG_COLOR
	style_card.border_width_left = 2
	style_card.border_width_top = 2
	style_card.border_width_right = 2
	style_card.border_width_bottom = 2
	style_card.border_color = BORDER_COLOR
	style_card.corner_radius_top_left = 8
	style_card.corner_radius_top_right = 8
	style_card.corner_radius_bottom_left = 8
	style_card.corner_radius_bottom_right = 8
	style_card.content_margin_left = 20.0
	style_card.content_margin_right = 20.0
	style_card.content_margin_top = 16.0
	style_card.content_margin_bottom = 16.0
	card_container.add_theme_stylebox_override("panel", style_card)

	var style_btn := StyleBoxFlat.new()
	style_btn.bg_color = Color(0.08, 0.10, 0.09, 0.88)
	style_btn.border_width_left = 1
	style_btn.border_width_top = 1
	style_btn.border_width_right = 1
	style_btn.border_width_bottom = 1
	style_btn.border_color = ACCENT_GREEN
	style_btn.corner_radius_top_left = 6
	style_btn.corner_radius_top_right = 6
	style_btn.corner_radius_bottom_left = 6
	style_btn.corner_radius_bottom_right = 6
	style_btn.content_margin_left = 16.0
	style_btn.content_margin_right = 16.0
	style_btn.content_margin_top = 8.0
	style_btn.content_margin_bottom = 8.0
	skip_button.add_theme_stylebox_override("normal", style_btn)
	skip_button.add_theme_color_override("font_color", ACCENT_GREEN)


func setup(
	team_a: TeamData,
	team_b: TeamData,
	referee: RefereeData,
	mgr_a: ManagerData,
	mgr_b: ManagerData
) -> void:
	_team_a_data = team_a
	_team_b_data = team_b
	_referee_data = referee
	_manager_a_data = mgr_a
	_manager_b_data = mgr_b
	_is_active = true

	var name_a: String = _team_a_data.team_name if _team_a_data != null else "Home Team"
	var name_b: String = _team_b_data.team_name if _team_b_data != null else "Away Team"

	fixture_title_label.text = "MATCHDAY • %s  VS  %s" % [name_a.to_upper(), name_b.to_upper()]
	fixture_subtitle_label.text = "POWERFOOTBALL PRE-MATCH BROADCAST PRESENTATION"

	_populate_officials_card()
	_populate_lineup_card(home_lineup_card, _team_a_data, _manager_a_data, true)
	_populate_lineup_card(away_lineup_card, _team_b_data, _manager_b_data, false)
	_populate_kickoff_ready_card()

	root_control.visible = true
	root_control.modulate.a = 0.0

	var fade_in := create_tween()
	fade_in.tween_property(root_control, "modulate:a", 1.0, 0.45)

	show_intro_phase(IntroCardPhase.FIXTURE_TITLE)


func show_intro_phase(phase: IntroCardPhase) -> void:
	_current_phase = phase
	_update_step_indicators()

	officials_card.visible = (phase == IntroCardPhase.MATCH_OFFICIALS)
	home_lineup_card.visible = (phase == IntroCardPhase.HOME_LINEUP)
	away_lineup_card.visible = (phase == IntroCardPhase.AWAY_LINEUP)
	kickoff_ready_card.visible = (phase == IntroCardPhase.KICKOFF_READY)

	card_container.visible = (phase != IntroCardPhase.FIXTURE_TITLE)

	if card_container.visible:
		if _card_tween != null and _card_tween.is_valid():
			_card_tween.kill()
		card_container.modulate.a = 0.0
		_card_tween = create_tween()
		_card_tween.tween_property(card_container, "modulate:a", 1.0, 0.35)


func hide_intro() -> void:
	_is_active = false
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()

	var fade_out := create_tween()
	fade_out.tween_property(root_control, "modulate:a", 0.0, 0.35)
	fade_out.tween_callback(func() -> void:
		root_control.visible = false
	)


func _populate_officials_card() -> void:
	for child: Node in officials_card.get_children():
		child.queue_free()

	var ref_name: String = _referee_data.referee_name if _referee_data != null else "Match Referee"
	var ref_nat: String = _referee_data.nationality if _referee_data != null else "Neutral"
	var ref_exp: int = _referee_data.experience if _referee_data != null else 50

	var header_box := HBoxContainer.new()
	header_box.add_theme_constant_override("separation", 12)
	officials_card.add_child(header_box)

	var icon_badge := Label.new()
	icon_badge.text = "⚖️"
	icon_badge.add_theme_font_size_override("font_size", 22)
	header_box.add_child(icon_badge)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	header_box.add_child(title_vbox)

	var name_lbl := Label.new()
	name_lbl.text = ref_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", GOLD_COLOR)
	title_vbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "Head Referee • %s • %d Matches Experience" % [ref_nat, ref_exp]
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	title_vbox.add_child(sub_lbl)

	var sep := HSeparator.new()
	officials_card.add_child(sep)

	# Trait gauges
	var strict_val: float = _referee_data.strictness if _referee_data != null else 0.5
	var consist_val: float = _referee_data.consistency if _referee_data != null else 0.5
	var comp_val: float = _referee_data.composure if _referee_data != null else 0.5
	var rep_val: float = _referee_data.reputation if _referee_data != null else 0.5

	var gauges_vbox := VBoxContainer.new()
	gauges_vbox.add_theme_constant_override("separation", 6)
	officials_card.add_child(gauges_vbox)

	gauges_vbox.add_child(_build_trait_bar("Foul Strictness", strict_val, _strictness_desc(strict_val)))
	gauges_vbox.add_child(_build_trait_bar("Decision Consistency", consist_val, _consistency_desc(consist_val)))
	gauges_vbox.add_child(_build_trait_bar("Composure Under Pressure", comp_val, _composure_desc(comp_val)))
	gauges_vbox.add_child(_build_trait_bar("Reputation / Authority", rep_val, _reputation_desc(rep_val)))

	# Summary descriptor badge
	var summary_panel := PanelContainer.new()
	var sum_style := StyleBoxFlat.new()
	sum_style.bg_color = Color(0.10, 0.12, 0.10, 0.8)
	sum_style.corner_radius_top_left = 4
	sum_style.corner_radius_top_right = 4
	sum_style.corner_radius_bottom_left = 4
	sum_style.corner_radius_bottom_right = 4
	sum_style.content_margin_left = 10.0
	sum_style.content_margin_right = 10.0
	sum_style.content_margin_top = 6.0
	sum_style.content_margin_bottom = 6.0
	summary_panel.add_theme_stylebox_override("panel", sum_style)

	var summary_lbl := Label.new()
	summary_lbl.text = "OFFICIATING STYLE: " + _referee_style_summary(_referee_data)
	summary_lbl.add_theme_font_size_override("font_size", 12)
	summary_lbl.add_theme_color_override("font_color", ACCENT_GREEN)
	summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_panel.add_child(summary_lbl)

	officials_card.add_child(summary_panel)


func _build_trait_bar(trait_name: String, value: float, desc: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var hbox := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = trait_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hbox.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%s (%d%%)" % [desc, int(value * 100.0)]
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", ACCENT_GREEN)
	hbox.add_child(val_lbl)
	vbox.add_child(hbox)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 6.0)

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = ACCENT_GREEN if value >= 0.5 else Color(0.7, 0.65, 0.2)
	bar_style.corner_radius_top_left = 3
	bar_style.corner_radius_top_right = 3
	bar_style.corner_radius_bottom_left = 3
	bar_style.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", bar_style)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.15, 0.13, 0.8)
	bar_bg.corner_radius_top_left = 3
	bar_bg.corner_radius_top_right = 3
	bar_bg.corner_radius_bottom_left = 3
	bar_bg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bar_bg)

	vbox.add_child(bar)
	return vbox


func _strictness_desc(val: float) -> String:
	if val > 0.75:
		return "High Strictness"
	if val > 0.45:
		return "Balanced"
	return "Leniency / Let Play Flow"


func _consistency_desc(val: float) -> String:
	if val > 0.75:
		return "Uniform Calls"
	if val > 0.45:
		return "Standard"
	return "Variable Thresholds"


func _composure_desc(val: float) -> String:
	if val > 0.75:
		return "Cool & Unfazed"
	if val > 0.45:
		return "Steady"
	return "Heats Up Quickly"


func _reputation_desc(val: float) -> String:
	if val > 0.75:
		return "Authoritative Elite"
	if val > 0.45:
		return "Respected"
	return "Emerging Official"


func _referee_style_summary(ref: RefereeData) -> String:
	if ref == null:
		return "Standard match officiating standards."
	var parts: Array[String] = []
	if ref.strictness > 0.7:
		parts.append("strict on physical contact")
	elif ref.strictness < 0.35:
		parts.append("permissive game-flow leniency")

	if ref.composure > 0.75:
		parts.append("unflappable composure under pressure")
	elif ref.composure < 0.4:
		parts.append("susceptible to match heat and atmosphere")

	if ref.unprofessionalism > 0.25:
		parts.append("known for subtle bias tendencies")
	if ref.incoherence > 0.4:
		parts.append("unpredictable sudden whistle calls")

	if parts.is_empty():
		return "Even-handed and balanced approach across both halves."
	return ", ".join(parts).capitalize() + "."


func _populate_lineup_card(
	container: VBoxContainer,
	team_data: TeamData,
	mgr_data: ManagerData,
	is_home: bool
) -> void:
	for child: Node in container.get_children():
		child.queue_free()

	if team_data == null:
		return

	# Header: Team Name, Manager, Formation
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	container.add_child(header)

	var team_title_vbox := VBoxContainer.new()
	team_title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_title_vbox.add_theme_constant_override("separation", 2)
	header.add_child(team_title_vbox)

	var team_lbl := Label.new()
	team_lbl.text = ("🏠 " if is_home else "✈️ ") + team_data.team_name.to_upper()
	team_lbl.add_theme_font_size_override("font_size", 18)
	team_lbl.add_theme_color_override("font_color", team_data.team_color)
	team_title_vbox.add_child(team_lbl)

	var mgr_str: String = "Manager: %s" % (mgr_data.manager_name if mgr_data != null and mgr_data.manager_name != "" else "Head Coach")
	var form_str: String = "Shape: %s" % (team_data.formation if team_data.formation != "" else "4-3-3")
	var sub_lbl := Label.new()
	sub_lbl.text = "%s  |  %s" % [mgr_str, form_str]
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	team_title_vbox.add_child(sub_lbl)

	var sep := HSeparator.new()
	container.add_child(sep)

	# Two-column Grid for 11 Starters
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	container.add_child(grid)

	var starters_count: int = mini(11, team_data.squad.size())
	for i: int in range(starters_count):
		var squad_idx: int = team_data.lineup_indices[i] if team_data.lineup_indices.size() == 11 else i
		var p: PlayerData = team_data.squad[squad_idx]
		var player_row := _build_lineup_row(p)
		grid.add_child(player_row)


func _build_lineup_row(p: PlayerData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var num_lbl := Label.new()
	num_lbl.text = "#%d" % p.shirt_number
	num_lbl.custom_minimum_size = Vector2(24.0, 0.0)
	num_lbl.add_theme_font_size_override("font_size", 12)
	num_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(num_lbl)

	var pos_badge := Label.new()
	pos_badge.text = "[%s]" % p.position_role
	pos_badge.custom_minimum_size = Vector2(36.0, 0.0)
	pos_badge.add_theme_font_size_override("font_size", 11)
	pos_badge.add_theme_color_override("font_color", GOLD_COLOR if p.position_role == "GK" else ACCENT_GREEN)
	row.add_child(pos_badge)

	var name_lbl := Label.new()
	var cap_tag: String = " (C)" if p.is_captain else ""
	name_lbl.text = p.player_name + cap_tag
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", GOLD_COLOR if p.is_captain else Color(0.95, 0.95, 0.95))
	row.add_child(name_lbl)

	return row


func _populate_kickoff_ready_card() -> void:
	for child: Node in kickoff_ready_card.get_children():
		child.queue_free()

	var lbl := Label.new()
	lbl.text = "⚡ TEAMS IN POSITION • COMMENCING KICKOFF"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", ACCENT_GREEN)
	kickoff_ready_card.add_child(lbl)


func _update_step_indicators() -> void:
	for i: int in range(step_indicator_box.get_child_count()):
		var dot := step_indicator_box.get_child(i) as Label
		if dot != null:
			if i == int(_current_phase):
				dot.text = "●"
				dot.modulate = ACCENT_GREEN
			else:
				dot.text = "○"
				dot.modulate = Color(0.5, 0.5, 0.5)


func _on_skip_pressed() -> void:
	skip_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return
	if not (event is InputEventKey) and not (event is InputEventJoypadButton):
		return
	if not event.is_pressed() or event.is_echo():
		return

	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.keycode == KEY_SPACE or key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			skip_requested.emit()
	elif event is InputEventJoypadButton:
		var joy_ev := event as InputEventJoypadButton
		if joy_ev.button_index == JOY_BUTTON_A or joy_ev.button_index == JOY_BUTTON_START:
			get_viewport().set_input_as_handled()
			skip_requested.emit()
