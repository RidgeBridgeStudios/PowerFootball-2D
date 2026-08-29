##
## PauseMenu
##
## In-game pause screen. Allows substitutions (max 3 per team per match),
## formation changes, and a read-only team sheet view.
## Pause/resume is driven by MatchPhase: while open, GameManager.current_phase
## is held at PREGAME so is_in_play() is false and every FSM's IN_PLAY guard
## freezes physics. This menu never touches get_tree().paused — GameManager
## already runs with PROCESS_MODE_ALWAYS.
## To open: call open(team_a_mgmt, team_b_mgmt).
## To close: the Resume button or pressing Escape calls close().
##
## Depends on: GameManager, GameEvents, TeamManagementData, FormationRegistry,
##             PlayerData.
## Exposes: open(mgmt_a, mgmt_b), close()
##

class_name PauseMenu
extends CanvasLayer

@onready var clock_label: Label = $Root/Window/Layout/Header/ClockLabel
@onready var score_label: Label = $Root/Window/Layout/Header/ScoreLabel
@onready var resume_btn: Button = $Root/Window/Layout/Header/ResumeButton
@onready var subs_remaining: Label = $Root/Window/Layout/Tabs/Substitutions/SubsRemainingLabel
@onready var team_a_sub_btn: Button = $Root/Window/Layout/Tabs/Substitutions/TeamTabs/TeamASubBtn
@onready var team_b_sub_btn: Button = $Root/Window/Layout/Tabs/Substitutions/TeamTabs/TeamBSubBtn
@onready var starters_list: VBoxContainer = $Root/Window/Layout/Tabs/Substitutions/SubLists/StartersScroll/StartersList
@onready var bench_list: VBoxContainer = $Root/Window/Layout/Tabs/Substitutions/SubLists/BenchScroll/BenchList
@onready var formation_picker: OptionButton = $Root/Window/Layout/Tabs/Formation/FormationPicker
@onready var formation_diagram: Control = $Root/Window/Layout/Tabs/Formation/FormationDiagram
@onready var squad_list: VBoxContainer = $Root/Window/Layout/Tabs/TeamSheet/SquadList

var _mgmt_a: TeamManagementData = null
var _mgmt_b: TeamManagementData = null
var _active_team: int = GameManager.TEAM_A

## Lineup slot selected for sub (index into mgmt.lineup). -1 = none.
var _selected_starter_slot: int = -1
var _is_open: bool = false


func _ready() -> void:
	hide()
	resume_btn.pressed.connect(close)
	team_a_sub_btn.pressed.connect(func(): _switch_sub_team(GameManager.TEAM_A))
	team_b_sub_btn.pressed.connect(func(): _switch_sub_team(GameManager.TEAM_B))
	formation_picker.item_selected.connect(_on_formation_selected)

	var formations: Array[String] = FormationRegistry.all_formations()
	formation_picker.clear()
	for f: String in formations:
		formation_picker.add_item(f)


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open(mgmt_a: TeamManagementData, mgmt_b: TeamManagementData) -> void:
	_mgmt_a = mgmt_a
	_mgmt_b = mgmt_b
	_is_open = true
	show()
	_refresh_header()
	_switch_sub_team(GameManager.TEAM_A)
	_refresh_formation_tab()
	_refresh_squad_sheet()
	GameEvents.pause_opened.emit()


func close() -> void:
	_mgmt_a.apply_to_team()
	_mgmt_b.apply_to_team()
	_is_open = false
	hide()
	GameEvents.pause_closed.emit()


func _refresh_header() -> void:
	clock_label.text = GameManager.get_clock_string()
	score_label.text = GameManager.get_score_string()
	var mgmt: TeamManagementData = _mgmt_a if _active_team == GameManager.TEAM_A else _mgmt_b
	var subs_left: int = 3 - mgmt.substitutions_used
	subs_remaining.text = "Substitutions remaining: %d / 3" % subs_left


func _switch_sub_team(team: int) -> void:
	_active_team = team
	_selected_starter_slot = -1
	_refresh_header()
	_rebuild_sub_lists()
	_refresh_formation_tab()
	_refresh_squad_sheet()


func _rebuild_sub_lists() -> void:
	var mgmt: TeamManagementData = _mgmt_a if _active_team == GameManager.TEAM_A else _mgmt_b

	for c in starters_list.get_children():
		c.queue_free()
	for c in bench_list.get_children():
		c.queue_free()

	for slot in range(mgmt.lineup.size()):
		var sq_idx: int = mgmt.lineup[slot]
		var p: PlayerData = mgmt.team.squad[sq_idx]
		var btn := Button.new()
		btn.text = "#%d  %s  [%s]  Form:%.1f  Rating:%.1f" % [
			p.shirt_number, p.player_name, p.position_role, p.form, p.last_match_rating
		]
		var s := slot
		btn.pressed.connect(func(): _on_starter_clicked(s))
		starters_list.add_child(btn)

	for bi in range(mgmt.bench.size()):
		var sq_idx: int = mgmt.bench[bi]
		var p: PlayerData = mgmt.team.squad[sq_idx]
		var btn := Button.new()
		btn.text = "#%d  %s  [%s]  Form:%.1f%s" % [
			p.shirt_number, p.player_name, p.position_role, p.form,
			"  ⚠ UNAVAILABLE" if p.is_unavailable else ""
		]
		btn.disabled = p.is_unavailable or mgmt.substitutions_used >= 3
		if p.is_unavailable:
			btn.modulate = Color(0.55, 0.55, 0.55)
		var b := bi
		btn.pressed.connect(func(): _on_bench_clicked(b))
		bench_list.add_child(btn)


func _on_starter_clicked(slot: int) -> void:
	_selected_starter_slot = slot


func _on_bench_clicked(bench_slot: int) -> void:
	if _selected_starter_slot < 0:
		return
	var mgmt: TeamManagementData = _mgmt_a if _active_team == GameManager.TEAM_A else _mgmt_b
	var player_out_idx: int = mgmt.lineup[_selected_starter_slot]
	var player_in_idx: int = mgmt.bench[bench_slot]

	if mgmt.swap(_selected_starter_slot, bench_slot, true):
		GameEvents.substitution_made.emit(_active_team, player_out_idx, player_in_idx)
		GameEvents.lineup_changed.emit(_active_team)
		_selected_starter_slot = -1
		_refresh_header()
		_rebuild_sub_lists()


func _refresh_formation_tab() -> void:
	var mgmt: TeamManagementData = _mgmt_a if _active_team == GameManager.TEAM_A else _mgmt_b
	var formations: Array[String] = FormationRegistry.all_formations()
	var idx: int = formations.find(mgmt.formation)
	formation_picker.selected = idx if idx >= 0 else 0
	formation_diagram.set_meta(&"positions", FormationRegistry.positions_for(mgmt.formation))
	formation_diagram.set_meta(&"mgmt", mgmt)
	formation_diagram.queue_redraw()


func _on_formation_selected(idx: int) -> void:
	var mgmt: TeamManagementData = _mgmt_a if _active_team == GameManager.TEAM_A else _mgmt_b
	mgmt.formation = FormationRegistry.all_formations()[idx]
	GameEvents.formation_changed.emit(_active_team, mgmt.formation)
	_refresh_formation_tab()


func _refresh_squad_sheet() -> void:
	for c in squad_list.get_children():
		c.queue_free()
	var mgmt: TeamManagementData = _mgmt_a if _active_team == GameManager.TEAM_A else _mgmt_b
	for p: PlayerData in mgmt.team.squad:
		var lbl := Label.new()
		lbl.text = "#%d  %-20s  [%s]  Spd:%.0f  Vis:%.0f  Comp:%.0f  Agg:%.0f  Form:%.1f  Goals:%d  Assists:%d%s" % [
			p.shirt_number, p.player_name, p.position_role,
			p.top_speed, p.vision * 100.0, p.composure * 100.0, p.aggression * 100.0,
			p.form, p.career_goals, p.career_assists,
			"  ⚠ UNAVAIL" if p.is_unavailable else ""
		]
		squad_list.add_child(lbl)
