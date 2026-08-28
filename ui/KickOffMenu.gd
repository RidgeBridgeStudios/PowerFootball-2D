##
## KickOffMenu
##
## Team-selection overlay shown by MainMenu when the player picks "Kick Off".
## Lists every team from DataLoader.league.teams in two ItemLists (home/away),
## tracks a CPU/local-multiplayer mode toggle, and hands the confirmed choice
## off to GameManager as scene metadata for PitchScene to read on _ready().
##
## Depends on: DataLoader, GameManager.
## Exposes: signal menu_closed, open()
##

extends Control

signal menu_closed

const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)

@onready var btn_vs_cpu: Button = $Panel/Layout/ModeRow/VsCpuButton
@onready var btn_vs_player: Button = $Panel/Layout/ModeRow/VsPlayerButton
@onready var home_list: ItemList = $Panel/Layout/TeamRow/HomePanel/HomeList
@onready var away_list: ItemList = $Panel/Layout/TeamRow/AwayPanel/AwayList
@onready var home_selected_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeSelectedLabel
@onready var away_selected_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwaySelectedLabel
@onready var hint_label: Label = $Panel/Layout/HintLabel
@onready var btn_back: Button = $Panel/Layout/ButtonRow/BackButton
@onready var btn_confirm: Button = $Panel/Layout/ButtonRow/ConfirmButton

var home_team_index: int = -1
var away_team_index: int = -1
var vs_mode: String = "cpu"


func _ready() -> void:
	visible = false
	btn_vs_cpu.toggled.connect(_on_vs_cpu_toggled)
	btn_vs_player.toggled.connect(_on_vs_player_toggled)
	home_list.item_selected.connect(_on_home_selected)
	away_list.item_selected.connect(_on_away_selected)
	btn_back.pressed.connect(_on_back_pressed)
	btn_confirm.pressed.connect(_on_confirm_pressed)

	_populate_teams()
	_style_lists()
	_update_confirm()


## Called by MainMenu instead of just `show()` so every re-entry starts from a
## clean selection rather than remembering the last match's teams.
func open() -> void:
	visible = true
	home_team_index = -1
	away_team_index = -1
	home_list.deselect_all()
	away_list.deselect_all()
	home_selected_label.text = ""
	away_selected_label.text = ""
	_update_confirm()
	btn_vs_cpu.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"action_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _populate_teams() -> void:
	home_list.clear()
	away_list.clear()
	if DataLoader.league == null:
		return
	for team: TeamData in DataLoader.league.teams:
		home_list.add_item(team.team_name)
		home_list.set_item_custom_fg_color(home_list.item_count - 1, team.team_color)
		away_list.add_item(team.team_name)
		away_list.set_item_custom_fg_color(away_list.item_count - 1, team.team_color)


## Green focus outline on whichever ItemList currently has keyboard focus, so
## the active panel (Tab switches between them) reads at a glance.
func _style_lists() -> void:
	for list: ItemList in [home_list, away_list]:
		var focus_style := StyleBoxFlat.new()
		focus_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		focus_style.border_width_left = 2
		focus_style.border_width_top = 2
		focus_style.border_width_right = 2
		focus_style.border_width_bottom = 2
		focus_style.border_color = ACCENT_COLOR
		focus_style.corner_radius_top_left = 4
		focus_style.corner_radius_top_right = 4
		focus_style.corner_radius_bottom_right = 4
		focus_style.corner_radius_bottom_left = 4
		list.add_theme_stylebox_override("focus", focus_style)


func _on_vs_cpu_toggled(pressed: bool) -> void:
	if pressed:
		vs_mode = "cpu"


func _on_vs_player_toggled(pressed: bool) -> void:
	if pressed:
		vs_mode = "local"


func _on_home_selected(index: int) -> void:
	home_team_index = index
	var team: TeamData = DataLoader.get_team(index)
	home_selected_label.text = team.team_name if team != null else ""
	_update_confirm()


func _on_away_selected(index: int) -> void:
	away_team_index = index
	var team: TeamData = DataLoader.get_team(index)
	away_selected_label.text = team.team_name if team != null else ""
	_update_confirm()


func _update_confirm() -> void:
	var both_selected: bool = home_team_index != -1 and away_team_index != -1
	btn_confirm.disabled = not both_selected
	hint_label.text = "KICK OFF ready!" if both_selected else "Select both teams to continue"
	if both_selected:
		btn_confirm.grab_focus()


func _on_confirm_pressed() -> void:
	GameManager.set_meta(&"home_team_index", home_team_index)
	GameManager.set_meta(&"away_team_index", away_team_index)
	GameManager.set_meta(&"vs_mode", vs_mode)
	GameManager.set_meta(&"practice_mode", false)
	get_tree().change_scene_to_file("res://pitch/PitchScene.tscn")


func _on_back_pressed() -> void:
	menu_closed.emit()
