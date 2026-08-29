##
## ManagerDirector
##
## The live match brain for one team. Reads ManagerData once at bind() time to
## configure formations and PlayerBrain parameters, then monitors the
## scoreline to shift shape once per half-game threshold. It never writes to a
## PlayerBrain inside _process or _physics_process — formation and tactics are
## an initialisation/event concern here, driven entirely off GameEvents and a
## once-per-goal read of GameManager's score and clock.
##
## Depends on: ManagerData, FormationLibrary, GameManager, GameEvents,
##             HeavyPlayerController, PlayerBrain, PitchBoundary.
## Exposes: bind(), get_active_formation(), get_data().
##

class_name ManagerDirector
extends Node

var _data: ManagerData = null
var _team: int = -1
var _players_node: Node2D = null
var _boundary: PitchBoundary = null

## Formation currently in use. May differ from _data.preferred_formation if a
## tactical shift has occurred.
var _active_formation: String = ""
## Formations to shift to when losing/winning late — computed once at bind()
## time so the Idealist override never needs to touch the ManagerData Resource
## itself.
var _atk_formation: String = ""
var _def_formation: String = ""

var _shifted_to_attack: bool = false
var _shifted_to_defend: bool = false
## Runtime pressing intensity — HotHead trait raises this after two conceded.
var _live_pressing: float = 0.5
## Tracks how many goals have been conceded this match (for HotHead).
var _goals_conceded: int = 0

## Per-role formation_ball_weight band that tempo is lerped across. Keeps
## defenders holding their line and attackers pushing up at any tempo
## setting, instead of tempo flattening every role to the same drift —
## the goalkeeper's band is fixed narrow since team tempo shouldn't drag
## the keeper out of position.
const _BALL_WEIGHT_RANGE_BY_ROLE: Dictionary = {
	PlayerBrain.Role.OUTFIELD_DEFENDER: Vector2(0.05, 0.25),
	PlayerBrain.Role.OUTFIELD_MIDFIELDER: Vector2(0.15, 0.45),
	PlayerBrain.Role.OUTFIELD_ATTACKER: Vector2(0.25, 0.65),
	PlayerBrain.Role.GOALKEEPER: Vector2(0.05, 0.05),
}


func bind(data: ManagerData, team: int, players_node: Node2D, boundary: PitchBoundary) -> void:
	_data = data
	_team = team
	_players_node = players_node
	_boundary = boundary

	_shifted_to_attack = false
	_shifted_to_defend = false
	_live_pressing = data.pressing_intensity
	_goals_conceded = 0

	# Idealist (512): never changes tactical stance — both shift targets
	# collapse onto the preferred formation so _check_formation_shift() has
	# nowhere else to go.
	if data.has_trait(512):
		_atk_formation = data.preferred_formation
		_def_formation = data.preferred_formation
	else:
		_atk_formation = data.attacking_formation
		_def_formation = data.defensive_formation

	_active_formation = data.preferred_formation

	if not GameEvents.goal_scored.is_connected(_on_goal_scored):
		GameEvents.goal_scored.connect(_on_goal_scored)
	if not GameEvents.kickoff_confirmed.is_connected(_on_kickoff_confirmed):
		GameEvents.kickoff_confirmed.connect(_on_kickoff_confirmed)

	_apply_formation(_active_formation)
	_apply_brain_overrides()


func _apply_formation(formation_name: String) -> void:
	if _boundary == null or _players_node == null:
		return

	var layout: Array[Dictionary] = FormationLibrary.get_formation(formation_name)
	var pitch_centre: Vector2 = _boundary.get_centre_spot()

	var team_players: Array[HeavyPlayerController] = []
	for node: Node in _players_node.get_children():
		var player := node as HeavyPlayerController
		if player != null and player.team == _team:
			team_players.append(player)
	var by_squad_index := func(a: HeavyPlayerController, b: HeavyPlayerController) -> bool:
		return a.squad_index < b.squad_index
	team_players.sort_custom(by_squad_index)

	for i: int in range(team_players.size()):
		var player: HeavyPlayerController = team_players[i]
		if player.brain == null:
			continue

		var slot_index: int = clampi(i, 0, layout.size() - 1)
		var slot: Dictionary = layout[slot_index]
		var offset: Vector2 = slot["anchor_offset"]

		var anchor: Vector2 = pitch_centre + offset if _team == GameManager.TEAM_A else pitch_centre - offset
		player.brain.formation_anchor = anchor

		# Convenience tag for career mode UI only — does not affect physics.
		var pdata: PlayerData = player.get_meta(&"player_data", null) as PlayerData
		if pdata != null:
			pdata.position_role = slot["role"]


func _apply_brain_overrides() -> void:
	if _data == null or _players_node == null:
		return

	var pitch_centre: Vector2 = _boundary.get_centre_spot() if _boundary != null else Vector2.ZERO

	for node: Node in _players_node.get_children():
		var player := node as HeavyPlayerController
		if player == null or player.team != _team:
			continue
		var brain: PlayerBrain = player.brain
		if brain == null:
			continue

		# a) Tempo -> formation_ball_weight, scaled within this player's role
		# band so tempo never flattens defenders and attackers to the same
		# drift.
		var weight_range: Vector2 = _BALL_WEIGHT_RANGE_BY_ROLE.get(
			brain.role, Vector2(0.15, 0.65))
		brain.formation_ball_weight = lerpf(weight_range.x, weight_range.y, _data.tempo)

		# b) Live pressing -> aggression + decision_interval.
		brain.aggression_attribute = clampf(
			brain.aggression_attribute + (_live_pressing - 0.5) * 0.20, 0.0, 1.0)
		brain.decision_interval = lerpf(0.35, 0.15, _live_pressing)

		# c) Physicality -> additional aggression boost.
		brain.aggression_attribute = clampf(
			brain.aggression_attribute + (_data.physicality - 0.5) * 0.15, 0.0, 1.0)

		# d) Visionary (8): midfield players within 300px of pitch centre X get
		# an extra ball-weight bump — they're trusted to carry the system.
		if _data.has_trait(8) and absf(brain.formation_anchor.x - pitch_centre.x) <= 300.0:
			brain.formation_ball_weight = minf(brain.formation_ball_weight + 0.10, 0.75)

		# e) Disciplinarian (16): composure floor.
		if _data.has_trait(16):
			brain.composure_attribute = maxf(brain.composure_attribute, 0.40)


## Reads GameManager.score and GameManager.match_time. Evaluates once per goal
## event — never per-frame.
func _check_formation_shift() -> void:
	if _data == null:
		return

	var our_score: int = GameManager.score[_team]
	var their_score: int = GameManager.score[1 - _team]
	var diff: int = our_score - their_score
	var time_left: float = GameManager.match_duration - GameManager.match_time
	var late_game: bool = time_left < GameManager.match_duration * 0.30

	# Pragmatist (4) shifts to defend at +1 goal lead instead of +2.
	var defend_threshold: int = 1 if _data.has_trait(4) else 2

	if diff <= -1 and late_game and not _shifted_to_attack:
		_shift_to(_atk_formation)
		_shifted_to_attack = true
	elif diff >= defend_threshold and late_game and not _shifted_to_defend:
		_shift_to(_def_formation)
		_shifted_to_defend = true


func _shift_to(formation_name: String) -> void:
	if formation_name == _active_formation:
		return

	_active_formation = formation_name
	_apply_formation(formation_name)
	_apply_brain_overrides()

	# Volatile (256): randomise live pressing after a shape shift.
	if _data.has_trait(256):
		_live_pressing = clampf(_live_pressing + randf_range(-0.15, 0.15), 0.0, 1.0)
		_apply_brain_overrides()

	GameEvents.manager_formation_changed.emit(_team, formation_name)


func _on_goal_scored(scoring_team: int) -> void:
	if _data == null:
		return

	if scoring_team != _team:
		_goals_conceded += 1
		# HotHead (1): after the second goal conceded, escalate pressing.
		if _data.has_trait(1) and _goals_conceded >= 2:
			_live_pressing = clampf(_live_pressing + 0.20, 0.0, 1.0)
			_apply_brain_overrides()

	_check_formation_shift()


func _on_kickoff_confirmed(_kickoff_team: int) -> void:
	# Players were repositioned for kickoff — re-apply formation anchors.
	_apply_formation(_active_formation)


func get_active_formation() -> String:
	return _active_formation


func get_data() -> ManagerData:
	return _data
