##
## PreGameScreen
##
## Full-screen pre-match setup. Hosts the modern TacticsEditor for both teams,
## displays manager cards, allows unlimited lineup/formation/individual role
## customization, and offers match simulation options ("Watch Match", "Quick Sim",
## or standard player-controlled "Kick Off").
##
## Reads: DataLoader.get_match_team(0/1), ManagerLoader.get_or_assign_manager()
## Writes: TeamManagementData.apply_to_team() for both teams before confirming.
##
## Depends on: DataLoader, ManagerLoader, GameManager, GameEvents,
##             TeamManagementData, PlayerData, ManagerData, TacticsEditor.
##

class_name PreGameScreen
extends CanvasLayer

const QuickSimModalScene: PackedScene = preload("res://ui/QuickSimModal.tscn")

@onready var sim_toggle: CheckButton = $Root/Layout/TopBar/SimulationToggle
@onready var kickoff_button: Button = $Root/Layout/TopBar/KickOffButton
@onready var quick_sim_button: Button = $Root/Layout/TopBar/QuickSimButton
@onready var vs_label: Label = $Root/Layout/TopBar/VsLabel

@onready var team_tabs: TabContainer = $Root/Layout/TeamTabs
@onready var tactics_editor_a: TacticsEditor = $Root/Layout/TeamTabs/TeamAPanel/TacticsEditorA
@onready var tactics_editor_b: TacticsEditor = $Root/Layout/TeamTabs/TeamBPanel/TacticsEditorB

var _mgmt_a: TeamManagementData = null
var _mgmt_b: TeamManagementData = null


func _ready() -> void:
	kickoff_button.pressed.connect(_on_kickoff_pressed)
	quick_sim_button.pressed.connect(_on_quick_sim_pressed)


## Builds the lineup/manager data and populates every panel. Deliberately not
## run from _ready(): this node is a static child of PitchScene and _ready()
## fires the instant the scene tree loads. PitchScene calls setup() explicitly.
func setup() -> void:
	sim_toggle.button_pressed = GameManager.get_meta(&"simulate_match", false)
	_build_management_data()
	_populate_manager_cards()
	tactics_editor_a.setup(_mgmt_a, GameManager.TEAM_A, false)
	tactics_editor_b.setup(_mgmt_b, GameManager.TEAM_B, false)


func _build_management_data() -> void:
	var team_a: TeamData = DataLoader.get_match_team(GameManager.TEAM_A)
	var team_b: TeamData = DataLoader.get_match_team(GameManager.TEAM_B)
	var mgr_a: ManagerData = ManagerLoader.get_or_assign_manager(team_a.team_name)
	var mgr_b: ManagerData = ManagerLoader.get_or_assign_manager(team_b.team_name)
	_mgmt_a = TeamManagementData.from_team(team_a, mgr_a)
	_mgmt_b = TeamManagementData.from_team(team_b, mgr_b)
	vs_label.text = "%s  vs  %s" % [team_a.team_name, team_b.team_name]
	team_tabs.set_tab_title(0, team_a.team_name + " (Home)")
	team_tabs.set_tab_title(1, team_b.team_name + " (Away)")


func _populate_manager_cards() -> void:
	_fill_manager_card(GameManager.TEAM_A, _mgmt_a.manager)
	_fill_manager_card(GameManager.TEAM_B, _mgmt_b.manager)


## Fill in manager card labels for one team.
func _fill_manager_card(team: int, m: ManagerData) -> void:
	var suffix: String = "A" if team == GameManager.TEAM_A else "B"
	var card: Node = get_node_or_null("Root/Layout/TeamTabs/Team%sPanel/Manager%sCard" % [suffix, suffix])
	if card == null:
		return

	var name_lbl := card.get_node_or_null("VBoxContainer/Manager%sName" % suffix) as Label
	if name_lbl != null:
		var nat_emoji: String = NationDatabase.get_flag_emoji(m.nationality)
		name_lbl.text = "%s Manager: %s (%s, Age: %s, %d yrs exp.)" % [
			nat_emoji, m.manager_name, m.nationality, m.get_age_detail_string(), m.experience
		]

	var tactics_lbl := card.get_node_or_null("VBoxContainer/Manager%sTactics" % suffix) as Label
	if tactics_lbl != null:
		tactics_lbl.text = "Preferred: %s  |  Playstyle: %s  |  Prized: %s" % [
			m.preferred_formation, m.preferred_playstyle, m.prized_attribute
		]

	var person_lbl := card.get_node_or_null("VBoxContainer/Manager%sPersonality" % suffix) as Label
	if person_lbl != null:
		var lang_strings: Array[String] = []
		for l: Dictionary in m.spoken_languages:
			var l_emoji: String = NationDatabase.get_flag_emoji(str(l.get("language", "")))
			lang_strings.append("%s %s (%s)" % [l_emoji, l.get("language", ""), l.get("level", "")])
		var lang_summary: String = "  |  Langs: " + (", ".join(lang_strings)) if not lang_strings.is_empty() else ""
		person_lbl.text = "Traits: " + _trait_names(m.traits) + lang_summary

	var stats: Node = card.get_node_or_null("VBoxContainer/Manager%sStats" % suffix)
	if stats != null:
		var def_l := stats.get_node_or_null("DefLabel") as Label
		if def_l != null: def_l.text = "DEF %d%%" % int(m.defensive_line * 100.0)
		var tmp_l := stats.get_node_or_null("TempoLabel") as Label
		if tmp_l != null: tmp_l.text = "TMP %d%%" % int(m.tempo * 100.0)
		var wid_l := stats.get_node_or_null("WidthLabel") as Label
		if wid_l != null: wid_l.text = "WID %d%%" % int(m.width * 100.0)
		var prs_l := stats.get_node_or_null("PressLabel") as Label
		if prs_l != null: prs_l.text = "PRS %d%%" % int(m.pressing_intensity * 100.0)


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


func _on_kickoff_pressed() -> void:
	GameManager.set_meta(&"simulate_match", sim_toggle.button_pressed)
	_mgmt_a.apply_to_team()
	_mgmt_b.apply_to_team()
	GameEvents.pregame_confirmed.emit()
	hide()


func _on_quick_sim_pressed() -> void:
	_mgmt_a.apply_to_team()
	_mgmt_b.apply_to_team()
	var team_a: TeamData = DataLoader.get_match_team(GameManager.TEAM_A)
	var team_b: TeamData = DataLoader.get_match_team(GameManager.TEAM_B)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(team_a.team_name, team_b.team_name)

	var modal: QuickSimModal = QuickSimModalScene.instantiate() as QuickSimModal
	add_child(modal)
	modal.setup_match(team_a, team_b, _mgmt_a.manager, _mgmt_b.manager, ref, _mgmt_a.lineup, _mgmt_b.lineup)
	modal.open()
	modal.modal_closed.connect(func():
		modal.queue_free()
		get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
	)
