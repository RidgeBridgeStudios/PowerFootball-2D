##
## PreGameScreen
##
## Full-screen pre-match setup. Shows both teams' manager cards, formation
## pickers, lineup editors (click-to-swap), and bench. Emits
## GameEvents.pregame_confirmed when the user clicks Kick Off.
## Reads: DataLoader.get_team(0/1), ManagerLoader.get_or_assign_manager()
## Writes: TeamManagementData.apply_to_team() for both teams before confirming.
##
## Depends on: DataLoader, ManagerLoader, GameManager, GameEvents,
##             TeamManagementData, FormationRegistry, PlayerData, ManagerData.
## Exposes: nothing external — hidden via hide() once Kick Off is pressed.
##

class_name PreGameScreen
extends CanvasLayer

@onready var formation_picker_a: OptionButton = $Root/MainLayout/TeamAPanel/FormationPickerA
@onready var formation_picker_b: OptionButton = $Root/MainLayout/TeamBPanel/FormationPickerB
@onready var lineup_list_a: VBoxContainer = $Root/MainLayout/TeamAPanel/LineupScrollA/LineupListA
@onready var lineup_list_b: VBoxContainer = $Root/MainLayout/TeamBPanel/LineupScrollB/LineupListB
@onready var bench_list_a: VBoxContainer = $Root/MainLayout/TeamAPanel/BenchScrollA/BenchListA
@onready var bench_list_b: VBoxContainer = $Root/MainLayout/TeamBPanel/BenchScrollB/BenchListB
@onready var formation_diagram_a: Control = $Root/MainLayout/TeamAPanel/FormationDiagramA
@onready var formation_diagram_b: Control = $Root/MainLayout/TeamBPanel/FormationDiagramB
@onready var sim_toggle: CheckButton = $Root/MainLayout/CentrePanel/SimulationToggle
@onready var kickoff_button: Button = $Root/MainLayout/CentrePanel/KickOffButton
@onready var team_a_name: Label = $Root/MainLayout/TeamAPanel/TeamAName
@onready var team_b_name: Label = $Root/MainLayout/TeamBPanel/TeamBName
@onready var vs_label: Label = $Root/MainLayout/CentrePanel/VsLabel

var _mgmt_a: TeamManagementData = null
var _mgmt_b: TeamManagementData = null
var _selected_lineup_slot: int = -1
var _selected_team: int = -1


func _ready() -> void:
	kickoff_button.pressed.connect(_on_kickoff_pressed)


## Builds the lineup/manager data and populates every panel. Deliberately not
## run from _ready(): this node is a static child of PitchScene and _ready()
## fires the instant the scene tree loads, before PitchScene even knows
## whether this is a full match or Practice Arena — calling
## ManagerLoader.get_or_assign_manager() that early would permanently assign
## managers during practice sessions, which never touched that state before.
## PitchScene calls this explicitly, only on the full-match path, right
## before show().
func setup() -> void:
	_build_management_data()
	_populate_manager_cards()
	_populate_formation_pickers()
	_rebuild_lineup_lists()


func _build_management_data() -> void:
	var team_a: TeamData = DataLoader.get_match_team(GameManager.TEAM_A)
	var team_b: TeamData = DataLoader.get_match_team(GameManager.TEAM_B)
	var mgr_a: ManagerData = ManagerLoader.get_or_assign_manager(team_a.team_name)
	var mgr_b: ManagerData = ManagerLoader.get_or_assign_manager(team_b.team_name)
	_mgmt_a = TeamManagementData.from_team(team_a, mgr_a)
	_mgmt_b = TeamManagementData.from_team(team_b, mgr_b)
	team_a_name.text = team_a.team_name
	team_b_name.text = team_b.team_name
	vs_label.text = "%s vs %s" % [team_a.team_name, team_b.team_name]


func _populate_manager_cards() -> void:
	_fill_manager_card(GameManager.TEAM_A, _mgmt_a.manager)
	_fill_manager_card(GameManager.TEAM_B, _mgmt_b.manager)


## Fill in all manager card labels for one team. Reads ManagerData.traits bitmask
## and converts bits to human-readable names (see ManagerData for the bitmask).
func _fill_manager_card(team: int, m: ManagerData) -> void:
	var suffix: String = "A" if team == GameManager.TEAM_A else "B"
	var card: Panel = get_node("Root/MainLayout/Team%sPanel/Manager%sCard" % [suffix, suffix])

	card.get_node("VBoxContainer/Manager%sName" % suffix).text = \
		"%s (%s, %d yrs exp.)" % [m.manager_name, m.nationality, m.experience]
	card.get_node("VBoxContainer/Manager%sTactics" % suffix).text = \
		"Preferred: %s  |  Playstyle: %s  |  Prized: %s" % [
			m.preferred_formation, m.preferred_playstyle, m.prized_attribute]
	card.get_node("VBoxContainer/Manager%sPersonality" % suffix).text = \
		"Traits: " + _trait_names(m.traits)

	var stats: HBoxContainer = card.get_node("VBoxContainer/Manager%sStats" % suffix)
	stats.get_node("DefLabel").text = "DEF %d%%" % int(m.defensive_line * 100.0)
	stats.get_node("TempoLabel").text = "TMP %d%%" % int(m.tempo * 100.0)
	stats.get_node("WidthLabel").text = "WID %d%%" % int(m.width * 100.0)
	stats.get_node("PressLabel").text = "PRS %d%%" % int(m.pressing_intensity * 100.0)


func _trait_names(traits: int) -> String:
	var names: Array[String] = []
	var map: Dictionary = {
		1: "Hot-Head", 2: "Loyalist", 4: "Pragmatist", 8: "Visionary",
		16: "Disciplinarian", 32: "Mind Games", 64: "Sentimental", 128: "Media Savvy",
		256: "Volatile", 512: "Idealist",
	}
	for bit: int in map.keys():
		if traits & bit:
			names.append(map[bit])
	return ", ".join(names) if names.size() > 0 else "None"


func _populate_formation_pickers() -> void:
	var formations: Array[String] = FormationRegistry.all_formations()
	for picker: OptionButton in [formation_picker_a, formation_picker_b]:
		picker.clear()
		for f: String in formations:
			picker.add_item(f)

	formation_picker_a.selected = _index_of(_mgmt_a.formation)
	formation_picker_b.selected = _index_of(_mgmt_b.formation)

	formation_picker_a.item_selected.connect(func(idx: int): _on_formation_changed(GameManager.TEAM_A, idx))
	formation_picker_b.item_selected.connect(func(idx: int): _on_formation_changed(GameManager.TEAM_B, idx))


func _index_of(formation: String) -> int:
	var list: Array[String] = FormationRegistry.all_formations()
	var idx: int = list.find(formation)
	return idx if idx >= 0 else 0


func _on_formation_changed(team: int, idx: int) -> void:
	var mgmt: TeamManagementData = _mgmt_a if team == GameManager.TEAM_A else _mgmt_b
	mgmt.formation = FormationRegistry.all_formations()[idx]
	_rebuild_formation_diagram(team)
	GameEvents.formation_changed.emit(team, mgmt.formation)


## Rebuild both lineup lists (starters + bench) for both teams.
func _rebuild_lineup_lists() -> void:
	_rebuild_team_lists(GameManager.TEAM_A, _mgmt_a, lineup_list_a, bench_list_a)
	_rebuild_team_lists(GameManager.TEAM_B, _mgmt_b, lineup_list_b, bench_list_b)
	_rebuild_formation_diagram(GameManager.TEAM_A)
	_rebuild_formation_diagram(GameManager.TEAM_B)


## Clears and repopulates one team's starter and bench VBoxContainers with
## player card Buttons. Clicking a starter then a bench player swaps them;
## clicking two starters reshuffles them.
func _rebuild_team_lists(
	team: int, mgmt: TeamManagementData,
	starter_list: VBoxContainer, bench_list_box: VBoxContainer
) -> void:
	for child in starter_list.get_children():
		child.queue_free()
	for child in bench_list_box.get_children():
		child.queue_free()

	for slot in range(mgmt.lineup.size()):
		var squad_idx: int = mgmt.lineup[slot]
		var p: PlayerData = mgmt.team.squad[squad_idx]
		var card: Button = _make_player_card(p, false)
		var s := slot
		card.pressed.connect(func(): _on_starter_clicked(team, s))
		starter_list.add_child(card)

	for bi in range(mgmt.bench.size()):
		var squad_idx: int = mgmt.bench[bi]
		var p: PlayerData = mgmt.team.squad[squad_idx]
		var card: Button = _make_player_card(p, true)
		var b := bi
		card.pressed.connect(func(): _on_bench_clicked(team, b))
		bench_list_box.add_child(card)


## Build a single player card Button. Shows shirt number, name, position,
## form, and key attributes. Greys out unavailable players.
func _make_player_card(p: PlayerData, is_bench: bool) -> Button:
	var btn := Button.new()
	btn.text = "#%d %s  [%s]  Form: %.1f  |  Spd:%.0f  Vis:%.0f  Comp:%.0f  Agg:%.0f%s" % [
		p.shirt_number, p.player_name, p.position_role, p.form,
		p.top_speed, p.vision * 100.0, p.composure * 100.0, p.aggression * 100.0,
		"  ⚠ UNAVAILABLE" if p.is_unavailable else ""
	]
	btn.disabled = p.is_unavailable and is_bench
	if p.is_unavailable:
		btn.modulate = Color(0.5, 0.5, 0.5, 1.0)
	return btn


func _on_starter_clicked(team: int, lineup_slot: int) -> void:
	if _selected_team == team and _selected_lineup_slot >= 0:
		# Second click on starters - reshuffle (pre-match only, not a substitution).
		var mgmt: TeamManagementData = _mgmt_a if team == GameManager.TEAM_A else _mgmt_b
		mgmt.reshuffle(_selected_lineup_slot, lineup_slot)
		_clear_selection()
		_rebuild_lineup_lists()
		GameEvents.lineup_changed.emit(team)
	else:
		_selected_team = team
		_selected_lineup_slot = lineup_slot


func _on_bench_clicked(team: int, bench_slot: int) -> void:
	if _selected_team == team and _selected_lineup_slot >= 0:
		var mgmt: TeamManagementData = _mgmt_a if team == GameManager.TEAM_A else _mgmt_b
		var out_idx: int = mgmt.lineup[_selected_lineup_slot]
		var in_idx: int = mgmt.bench[bench_slot]
		if mgmt.swap(_selected_lineup_slot, bench_slot, false):
			GameEvents.substitution_made.emit(team, out_idx, in_idx)
			_clear_selection()
			_rebuild_lineup_lists()
			GameEvents.lineup_changed.emit(team)
	else:
		_clear_selection()


func _clear_selection() -> void:
	_selected_lineup_slot = -1
	_selected_team = -1


func _rebuild_formation_diagram(team: int) -> void:
	var diagram: Control = formation_diagram_a if team == GameManager.TEAM_A else formation_diagram_b
	var mgmt: TeamManagementData = _mgmt_a if team == GameManager.TEAM_A else _mgmt_b
	diagram.set_meta(&"positions", FormationRegistry.positions_for(mgmt.formation))
	diagram.set_meta(&"mgmt", mgmt)
	diagram.queue_redraw()


func _on_kickoff_pressed() -> void:
	GameManager.set_meta(&"simulate_match", sim_toggle.button_pressed)
	_mgmt_a.apply_to_team()
	_mgmt_b.apply_to_team()
	GameEvents.pregame_confirmed.emit()
	hide()
