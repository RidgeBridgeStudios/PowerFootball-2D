##
## PauseMenu
##
## In-game pause screen. Hosts the TacticsEditor in match mode:
## enforces max 3 substitutions per team, provides live player stamina
## visibility, interactive pitch board for formation adjustments and
## position swaps, and individual role instruction customization.
##
## Pause/resume is driven by MatchPhase: while open, GameManager.current_phase
## is held at PREGAME so is_in_play() is false and every FSM's IN_PLAY guard
## freezes physics. This menu never touches get_tree().paused — GameManager
## already runs with PROCESS_MODE_ALWAYS.
##
## To open: call open(team_a_mgmt, team_b_mgmt).
## To close: the Resume button or pressing Escape calls close().
##
## Depends on: GameManager, GameEvents, TeamManagementData, MatchWorldModel,
##             HeavyPlayerController, TacticsEditor.
## Exposes: open(mgmt_a, mgmt_b), close().
##

class_name PauseMenu
extends CanvasLayer

@onready var clock_label: Label = $Root/Window/Layout/Header/ClockLabel
@onready var score_label: Label = $Root/Window/Layout/Header/ScoreLabel
@onready var resume_btn: Button = $Root/Window/Layout/Header/ResumeButton
@onready var team_a_btn: Button = $Root/Window/Layout/Header/TeamTabs/TeamABtn
@onready var team_b_btn: Button = $Root/Window/Layout/Header/TeamTabs/TeamBBtn
@onready var tactics_editor: TacticsEditor = $Root/Window/Layout/TacticsEditor

var _mgmt_a: TeamManagementData = null
var _mgmt_b: TeamManagementData = null
var _active_team: int = GameManager.TEAM_A
var _is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	resume_btn.pressed.connect(close)
	team_a_btn.pressed.connect(func(): _switch_team(GameManager.TEAM_A))
	team_b_btn.pressed.connect(func(): _switch_team(GameManager.TEAM_B))


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
	_switch_team(GameManager.TEAM_A)
	GameEvents.pause_opened.emit()


func close() -> void:
	if _mgmt_a != null:
		_mgmt_a.apply_to_team()
	if _mgmt_b != null:
		_mgmt_b.apply_to_team()
	_is_open = false
	hide()
	GameEvents.pause_closed.emit()


func _refresh_header() -> void:
	clock_label.text = GameManager.get_clock_string()
	score_label.text = GameManager.get_score_string()
	if _mgmt_a != null and _mgmt_b != null:
		team_a_btn.text = _mgmt_a.team.team_name
		team_b_btn.text = _mgmt_b.team.team_name


func _switch_team(team: int) -> void:
	_active_team = team
	team_a_btn.button_pressed = (team == GameManager.TEAM_A)
	team_b_btn.button_pressed = (team == GameManager.TEAM_B)

	var mgmt: TeamManagementData = _mgmt_a if _active_team == GameManager.TEAM_A else _mgmt_b
	var live_players: Array[HeavyPlayerController] = _get_live_players_for_team(_active_team)
	tactics_editor.setup(mgmt, _active_team, true, live_players)


func _get_live_players_for_team(team: int) -> Array[HeavyPlayerController]:
	var result: Array[HeavyPlayerController] = []
	if MatchWorldModel.instance != null:
		for p in MatchWorldModel.instance.player_nodes:
			if is_instance_valid(p) and p.team == team:
				result.append(p)
	return result
