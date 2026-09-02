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


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_panels()
	_build_shell()

	GameEvents.career_inbox_changed.connect(_on_inbox_changed)
	GameEvents.career_advance_halted.connect(_on_advance_halted)
	GameEvents.career_manager_sacked.connect(_on_sacked)

	# Returning from a played match: PitchScene parks the score on GameManager
	# and CareerManager attributes it to the pending fixture.
	if GameManager.has_meta(&"manager_last_match_result"):
		var res: Dictionary = GameManager.get_meta(&"manager_last_match_result")
		GameManager.remove_meta(&"manager_last_match_result")
		CareerManager.record_user_match_result(
			int(res.get("home_score", 0)), int(res.get("away_score", 0))
		)

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
	CareerTheme.clear(_topbar_host)
	var p: CareerThemePalette = CareerTheme.palette()
	var career: CareerSaveData = CareerManager.career
	var team: TeamData = DataLoader.get_team(career.user_team_index)
	var finances: ClubFinances = career.user_finances()

	_topbar_host.add_child(_topbar_stat(
		team.team_name if team != null else "—",
		career.profile.manager_name if career.profile != null else "", p.accent
	))
	_topbar_host.add_child(_topbar_stat(
		career.today.to_display(), career.season_label(), p.text_primary
	))

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

	var continue_button: Button = CareerTheme.button(_continue_label(), true)
	continue_button.pressed.connect(_on_continue_pressed)
	_topbar_host.add_child(continue_button)


func _continue_label() -> String:
	var career: CareerSaveData = CareerManager.career
	if career.days_until_next_fixture() == 0:
		return "Play Match"
	if career.pending_decision_count() > 0:
		return "Inbox (%d)" % career.pending_decision_count()
	return "Continue"


func _topbar_stat(value: String, caption: String, color: Color) -> Control:
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
	var career: CareerSaveData = CareerManager.career
	# A pending decision blocks Continue outright, the way FM does — otherwise
	# the deadline would silently expire while the player advanced past it.
	if career.pending_decision_count() > 0:
		show_section(Section.INBOX)
		return

	if career.days_until_next_fixture() == 0:
		if CareerManager.play_next_fixture():
			get_tree().change_scene_to_file("res://pitch/PitchScene.tscn")
		return

	var reason: int = CareerManager.continue_until_event()
	if reason == CareerManager.HaltReason.MATCH_DAY:
		show_section(Section.OVERVIEW)
	elif reason == CareerManager.HaltReason.INBOX_DECISION:
		show_section(Section.INBOX)
	else:
		refresh()


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
