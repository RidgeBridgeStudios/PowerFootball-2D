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
## Also runs the macro Team Match Urgency evaluator on a ~1s tick (see
## "Macro match urgency" below) and publishes it via
## GameEvents.team_urgency_updated — MatchWorldModel caches it, PlayerBrain's
## PassUtilityScorer/FormationAnchorMath call sites read the cache. Within
## that same tick, a one-shot emergency-tactics escalation can force urgency
## to +1.0 and emit GameEvents.emergency_tactics_triggered — see
## _evaluate_tactical_urgency().
##
## Depends on: ManagerData, FormationLibrary, GameManager, GameEvents,
##             MatchWorldModel, HeavyPlayerController, PlayerBrain, PitchBoundary.
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
## One-shot, like the two flags above: fires GameEvents.
## emergency_tactics_triggered and forces team_urgency to +1.0 (see
## _evaluate_tactical_urgency()) the first time this team is trailing in
## Game-Crunch, then never again this match.
var _emergency_tactics_triggered: bool = false
## Runtime pressing intensity — HotHead trait raises this after two conceded.
var _live_pressing: float = 0.5
## Tracks how many goals have been conceded this match (for HotHead).
var _goals_conceded: int = 0

## --- Macro match urgency (Layer 2 tactical evaluator) -----------------------
## Low-frequency (~1s) tick that turns scoreline + elapsed time + this
## manager's risk disposition into a published Team Match Urgency scalar —
## see POWERFOOTBALL_MASTER_VISION.md and the architecture plan for the full
## derivation. GameEvents.team_urgency_updated is the only output; everything
## downstream (PassUtilityScorer/FormationAnchorMath call sites in
## PlayerBrain) reads the cached value off MatchWorldModel.team_urgency.
const URGENCY_TICK_INTERVAL: float = 1.0
const TIME_ACCEL_K: float = 1.35
## Minimum change worth publishing — avoids GameEvents spam while urgency is
## still converging toward an unchanged target.
const URGENCY_PUBLISH_EPSILON: float = 0.01

var _urgency_eval_timer: float = 0.0
## Derived once at bind() time from this manager's tempo/pressing_intensity
## sliders and traits (ManagerData has no dedicated risk field — see
## AGENTS_ERRATA.md's "manager risk profile is derived, not authored" entry).
## Bounded to the architecture plan's [-0.35, 0.35] band: negative = pragmatic/
## defensive, positive = hyper-aggressive.
var _risk_profile: float = 0.0

const _ROLE_CONFIGS: Dictionary = {
	"CB": preload("res://shared/roles/role_cb.tres"),
	"LB": preload("res://shared/roles/role_lb.tres"),
	"RB": preload("res://shared/roles/role_rb.tres"),
	"DM": preload("res://shared/roles/role_dm.tres"),
	"CDM": preload("res://shared/roles/role_cdm.tres"),
	"CM": preload("res://shared/roles/role_cm.tres"),
	"LM": preload("res://shared/roles/role_lm.tres"),
	"RM": preload("res://shared/roles/role_rm.tres"),
	"LW": preload("res://shared/roles/role_lw.tres"),
	"RW": preload("res://shared/roles/role_rw.tres"),
	"AM": preload("res://shared/roles/role_am.tres"),
	"CAM": preload("res://shared/roles/role_am.tres"),
	"ST": preload("res://shared/roles/role_st.tres"),
	"CF": preload("res://shared/roles/role_st.tres"),
}

const _ROLE_ENUM_MAP: Dictionary = {
	"GK": PlayerBrain.Role.GOALKEEPER,
	"CB": PlayerBrain.Role.OUTFIELD_DEFENDER,
	"LB": PlayerBrain.Role.OUTFIELD_DEFENDER,
	"RB": PlayerBrain.Role.OUTFIELD_DEFENDER,
	"DM": PlayerBrain.Role.OUTFIELD_MIDFIELDER,
	"CDM": PlayerBrain.Role.OUTFIELD_MIDFIELDER,
	"CM": PlayerBrain.Role.OUTFIELD_MIDFIELDER,
	"LM": PlayerBrain.Role.OUTFIELD_MIDFIELDER,
	"RM": PlayerBrain.Role.OUTFIELD_MIDFIELDER,
	"LW": PlayerBrain.Role.OUTFIELD_ATTACKER,
	"RW": PlayerBrain.Role.OUTFIELD_ATTACKER,
	"AM": PlayerBrain.Role.OUTFIELD_ATTACKER,
	"CAM": PlayerBrain.Role.OUTFIELD_ATTACKER,
	"ST": PlayerBrain.Role.OUTFIELD_ATTACKER,
	"CF": PlayerBrain.Role.OUTFIELD_ATTACKER,
}

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
	_emergency_tactics_triggered = false
	_live_pressing = data.pressing_intensity
	_goals_conceded = 0
	_risk_profile = _compute_risk_profile(data)
	_urgency_eval_timer = 0.0

	# Idealist (512): never changes tactical stance — both shift targets
	# collapse onto the preferred formation so _check_formation_shift() has
	# nowhere else to go.
	if data.has_trait(512):
		_atk_formation = data.preferred_formation
		_def_formation = data.preferred_formation
	else:
		_atk_formation = data.attacking_formation
		_def_formation = data.defensive_formation

	var match_team: TeamData = DataLoader.get_match_team(team)
	if match_team != null and match_team.formation_override != "":
		_active_formation = match_team.formation_override
	else:
		_active_formation = data.preferred_formation

	if not GameEvents.goal_scored.is_connected(_on_goal_scored):
		GameEvents.goal_scored.connect(_on_goal_scored)
	if not GameEvents.kickoff_confirmed.is_connected(_on_kickoff_confirmed):
		GameEvents.kickoff_confirmed.connect(_on_kickoff_confirmed)
	if not GameEvents.formation_changed.is_connected(_on_user_formation_changed):
		GameEvents.formation_changed.connect(_on_user_formation_changed)
	if not GameEvents.lineup_changed.is_connected(_on_lineup_changed):
		GameEvents.lineup_changed.connect(_on_lineup_changed)
	if not GameEvents.player_injured.is_connected(_on_player_injured):
		GameEvents.player_injured.connect(_on_player_injured)

	_apply_formation(_active_formation)
	_apply_brain_overrides()


func _on_user_formation_changed(team_id: int, new_formation: String) -> void:
	if team_id != _team:
		return
	_active_formation = new_formation
	_apply_formation(new_formation)
	_apply_brain_overrides()


func _on_lineup_changed(team_id: int) -> void:
	if team_id != _team:
		return
	_apply_formation(_active_formation)
	_apply_brain_overrides()


## Reacts to a knock severe enough to end this player's involvement (see
## HeavyPlayerController.INJURY_FORCED_SUB_SEVERITY). Unlike a tactical
## substitution — which routes through TeamManagementData / PauseMenu and is
## a human decision — this manager does not wait to be asked, matching a
## stretcher-off in real football: it searches the bench itself and resolves
## straight into the same GameEvents.substitution_made that PauseMenu already
## drives, so PitchScene/MatchStatsTracker/MatchTelemetryLogger/HUD/the
## referee crew all react through their existing listener with no new code.
func _on_player_injured(
	player: HeavyPlayerController, severity: float, _injury_tag: StringName
) -> void:
	if player == null or player.team != _team or _players_node == null:
		return
	if severity < HeavyPlayerController.INJURY_FORCED_SUB_SEVERITY:
		return
	if not GameManager.is_in_play():
		return

	var team_data: TeamData = DataLoader.get_match_team(_team)
	if team_data == null or team_data.substitutions_made >= 3:
		return

	var replacement_idx: int = _find_bench_replacement(player.squad_index)
	if replacement_idx < 0:
		# No fit bench cover — the team plays a man light, same as real
		# football when the bench is already exhausted.
		return

	GameEvents.forced_substitution_requested.emit(_team, player.squad_index)
	team_data.substitutions_made += 1
	GameEvents.substitution_made.emit(_team, player.squad_index, replacement_idx)


## Positional bench search: prefers an exact position_role match, falls back
## to the same broad role category (_ROLE_ENUM_MAP), then any fit outfield
## body. Not a hot path — fires once per forced substitution, not per frame —
## so the Array scratch below is fine despite the zero-allocation rule that
## governs _physics_process/evaluate_tactical_action.
func _find_bench_replacement(out_squad_index: int) -> int:
	var team_data: TeamData = DataLoader.get_match_team(_team)
	if team_data == null:
		return -1
	var outgoing: PlayerData = DataLoader.get_player(_team, out_squad_index)
	var out_role: String = outgoing.position_role.to_upper() if outgoing != null else ""
	var out_category: PlayerBrain.Role = _ROLE_ENUM_MAP.get(out_role, PlayerBrain.Role.OUTFIELD_MIDFIELDER)

	var fielded: Array[int] = _current_fielded_squad_indices()

	var best_exact: int = -1
	var best_category: int = -1
	var best_any: int = -1
	for i: int in range(team_data.squad.size()):
		if fielded.has(i):
			continue
		var candidate: PlayerData = team_data.squad[i]
		if candidate == null or candidate.is_unavailable:
			continue
		if best_any < 0:
			best_any = i
		var cand_role: String = candidate.position_role.to_upper()
		if best_exact < 0 and cand_role == out_role:
			best_exact = i
		elif best_category < 0 and _ROLE_ENUM_MAP.get(cand_role, PlayerBrain.Role.OUTFIELD_MIDFIELDER) == out_category:
			best_category = i

	if best_exact >= 0:
		return best_exact
	if best_category >= 0:
		return best_category
	return best_any


## Squad indices currently fielded for this team, read straight off the live
## pitch nodes (not TeamData.lineup_indices, which a prior mid-match
## substitution may have already diverged from).
func _current_fielded_squad_indices() -> Array[int]:
	var out: Array[int] = []
	for node: Node in _players_node.get_children():
		var p := node as HeavyPlayerController
		if p != null and p.team == _team:
			out.append(p.squad_index)
	return out


func _apply_formation(formation_name: String) -> void:
	if _boundary == null or _players_node == null:
		return

	var layout: Array[Dictionary] = FormationLibrary.get_formation(formation_name)
	var pitch_centre: Vector2 = _boundary.get_centre_spot()

	var team_players: Array[HeavyPlayerController] = []
	for node: Node in _players_node.get_children():
		var p := node as HeavyPlayerController
		if p != null and p.team == _team:
			team_players.append(p)

	var match_team: TeamData = DataLoader.get_match_team(_team)
	var ordered_players: Array[HeavyPlayerController] = []
	if match_team != null and match_team.lineup_indices.size() == 11:
		for target_squad_idx: int in match_team.lineup_indices:
			for p: HeavyPlayerController in team_players:
				if p.squad_index == target_squad_idx:
					ordered_players.append(p)
					break

	if ordered_players.size() != team_players.size():
		var by_squad_index := func(a: HeavyPlayerController, b: HeavyPlayerController) -> bool:
			return a.squad_index < b.squad_index
		team_players.sort_custom(by_squad_index)
		ordered_players = team_players

	# Collected alongside the direct writes below and published on
	# GameEvents.formation_anchors_changed, so a brain can react to the new
	# shape immediately instead of waiting out its decision stagger.
	var new_anchors: Dictionary = {}

	for i: int in range(ordered_players.size()):
		var player: HeavyPlayerController = ordered_players[i]
		if player.brain == null:
			continue

		var slot_index: int = clampi(i, 0, layout.size() - 1)
		var slot: Dictionary = layout[slot_index]
		var role_str: String = slot["role"]
		if match_team != null and match_team.role_overrides.has(slot_index):
			role_str = str(match_team.role_overrides[slot_index])

		var offset: Vector2 = slot["anchor_offset"]

		var defends_left: bool = (_team == GameManager.TEAM_A) if not _boundary.sides_flipped else (_team != GameManager.TEAM_A)
		var anchor: Vector2 = pitch_centre + offset if defends_left else pitch_centre - offset
		player.brain.formation_anchor = anchor
		player.brain.role = _ROLE_ENUM_MAP.get(role_str, PlayerBrain.Role.OUTFIELD_MIDFIELDER)
		player.brain.is_goalkeeper = (role_str == "GK")
		if _ROLE_CONFIGS.has(role_str):
			player.role_config = (_ROLE_CONFIGS[role_str] as PlayerRoleConfig).duplicate()
		new_anchors[player.brain.player_index] = anchor

		# Convenience tag for career mode UI only — does not affect physics.
		var pdata: PlayerData = player.get_meta(&"player_data", null) as PlayerData
		if pdata != null:
			pdata.position_role = role_str

	GameEvents.formation_anchors_changed.emit(_team, new_anchors)


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


## Reads GameManager.score and GameManager.get_match_time_ratio(). Evaluates once per goal
## event — never per-frame.
func _check_formation_shift() -> void:
	if _data == null:
		return

	var our_score: int = GameManager.score[_team]
	var their_score: int = GameManager.score[1 - _team]
	var diff: int = our_score - their_score
	var time_ratio: float = GameManager.get_match_time_ratio()
	var late_game: bool = time_ratio >= 0.70

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


func _on_goal_scored(scoring_team: int, _scorer: Node = null) -> void:
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


## Every manager's tempo (0=patient build-up, 1=direct/counter) and
## pressing_intensity (0=passive, 1=gegenpress) already read as a risk
## disposition — a direct, relentless manager takes more chances than a
## patient, passive one — so risk_profile rides on those existing sliders
## instead of adding a new @export ManagerData field just for this. Pragmatist
## (4) pulls it further toward caution; HotHead (1) and Volatile (256) push it
## further toward aggression.
func _compute_risk_profile(data: ManagerData) -> float:
	var raw: float = (data.tempo - 0.5) * 0.5 + (data.pressing_intensity - 0.5) * 0.3
	if data.has_trait(4):
		raw -= 0.15
	if data.has_trait(1) or data.has_trait(256):
		raw += 0.15
	return clampf(raw, -0.35, 0.35)


func _process(delta: float) -> void:
	if _team < 0 or _data == null:
		return

	_urgency_eval_timer += delta
	if _urgency_eval_timer >= URGENCY_TICK_INTERVAL:
		_urgency_eval_timer -= URGENCY_TICK_INTERVAL
		_evaluate_tactical_urgency()


## Hyperbolic-tangent scoreline/time S-curve, dampened hard during Phase 0
## (Cautious Sizing-Up) so no team commits to high-risk vertical play in the
## opening minutes regardless of manager disposition. See
## POWERFOOTBALL_MASTER_VISION.md Part V / the architecture plan for the
## derivation of every constant here.
func _evaluate_tactical_urgency() -> void:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return

	var goals_for: int = GameManager.score[_team]
	var goals_against: int = GameManager.score[1 - _team]
	var delta_score: float = float(goals_for - goals_against)

	var time_ratio: float = GameManager.get_match_time_ratio()
	var time_sq: float = time_ratio * time_ratio

	var raw_urgency: float = tanh(-TIME_ACCEL_K * delta_score * time_sq + _risk_profile)

	# Phase 0 (Cautious Sizing-Up): never let a positive urgency reading exceed
	# 0.2, however aggressive the manager or scoreline would otherwise push it.
	if time_ratio < GameManager.STAGE_1_FRACTION and raw_urgency > 0.0:
		raw_urgency = minf(raw_urgency, 0.2)

	var final_urgency: float = clampf(raw_urgency, -1.0, 1.0)

	# Emergency tactics: one-shot escalation distinct from the smooth formula
	# above. Trailing this late already pushes raw_urgency high via
	# delta_score*time_sq, but tanh saturation means it is not necessarily at
	# the full +1.0 (the max URGENCY_MAX_DEF_LINE_SHIFT=120px defensive-line
	# push FormationAnchorMath.gd applies at |urgency|==1.0) an actual
	# "all out attack" gamble calls for — e.g. trailing by exactly 1 goal right
	# at GameManager.STAGE_3_FRACTION only reads ~0.5-0.9 depending on risk
	# profile, not 1.0. Force the full push once, as a discrete directive
	# rather than something PlayerBrain has to keep independently re-deriving
	# a threshold check against — see GameEvents.emergency_tactics_triggered.
	if not _emergency_tactics_triggered and time_ratio >= GameManager.STAGE_3_FRACTION and delta_score <= -1.0:
		_emergency_tactics_triggered = true
		final_urgency = 1.0
		GameEvents.emergency_tactics_triggered.emit(_team, &"ALL_OUT_ATTACK")

	if absf(final_urgency - world.team_urgency[_team]) > URGENCY_PUBLISH_EPSILON:
		GameEvents.team_urgency_updated.emit(_team, final_urgency)
