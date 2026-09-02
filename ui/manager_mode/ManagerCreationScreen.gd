##
## ManagerCreationScreen
##
## Career entry: pick a save slot (or load one), create a manager identity,
## choose a club that will actually have you, and agree a contract.
##
## The job list is filtered by reputation tier — an unknown manager cannot walk
## into a Continental Giant — which is what makes the background and philosophy
## choices on the previous step matter rather than being flavour.
##
## Depends on: CareerManager, CareerSerializer, ManagerCareerProfile,
##             CareerTheme, DataLoader, BoardState.
##

extends Control

enum Step { SLOT = 0, IDENTITY = 1, JOB = 2, CONTRACT = 3 }

const HUB_SCENE: String = "res://ui/manager_mode/ManagerModeRoot.tscn"
const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"

const NATIONALITIES: Array[String] = [
	"English", "Scottish", "Norwegian", "German", "Italian", "Spanish",
	"Argentine", "Portuguese", "Dutch", "Japanese", "Polish", "Croatian",
]

var _step: Step = Step.SLOT
var _slot: int = 0

var _name: String = "Alex Morgan"
var _nationality_index: int = 0
var _background: ManagerCareerProfile.Background = ManagerCareerProfile.Background.NONE
var _philosophy: ManagerCareerProfile.Philosophy = ManagerCareerProfile.Philosophy.BALANCED
var _formation_index: int = 0
var _selected_team: int = -1

var _profile: ManagerCareerProfile = null
var _content: VBoxContainer = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_shell()
	_render()


func _build_shell() -> void:
	var p: CareerThemePalette = CareerTheme.palette()

	var background := ColorRect.new()
	background.color = p.surface
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(760.0, 0.0)
	frame.add_theme_stylebox_override("panel", CareerTheme.style_box(p.panel, p.corner_radius))
	centre.add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	frame.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 9)
	margin.add_child(_content)


func _render() -> void:
	CareerTheme.clear(_content)
	match _step:
		Step.SLOT:
			_render_slots()
		Step.IDENTITY:
			_render_identity()
		Step.JOB:
			_render_jobs()
		_:
			_render_contract()


## --- Step 1: save slot ------------------------------------------------------------

func _render_slots() -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	_content.add_child(CareerTheme.title("Manager Career"))
	_content.add_child(CareerTheme.secondary("Choose a save slot to begin or continue a career."))
	_content.add_child(CareerTheme.divider())

	for summary: Dictionary in CareerSerializer.list_slots():
		var slot: int = int(summary.get("slot", 0))
		var empty: bool = bool(summary.get("empty", true))
		var row: HBoxContainer = CareerTheme.row(10)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 1)
		info.add_child(CareerTheme.label("Slot %d" % (slot + 1), p.text_primary, p.font_size_heading))
		if empty:
			info.add_child(CareerTheme.muted("Empty"))
		elif bool(summary.get("future", false)):
			info.add_child(CareerTheme.label(
				"Saved by a newer version — cannot be loaded.", p.danger, p.font_size_small
			))
		else:
			info.add_child(CareerTheme.secondary("%s — %s" % [
				String(summary.get("manager_name", "")), String(summary.get("club", ""))
			]))
			info.add_child(CareerTheme.muted("%s · Season %d%s" % [
				String(summary.get("date", "")), int(summary.get("season", 2026)),
				"  (will be migrated)" if bool(summary.get("outdated", false)) else ""
			]))
		row.add_child(info)

		if empty:
			var start: Button = CareerTheme.button("New Career", true)
			start.pressed.connect(func() -> void:
				_slot = slot
				_step = Step.IDENTITY
				_render()
			)
			row.add_child(start)
		else:
			var load_button: Button = CareerTheme.button("Continue", true)
			load_button.disabled = bool(summary.get("future", false))
			load_button.pressed.connect(func() -> void:
				if CareerManager.load_career(slot):
					get_tree().change_scene_to_file(HUB_SCENE)
			)
			row.add_child(load_button)

			var overwrite: Button = CareerTheme.button("Delete")
			overwrite.pressed.connect(func() -> void:
				CareerSerializer.delete_slot(slot)
				_render()
			)
			row.add_child(overwrite)

		_content.add_child(row)
		_content.add_child(CareerTheme.divider())

	var back: Button = CareerTheme.button("Back to Main Menu")
	back.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	)
	_content.add_child(back)


## --- Step 2: identity ---------------------------------------------------------------

func _render_identity() -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	_content.add_child(CareerTheme.title("Create Your Manager"))

	var name_row: HBoxContainer = CareerTheme.row()
	name_row.add_child(CareerTheme.cell("Name", 150, p.text_muted))
	var name_edit := LineEdit.new()
	name_edit.text = _name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(value: String) -> void:
		_name = value
	)
	name_row.add_child(name_edit)
	_content.add_child(name_row)

	_content.add_child(_option_row("Nationality", NATIONALITIES, _nationality_index,
		func(index: int) -> void:
			_nationality_index = index
	))

	_content.add_child(_option_row(
		"Playing background", ManagerCareerProfile.BACKGROUND_NAMES, int(_background),
		func(index: int) -> void:
			_background = index as ManagerCareerProfile.Background
			_render()
	))
	_content.add_child(CareerTheme.muted(
		"A stronger playing career starts you with better attributes and a higher reputation, which decides which clubs will interview you."
	))

	_content.add_child(_option_row(
		"Tactical philosophy", ManagerCareerProfile.PHILOSOPHY_NAMES, int(_philosophy),
		func(index: int) -> void:
			_philosophy = index as ManagerCareerProfile.Philosophy
			_render()
	))

	_content.add_child(_option_row(
		"Preferred formation", TacticsPanel.FORMATIONS, _formation_index,
		func(index: int) -> void:
			_formation_index = index
	))

	# Live preview of what these choices produce.
	var preview: ManagerCareerProfile = ManagerCareerProfile.make_new(
		_name, NATIONALITIES[_nationality_index], _background, _philosophy,
		TacticsPanel.FORMATIONS[_formation_index]
	)
	_content.add_child(CareerTheme.divider())
	_content.add_child(CareerTheme.muted("STARTING PROFILE"))
	var stats: HBoxContainer = CareerTheme.row(20)
	stats.add_child(CareerTheme.label("Tier: %s" % preview.tier_name(), p.accent))
	stats.add_child(CareerTheme.secondary("Reputation %d%%" % int(preview.reputation * 100.0)))
	_content.add_child(stats)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	_content.add_child(grid)
	for key: StringName in ManagerCareerProfile.ATTRIBUTE_KEYS:
		var line: HBoxContainer = CareerTheme.row(6)
		line.add_child(CareerTheme.cell(
			String(ManagerCareerProfile.ATTRIBUTE_LABELS.get(key, String(key))), 150,
			p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))
		line.add_child(CareerTheme.bar(preview.attribute(key) / 20.0, 80))
		line.add_child(CareerTheme.label(
			"%d" % int(round(preview.attribute(key))), p.text_secondary, p.font_size_small
		))
		grid.add_child(line)

	_content.add_child(CareerTheme.divider())
	var actions: HBoxContainer = CareerTheme.row()
	var back: Button = CareerTheme.button("Back")
	back.pressed.connect(func() -> void:
		_step = Step.SLOT
		_render()
	)
	actions.add_child(back)
	var next_button: Button = CareerTheme.button("Find a Club", true)
	next_button.disabled = _name.strip_edges() == ""
	next_button.pressed.connect(func() -> void:
		_profile = ManagerCareerProfile.make_new(
			_name.strip_edges(), NATIONALITIES[_nationality_index], _background, _philosophy,
			TacticsPanel.FORMATIONS[_formation_index]
		)
		_step = Step.JOB
		_render()
	)
	actions.add_child(next_button)
	_content.add_child(actions)


## --- Step 3: job selection -----------------------------------------------------------

func _render_jobs() -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	_content.add_child(CareerTheme.title("Available Positions"))
	_content.add_child(CareerTheme.secondary(
		"You are a %s manager. Clubs far above your reputation will not consider you." % _profile.tier_name()
	))
	_content.add_child(CareerTheme.divider())

	if DataLoader.league == null:
		_content.add_child(CareerTheme.muted("No league data loaded."))
		return

	var eligible: int = 0
	for team_index: int in range(DataLoader.league.teams.size()):
		var team: TeamData = DataLoader.league.teams[team_index]
		var can_apply: bool = _profile.can_apply_to(team.reputation)
		var board: BoardState = BoardState.make_for_club(team, 24000)

		var row: HBoxContainer = CareerTheme.data_row(team_index, team_index == _selected_team)
		row.add_child(CareerTheme.cell(team.team_name, 170,
			p.accent if team_index == _selected_team else (p.text_primary if can_apply else p.text_muted)))
		row.add_child(CareerTheme.cell(team.stature, 160, p.text_secondary))
		row.add_child(CareerTheme.cell(
			"Rep %d%%" % int(team.reputation * 100.0), 72, p.text_secondary
		))
		row.add_child(CareerTheme.cell(
			CareerTheme.money(team.transfer_budget), 80, p.text_secondary, HORIZONTAL_ALIGNMENT_RIGHT
		))
		row.add_child(CareerTheme.cell(
			board.expectation_label(), 190, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
		))

		if can_apply:
			eligible += 1
			var apply: Button = CareerTheme.button("Apply")
			apply.pressed.connect(func() -> void:
				_selected_team = team_index
				_step = Step.CONTRACT
				_render()
			)
			row.add_child(apply)
		else:
			row.add_child(CareerTheme.cell("Out of reach", 80, p.danger, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
		_content.add_child(CareerTheme.data_row_root(row))

	if eligible == 0:
		_content.add_child(CareerTheme.label(
			"No club will currently interview you. Try a stronger playing background.", p.warning
		))

	_content.add_child(CareerTheme.divider())
	var back: Button = CareerTheme.button("Back")
	back.pressed.connect(func() -> void:
		_step = Step.IDENTITY
		_render()
	)
	_content.add_child(back)


## --- Step 4: contract -----------------------------------------------------------------

func _render_contract() -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = DataLoader.get_team(_selected_team)
	if team == null:
		_step = Step.JOB
		_render()
		return

	var board: BoardState = BoardState.make_for_club(team, 24000)
	_content.add_child(CareerTheme.title("Contract Offer — %s" % team.team_name))
	_content.add_child(CareerTheme.secondary(
		"%s have offered you the manager's job. Here are the terms." % team.team_name
	))
	_content.add_child(CareerTheme.divider())

	_content.add_child(_term_row("Club stature", team.stature, p))
	_content.add_child(_term_row("Board expectation", board.expectation_label(), p))
	_content.add_child(_term_row("Contract length", "3 years", p))
	_content.add_child(_term_row("Transfer budget", CareerTheme.money(team.transfer_budget), p))
	_content.add_child(_term_row("Wage budget", "%s per week" % CareerTheme.money(team.wage_budget_weekly), p))
	_content.add_child(_term_row("Squad size", "%d players" % team.squad.size(), p))
	_content.add_child(_term_row("Training facilities", "Level %d of 5" % board.training_facilities, p))
	_content.add_child(_term_row("Youth facilities", "Level %d of 5" % board.youth_facilities, p))

	_content.add_child(CareerTheme.divider())
	_content.add_child(CareerTheme.muted(
		"Bonuses are paid on meeting the board's target. Fall far enough below it for long enough and you will be dismissed."
	))

	var actions: HBoxContainer = CareerTheme.row()
	var back: Button = CareerTheme.button("Consider other clubs")
	back.pressed.connect(func() -> void:
		_step = Step.JOB
		_render()
	)
	actions.add_child(back)

	var sign: Button = CareerTheme.button("Sign Contract", true)
	sign.pressed.connect(func() -> void:
		if CareerManager.start_new_career(_profile, _selected_team, _slot) != null:
			get_tree().change_scene_to_file(HUB_SCENE)
	)
	actions.add_child(sign)
	_content.add_child(actions)


## --- Helpers ---------------------------------------------------------------------------

func _term_row(caption: String, value: String, p: CareerThemePalette) -> HBoxContainer:
	var row: HBoxContainer = CareerTheme.row()
	row.add_child(CareerTheme.cell(caption, 180, p.text_muted))
	row.add_child(CareerTheme.label(value, p.text_primary))
	return row


## A labelled row of mutually exclusive choices, rendered as buttons rather
## than an OptionButton so the whole set stays visible while choosing.
func _option_row(caption: String, choices: Array[String], selected: int, on_pick: Callable) -> HBoxContainer:
	var p: CareerThemePalette = CareerTheme.palette()
	var row: HBoxContainer = CareerTheme.row(4)
	row.add_child(CareerTheme.cell(caption, 150, p.text_muted))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(flow)
	for i: int in range(choices.size()):
		var b: Button = CareerTheme.button(choices[i], i == selected)
		b.pressed.connect(func() -> void:
			on_pick.call(i)
			if _step == Step.IDENTITY:
				_render()
		)
		flow.add_child(b)
	return row
