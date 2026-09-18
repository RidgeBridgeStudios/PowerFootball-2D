##
## ManagerModeRoot
##
## The Manager Mode shell: FM-style dark sidebar on the left, a persistent top
## bar showing club/date/next fixture/funds, and a content pane that hosts one
## CareerPanel at a time.
##
## The whole tree is built in _ready() with containers and anchor presets
## rather than authored node-by-node in the .tscn. That is deliberate: the
## sidebar's contents depend on live career state (the inbox badge count), so
## it would have to be rebuilt in code regardless, and building the whole shell
## one way keeps layout in a single readable place.
##
## Owns navigation and the Continue loop. It does NOT own career state —
## CareerManager does, and every panel reads through it.
##
## Depends on: CareerManager, CareerTheme, CareerPanel and its subclasses,
##             GameEvents, DataLoader.
## Exposes: show_section(), refresh().
##

extends Control

enum Section {
	OVERVIEW = 0, INBOX = 1, SQUAD = 2, TACTICS = 3, TRAINING = 4,
	TRANSFERS = 5, SCOUTING = 6, STAFF = 7, FIXTURES = 8, LEAGUE = 9,
	FINANCES = 10, BOARD = 11, CALENDAR = 12,
}

const SECTION_LABELS: Array[String] = [
	"Overview", "Inbox", "Squad", "Tactics", "Training",
	"Transfers", "Scouting", "Staff", "Fixtures", "League",
	"Finances", "Board", "Calendar",
]

const CREATION_SCENE: String = "res://ui/manager_mode/ManagerCreationScreen.tscn"
const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"

var _current_section: Section = Section.OVERVIEW
var _panels: Dictionary = {}

var _nav_list: VBoxContainer = null
var _content_host: VBoxContainer = null
var _topbar_host: HBoxContainer = null
var _status_label: Label = null
var _continue_button: Button = null
var _topbar_date_value: Label = null
var _date_tween: Tween = null
var _button_pulse_tween: Tween = null
var _speed_buttons: Array[Button] = []
var _advance_dialog: AdvanceToDateDialog = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_panels()
	_build_shell()

	GameEvents.career_inbox_changed.connect(_on_inbox_changed)
	GameEvents.career_advance_halted.connect(_on_advance_halted)
	GameEvents.career_continue_started.connect(_on_continue_started)
	GameEvents.career_continue_stopped.connect(_on_continue_stopped)
	GameEvents.career_speed_changed.connect(_on_speed_changed)
	GameEvents.career_day_advanced.connect(_on_day_advanced)
	GameEvents.career_manager_sacked.connect(_on_sacked)

	if not CareerManager.is_career_active():
		# No career loaded — the creation flow owns getting one started.
		get_tree().change_scene_to_file(CREATION_SCENE)
		return

	show_section(Section.OVERVIEW)


func _build_panels() -> void:
	_panels = {
		Section.OVERVIEW: OverviewPanel.new(),
		Section.INBOX: InboxPanel.new(),
		Section.SQUAD: SquadPanel.new(),
		Section.TACTICS: TacticsPanel.new(),
		Section.TRAINING: TrainingPanel.new(),
		Section.TRANSFERS: TransfersPanel.new(),
		Section.SCOUTING: ScoutingPanel.new(),
		Section.STAFF: StaffPanel.new(),
		Section.FIXTURES: FixturesPanel.new(),
		Section.LEAGUE: LeaguePanel.new(),
		Section.FINANCES: FinancesPanel.new(),
		Section.BOARD: BoardPanel.new(),
		Section.CALENDAR: CalendarPanel.new(),
	}
	for key: int in _panels:
		var panel: CareerPanel = _panels[key] as CareerPanel
		panel.request_refresh = refresh
		panel.request_section = func(section: int) -> void:
			show_section(section as Section)


func _build_shell() -> void:
	var p: CareerThemePalette = CareerTheme.palette()

	var background := ColorRect.new()
	background.color = p.surface
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var layout := HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	layout.add_child(_build_sidebar(p))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	layout.add_child(right)

	right.add_child(_build_topbar(p))

	var content_panel := PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_panel.add_theme_stylebox_override("panel", CareerTheme.style_box(p.surface, 0))
	right.add_child(content_panel)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", p.content_margin)
	content_margin.add_theme_constant_override("margin_right", p.content_margin)
	content_margin.add_theme_constant_override("margin_top", p.content_margin)
	content_margin.add_theme_constant_override("margin_bottom", p.content_margin)
	content_panel.add_child(content_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_margin.add_child(scroll)

	_content_host = VBoxContainer.new()
	_content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_host.add_theme_constant_override("separation", 10)
	scroll.add_child(_content_host)


func _build_sidebar(p: CareerThemePalette) -> Control:
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(float(p.sidebar_width), 0.0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_stylebox_override("panel", CareerTheme.style_box(p.sidebar, 0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	sidebar.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)

	var brand: Label = CareerTheme.label("POWERFOOTBALL", p.accent, p.font_size_small)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(brand)
	var mode: Label = CareerTheme.label("MANAGER MODE", p.text_muted, p.font_size_small)
	mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(mode)
	column.add_child(CareerTheme.spacer(10))

	_nav_list = VBoxContainer.new()
	_nav_list.add_theme_constant_override("separation", 1)
	_nav_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_nav_list)

	column.add_child(CareerTheme.spacer(8))
	var save_button: Button = CareerTheme.button("Save Career")
	save_button.pressed.connect(_on_save_pressed)
	column.add_child(save_button)
	var quit_button: Button = CareerTheme.button("Main Menu")
	quit_button.pressed.connect(_on_main_menu_pressed)
	column.add_child(quit_button)
	return sidebar


func _build_topbar(p: CareerThemePalette) -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", CareerTheme.style_box(p.panel, 0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", p.content_margin)
	margin.add_theme_constant_override("margin_right", p.content_margin)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	bar.add_child(margin)

	_topbar_host = HBoxContainer.new()
	_topbar_host.add_theme_constant_override("separation", 18)
	margin.add_child(_topbar_host)
	return bar


## --- Navigation ------------------------------------------------------------------

func show_section(section: Section) -> void:
	_current_section = section
	refresh()


func refresh() -> void:
	if not CareerManager.is_career_active():
		return
	_rebuild_nav()
	_rebuild_topbar()
	_rebuild_content()


func _rebuild_nav() -> void:
	CareerTheme.clear(_nav_list)
	var career: CareerSaveData = CareerManager.career
	for i: int in range(SECTION_LABELS.size()):
		var section: Section = i as Section
		var badge: int = 0
		if section == Section.INBOX:
			badge = career.unread_inbox_count()
		var b: Button = CareerTheme.nav_button(
			SECTION_LABELS[i], section == _current_section, badge
		)
		b.pressed.connect(func() -> void:
			show_section(section)
		)
		_nav_list.add_child(b)


func _rebuild_topbar() -> void:
	_speed_buttons.clear()
	CareerTheme.clear(_topbar_host)
	var p: CareerThemePalette = CareerTheme.palette()
	var career: CareerSaveData = CareerManager.career
	var team: TeamData = DataLoader.get_team(career.user_team_index)
	var finances: ClubFinances = career.user_finances()

	_topbar_host.add_child(_topbar_stat(
		team.team_name if team != null else "—",
		career.profile.manager_name if career.profile != null else "", p.accent
	))
	var date_box: VBoxContainer = _topbar_stat(
		career.today.to_display(), career.season_label(), p.text_primary
	)
	_topbar_date_value = date_box.get_child(0) as Label
	_topbar_host.add_child(date_box)

	var fixture: FixtureData = career.next_user_fixture()
	if fixture != null:
		var opponent: TeamData = DataLoader.get_team(fixture.opponent_of(career.user_team_index))
		var days: int = career.days_until_next_fixture()
		var when: String = "Today" if days <= 0 else ("Tomorrow" if days == 1 else "in %d days" % days)
		_topbar_host.add_child(_topbar_stat(
			"%s %s" % ["v" if fixture.is_home_for(career.user_team_index) else "@",
				opponent.team_name if opponent != null else "?"],
			"%s · %s" % [fixture.competition_short(), when], p.text_primary
		))
	else:
		_topbar_host.add_child(_topbar_stat("No fixture", "Season complete", p.text_muted))

	if finances != null:
		_topbar_host.add_child(_topbar_stat(
			CareerTheme.money(finances.transfer_budget), "Transfer budget", p.text_primary
		))
		_topbar_host.add_child(_topbar_stat(
			"%s/wk" % CareerTheme.money(finances.wage_budget_weekly), "Wage budget", p.text_primary
		))

	if career.board != null:
		_topbar_host.add_child(_topbar_stat(
			career.board.confidence_label(),
			"Board confidence",
			CareerTheme.tint_for_rating(career.board.confidence)
		))

	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_topbar_host.add_child(pad)

	_status_label = CareerTheme.muted("")
	_topbar_host.add_child(_status_label)

	var advance_to_btn: Button = CareerTheme.button("Advance to...", false)
	advance_to_btn.pressed.connect(_on_advance_to_date_pressed)
	_topbar_host.add_child(advance_to_btn)

	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 0)
	var speed_group := ButtonGroup.new()
	var current_speed: int = CareerManager.get_continue_speed()

	var active_box: StyleBoxFlat = CareerTheme.style_box(p.accent_dim, p.corner_radius)
	var inactive_box: StyleBoxFlat = CareerTheme.style_box(p.panel, p.corner_radius)

	for s: int in [1, 2, 3]:
		var speed_val: int = s
		var btn: Button = CareerTheme.button("%dx" % speed_val, false)
		btn.toggle_mode = true
		btn.button_group = speed_group
		btn.custom_minimum_size = Vector2(34.0, 24.0)
		btn.add_theme_stylebox_override("pressed", active_box)
		btn.add_theme_stylebox_override("normal", inactive_box)
		btn.button_pressed = (speed_val == current_speed)
		btn.pressed.connect(func() -> void:
			CareerManager.set_continue_speed(speed_val)
		)
		speed_box.add_child(btn)
		_speed_buttons.append(btn)
	_topbar_host.add_child(speed_box)

	_continue_button = CareerTheme.button(_continue_label(), true)
	_continue_button.pressed.connect(_on_continue_pressed)
	_topbar_host.add_child(_continue_button)


func _continue_label() -> String:
	if CareerManager.is_continue_running():
		return "Stop"
	var career: CareerSaveData = CareerManager.career
	if career.days_until_next_fixture() == 0:
		return "Play Match"
	if career.pending_decision_count() > 0:
		return "Inbox (%d)" % career.pending_decision_count()
	return "Continue"


func _topbar_stat(value: String, caption: String, color: Color) -> VBoxContainer:
	var p: CareerThemePalette = CareerTheme.palette()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(CareerTheme.label(value, color, p.font_size_body))
	box.add_child(CareerTheme.label(caption, p.text_muted, p.font_size_small))
	return box


func _rebuild_content() -> void:
	CareerTheme.clear(_content_host)
	var panel: CareerPanel = _panels.get(_current_section, null) as CareerPanel
	if panel == null:
		return
	_content_host.add_child(CareerTheme.title(panel.title()))
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	_content_host.add_child(body)
	panel.build(body, CareerManager.career)


## --- Actions ----------------------------------------------------------------------

func _on_continue_pressed() -> void:
	if CareerManager.is_continue_running():
		CareerManager.cancel_continue()
		return
	var career: CareerSaveData = CareerManager.career
	if career.pending_decision_count() > 0:
		show_section(Section.INBOX)
		return
	if career.days_until_next_fixture() == 0:
		_open_matchday_modal()
		return
	CareerManager.continue_until_event()


func _open_matchday_modal() -> void:
	var career: CareerSaveData = CareerManager.career
	if career == null:
		return
	var fixture: FixtureData = career.next_user_fixture()
	if fixture == null:
		return
	var home: TeamData = DataLoader.get_team(fixture.home_team_index)
	var away: TeamData = DataLoader.get_team(fixture.away_team_index)
	if home == null or away == null:
		return

	var home_mgr: ManagerData = ManagerLoader.get_or_assign_manager(home.team_name)
	var away_mgr: ManagerData = ManagerLoader.get_or_assign_manager(away.team_name)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(home.team_name, away.team_name)
	var is_neutral: bool = (fixture.leg == 0 and fixture.round_label == "Final")

	var modal_scene: PackedScene = preload("res://ui/QuickSimModal.tscn")
	var modal: QuickSimModal = modal_scene.instantiate() as QuickSimModal
	add_child(modal)
	modal.setup_match(
		home, away, home_mgr, away_mgr, ref,
		home.lineup_indices, away.lineup_indices, is_neutral
	)
	modal.match_completed.connect(_on_matchday_modal_completed.bind(fixture))
	modal.modal_closed.connect(_on_matchday_modal_closed.bind(modal))
	modal.open()


func _on_matchday_modal_completed(sim_result: QuickSimEngine.QuickSimResult, fixture: FixtureData) -> void:
	CareerManager.apply_user_match_result(fixture, sim_result)
	refresh()


func _on_matchday_modal_closed(modal: QuickSimModal) -> void:
	refresh()
	if modal != null and is_instance_valid(modal):
		modal.queue_free()


func _on_advance_to_date_pressed() -> void:
	if CareerManager.is_continue_running():
		return
	if _advance_dialog == null:
		_advance_dialog = AdvanceToDateDialog.new()
		add_child(_advance_dialog)
		_advance_dialog.date_confirmed.connect(_on_advance_date_confirmed)
	_advance_dialog.popup_centered()


func _on_advance_date_confirmed(target: CareerDate) -> void:
	if target == null:
		return
	CareerManager.set_target_date(target)
	CareerManager.continue_until_event()


func _on_continue_started() -> void:
	if _continue_button != null and is_instance_valid(_continue_button):
		_continue_button.text = "Stop"
		_continue_button.modulate = Color(0.85, 0.85, 0.85, 1.0)
	_start_button_pulse()


func _on_continue_stopped(reason: String) -> void:
	if _continue_button != null and is_instance_valid(_continue_button):
		_continue_button.text = _continue_label()
		_continue_button.modulate = Color.WHITE
	_stop_button_pulse()
	if _status_label != null and is_instance_valid(_status_label):
		_status_label.text = reason
	refresh()


func _on_speed_changed(speed: int) -> void:
	for i: int in range(_speed_buttons.size()):
		var b: Button = _speed_buttons[i]
		if is_instance_valid(b):
			b.button_pressed = (i + 1) == speed


func _on_day_advanced(_iso_date: String) -> void:
	_animate_topbar_date()
	if _current_section == Section.CALENDAR and is_inside_tree():
		_rebuild_content()


func _animate_topbar_date() -> void:
	if _topbar_date_value == null or not is_instance_valid(_topbar_date_value):
		return
	if _date_tween != null and _date_tween.is_valid():
		_date_tween.kill()

	var new_display: String = CareerManager.career.today.to_display()
	var start_y: float = _topbar_date_value.position.y

	_date_tween = create_tween()
	_date_tween.tween_property(_topbar_date_value, ^"position:y", start_y - 8.0, 0.08)
	_date_tween.parallel().tween_property(_topbar_date_value, ^"modulate:a", 0.4, 0.08)
	_date_tween.tween_callback(func() -> void:
		_topbar_date_value.text = new_display
		_topbar_date_value.position.y = start_y + 8.0
	)
	_date_tween.tween_property(_topbar_date_value, ^"position:y", start_y, 0.08)
	_date_tween.parallel().tween_property(_topbar_date_value, ^"modulate:a", 1.0, 0.08)


func _start_button_pulse() -> void:
	if _continue_button == null or not is_instance_valid(_continue_button):
		return
	_stop_button_pulse()
	_continue_button.pivot_offset = _continue_button.size * 0.5
	_button_pulse_tween = create_tween().set_loops()
	_button_pulse_tween.tween_property(_continue_button, ^"scale", Vector2(1.04, 1.04), 0.25).set_trans(Tween.TRANS_SINE)
	_button_pulse_tween.tween_property(_continue_button, ^"scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)


func _stop_button_pulse() -> void:
	if _button_pulse_tween != null and _button_pulse_tween.is_valid():
		_button_pulse_tween.kill()
	if _continue_button != null and is_instance_valid(_continue_button):
		_continue_button.scale = Vector2.ONE


func _on_inbox_changed(_unread: int, _pending: int) -> void:
	if is_inside_tree():
		_rebuild_nav()


func _on_advance_halted(reason: String) -> void:
	if _status_label != null and is_instance_valid(_status_label):
		_status_label.text = reason


func _on_sacked(club_name: String, reason: String) -> void:
	CareerTheme.clear(_content_host)
	_content_host.add_child(CareerTheme.title("You have been dismissed"))
	_content_host.add_child(CareerTheme.paragraph(
		"%s have terminated your contract. %s" % [club_name, reason]
	))
	var b: Button = CareerTheme.button("Return to Main Menu", true)
	b.pressed.connect(_on_main_menu_pressed)
	_content_host.add_child(b)


func _on_save_pressed() -> void:
	if CareerManager.save_career() and _status_label != null and is_instance_valid(_status_label):
		_status_label.text = "Career saved."


func _on_main_menu_pressed() -> void:
	CareerManager.save_career()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
