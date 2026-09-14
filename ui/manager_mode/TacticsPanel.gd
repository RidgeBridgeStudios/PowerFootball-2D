##
## TacticsPanel
##
## Formation, team instructions, per-slot roles, and set-piece assignments.
##
## Writes through TeamManagementData.apply_to_team() and the manager's own
## ManagerData, which is what the quick-sim engine binds to at match time — so a
## change here genuinely reaches the match engine rather than being UI state.
##
## Depends on: CareerPanel, CareerTheme, TeamManagementData, FormationLibrary,
##             ManagerCareerProfile, CareerManager, GameEvents.
##

class_name TacticsPanel
extends CareerPanel

const FORMATIONS: Array[String] = [
	"4-4-2", "4-3-3", "4-2-3-1", "3-5-2", "5-3-2", "4-4-2 Diamond", "4-1-4-1"
]

const ROLE_CHOICES: Array[String] = [
	"GK", "CB", "LB", "RB", "DM", "CDM", "CM", "LM", "RM", "AM", "CAM", "LW", "RW", "ST"
]

var _management: TeamManagementData = null
var _selected_slot: int = -1


func title() -> String:
	return "Tactics"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var team: TeamData = club(career)
	var profile: ManagerCareerProfile = career.profile
	if team == null or profile == null:
		empty_state(host, "No club loaded.")
		return

	# Rebuilt each visit so it always reflects the live squad (a transfer or an
	# injury between visits must not leave a stale working copy behind).
	_management = TeamManagementData.from_team(team, profile.tactical)

	host.add_child(CareerTheme.card_root(_presets_card(profile, p)))
	host.add_child(CareerTheme.card_root(_formation_card(career, team, profile, p)))
	host.add_child(CareerTheme.card_root(_instructions_card(profile, p)))
	host.add_child(CareerTheme.card_root(_lineup_card(career, team, p)))
	host.add_child(CareerTheme.card_root(_set_pieces_card(career, team, p)))


func _presets_card(profile: ManagerCareerProfile, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Tactical Presets")
	body.add_child(CareerTheme.muted("Quickly switch between up to 5 complete tactical presets."))

	profile.ensure_default_presets()

	var row: HBoxContainer = CareerTheme.row()
	body.add_child(row)

	for slot_idx: int in range(5):
		var preset: Dictionary = profile.get_preset(slot_idx)
		var preset_name: String = str(preset.get("name", "Preset %d" % (slot_idx + 1)))
		var is_active: bool = (preset.get("formation", "") == _management.formation)
		var btn: Button = CareerTheme.button(preset_name, is_active)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void:
			_load_preset(profile, slot_idx)
			refresh()
		)
		row.add_child(btn)

	var save_row: HBoxContainer = CareerTheme.row()
	save_row.add_child(CareerTheme.label("Save current shape & tactics to slot:"))
	for slot_idx2: int in range(5):
		var s_btn: Button = CareerTheme.button("Save Slot %d" % (slot_idx2 + 1))
		s_btn.pressed.connect(func() -> void:
			_save_current_to_preset(profile, slot_idx2)
			refresh()
		)
		save_row.add_child(s_btn)
	body.add_child(save_row)
	return body


func _load_preset(profile: ManagerCareerProfile, slot_index: int) -> void:
	var preset: Dictionary = profile.get_preset(slot_index)
	if preset.is_empty():
		return
	var formation: String = str(preset.get("formation", "4-4-2"))
	_management.formation = formation
	profile.preferred_formation = formation
	if profile.tactical != null:
		profile.tactical.tempo = float(preset.get("tempo", 0.5))
		profile.tactical.pressing_intensity = float(preset.get("pressing_intensity", 0.5))
		profile.tactical.defensive_line = float(preset.get("defensive_line", 0.5))
		profile.tactical.width = float(preset.get("width", 0.5))
		profile.tactical.physicality = float(preset.get("physicality", 0.5))
		profile.sync_to_tactical()
	_management.apply_to_team()
	GameEvents.formation_changed.emit(GameManager.TEAM_A, formation)
	CareerManager.save_career()


func _save_current_to_preset(profile: ManagerCareerProfile, slot_index: int) -> void:
	var tac: ManagerData = profile.tactical
	var formation: String = _management.formation
	var default_name: String = "%s Setup" % formation
	var tempo: float = tac.tempo if tac != null else 0.5
	var pressing: float = tac.pressing_intensity if tac != null else 0.5
	var def_line: float = tac.defensive_line if tac != null else 0.5
	var width: float = tac.width if tac != null else 0.5
	var phys: float = tac.physicality if tac != null else 0.5

	profile.save_preset(slot_index, default_name, formation, tempo, pressing, def_line, width, phys)
	CareerManager.save_career()


func _formation_card(
	career: CareerSaveData,
	team: TeamData,
	profile: ManagerCareerProfile,
	p: CareerThemePalette
) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Formation")
	var current: String = _management.formation
	body.add_child(CareerTheme.label("Current shape: %s" % current, p.accent, p.font_size_heading))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	body.add_child(grid)

	for formation: String in FORMATIONS:
		var b: Button = CareerTheme.button(formation, formation == current)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_management.formation = formation
			profile.preferred_formation = formation
			profile.sync_to_tactical()
			_management.apply_to_team()
			# ManagerDirector listens for this and re-lays the anchors, so a
			# shape picked here is live the moment the next match binds.
			GameEvents.formation_changed.emit(GameManager.TEAM_A, formation)
			CareerManager.save_career()
			refresh()
		)
		grid.add_child(b)
	return body


func _instructions_card(profile: ManagerCareerProfile, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Team Instructions")
	var tactical: ManagerData = profile.tactical
	if tactical == null:
		body.add_child(CareerTheme.muted("No tactical profile."))
		return body

	body.add_child(CareerTheme.muted(
		"These are read by QuickSimEngine when your fixture is simulated: tempo sets the match's chance and pass volume, while pressing intensity and defensive line shape how the two sides are rated against each other."
	))
	body.add_child(_slider_row("Tempo", tactical.tempo, p,
		func(v: float) -> void: tactical.tempo = v))
	body.add_child(_slider_row("Pressing intensity", tactical.pressing_intensity, p,
		func(v: float) -> void: tactical.pressing_intensity = v))
	body.add_child(_slider_row("Defensive line", tactical.defensive_line, p,
		func(v: float) -> void: tactical.defensive_line = v))
	body.add_child(_slider_row("Width", tactical.width, p,
		func(v: float) -> void: tactical.width = v))
	body.add_child(_slider_row("Physicality", tactical.physicality, p,
		func(v: float) -> void: tactical.physicality = v))

	body.add_child(CareerTheme.divider())
	body.add_child(CareerTheme.secondary(
		"Philosophy: %s — presets above are derived from it, and editing a slider overrides that preset until the philosophy changes." % profile.philosophy_name()
	))
	return body


func _slider_row(caption: String, value: float, p: CareerThemePalette, setter: Callable) -> HBoxContainer:
	var line: HBoxContainer = CareerTheme.row()
	line.add_child(CareerTheme.cell(caption, 150, p.text_muted))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(190.0, 0.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var readout: Label = CareerTheme.label("%d%%" % int(value * 100.0), p.text_secondary)
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		readout.text = "%d%%" % int(v * 100.0)
	)
	# Persist on release rather than on every step, so dragging does not write
	# a save file per frame.
	slider.drag_ended.connect(func(_changed: bool) -> void:
		CareerManager.save_career()
	)
	line.add_child(slider)
	line.add_child(readout)
	return line


func _lineup_card(career: CareerSaveData, team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Starting XI")
	var layout: Array[Dictionary] = FormationLibrary.get_formation(_management.formation)

	var header: HBoxContainer = CareerTheme.header_row()
	body.add_child(CareerTheme.data_row_root(header))
	header.add_child(CareerTheme.cell("Slot", 44, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Role", 60, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Player", 170, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("OVR", 40, p.text_muted, HORIZONTAL_ALIGNMENT_RIGHT, p.font_size_small))
	header.add_child(CareerTheme.cell("Cond", 60, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))
	header.add_child(CareerTheme.cell("Status", 130, p.text_muted, HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small))

	for slot: int in range(_management.lineup.size()):
		var squad_index: int = _management.lineup[slot]
		if squad_index < 0 or squad_index >= team.squad.size():
			continue
		var data: PlayerData = team.squad[squad_index]
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		var selected: bool = slot == _selected_slot
		var line: HBoxContainer = CareerTheme.data_row(slot, selected)

		line.add_child(CareerTheme.cell(str(slot + 1), 44, p.text_muted))

		var role: String = _management.get_slot_role(slot)
		var role_button: Button = CareerTheme.button(role)
		role_button.custom_minimum_size = Vector2(60.0, 0.0)
		role_button.pressed.connect(func() -> void:
			var current: int = maxi(ROLE_CHOICES.find(role), 0)
			_management.set_slot_role(slot, ROLE_CHOICES[(current + 1) % ROLE_CHOICES.size()])
			_management.apply_to_team()
			CareerManager.save_career()
			refresh()
		)
		line.add_child(role_button)

		var name_button: Button = CareerTheme.button(data.player_name)
		name_button.custom_minimum_size = Vector2(170.0, 0.0)
		name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_button.pressed.connect(func() -> void:
			_selected_slot = -1 if selected else slot
			refresh()
		)
		line.add_child(name_button)

		var overall: int = data.calculate_overall_rating()
		line.add_child(CareerTheme.cell(
			str(overall), 40, CareerTheme.tint_for_rating(float(overall - 45) / 54.0),
			HORIZONTAL_ALIGNMENT_RIGHT
		))
		if state != null:
			line.add_child(CareerTheme.bar(state.condition, 56))
			var status: String = state.availability_label()
			line.add_child(CareerTheme.cell(
				status, 130, p.danger if not state.is_available() else p.text_muted,
				HORIZONTAL_ALIGNMENT_LEFT, p.font_size_small
			))
		else:
			line.add_child(CareerTheme.cell("—", 60, p.text_muted))
			line.add_child(CareerTheme.cell("—", 130, p.text_muted))
		body.add_child(CareerTheme.data_row_root(line))

		if selected:
			body.add_child(_bench_picker(career, team, slot, p))

	if layout.size() != _management.lineup.size():
		body.add_child(CareerTheme.muted(
			"Formation defines %d slots for %d selected players." % [layout.size(), _management.lineup.size()]
		))
	return body


func _bench_picker(career: CareerSaveData, team: TeamData, slot: int, p: CareerThemePalette) -> Control:
	var wrapper := PanelContainer.new()
	wrapper.add_theme_stylebox_override("panel", CareerTheme.style_box(p.header, p.corner_radius))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	wrapper.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	column.add_child(CareerTheme.muted("Replace with:"))

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	column.add_child(flow)

	for bench_slot: int in range(_management.bench.size()):
		var squad_index: int = _management.bench[bench_slot]
		if squad_index < 0 or squad_index >= team.squad.size():
			continue
		var data: PlayerData = team.squad[squad_index]
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		var available: bool = state == null or state.is_available()
		var b: Button = CareerTheme.button("%s (%s, %d)" % [
			data.player_name, data.position_role, data.calculate_overall_rating()
		])
		b.disabled = not available
		b.pressed.connect(func() -> void:
			if _management.swap(slot, bench_slot, false):
				_management.apply_to_team()
				GameEvents.lineup_changed.emit(GameManager.TEAM_A)
				CareerManager.save_career()
			_selected_slot = -1
			refresh()
		)
		flow.add_child(b)
	return wrapper


func _set_pieces_card(career: CareerSaveData, team: TeamData, p: CareerThemePalette) -> VBoxContainer:
	var body: VBoxContainer = CareerTheme.card("Set Pieces & Captaincy")

	# Best available taker for each duty, by the attribute that actually
	# governs it, so the recommendation is not cosmetic.
	body.add_child(_duty_row("Captain", _best_by(team, career, &"leadership"), p))
	body.add_child(_duty_row("Penalties", _best_by(team, career, &"composure"), p))
	body.add_child(_duty_row("Free kicks", _best_by(team, career, &"close_control"), p))
	body.add_child(_duty_row("Corners", _best_by(team, career, &"vision"), p))

	body.add_child(CareerTheme.divider())
	var captain_name: String = "None"
	for data: PlayerData in team.squad:
		if data.is_captain:
			captain_name = data.player_name
			break
	body.add_child(CareerTheme.secondary("Current captain: %s" % captain_name))
	body.add_child(CareerTheme.muted(
		"Set the captain from a player's profile on the Squad screen."
	))
	return body


func _duty_row(caption: String, suggestion: String, p: CareerThemePalette) -> HBoxContainer:
	var line: HBoxContainer = CareerTheme.row()
	line.add_child(CareerTheme.cell(caption, 120, p.text_muted))
	line.add_child(CareerTheme.label("Best available: %s" % suggestion, p.text_primary))
	return line


func _best_by(team: TeamData, career: CareerSaveData, attribute: StringName) -> String:
	var best_name: String = "—"
	var best_value: float = -1.0
	for squad_index: int in range(team.squad.size()):
		var state: PlayerCareerState = career.state_for_squad(career.user_team_index, squad_index)
		if state != null and not state.is_available():
			continue
		var data: PlayerData = team.squad[squad_index]
		var value: float = 0.0
		match attribute:
			&"leadership":
				value = data.leadership
			&"composure":
				value = data.composure
			&"close_control":
				value = data.close_control
			&"vision":
				value = data.vision
			_:
				value = 0.0
		if value > best_value:
			best_value = value
			best_name = data.player_name
	return best_name
