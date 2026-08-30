##
## MatchStatsTracker (Autoload singleton)
##
## Per-match counting stats for the full-time stats screen: possession, shots,
## passes, fouls, cards, corners and offsides. Every stat here is a TEAM
## aggregate (index 0 = TEAM_A, index 1 = TEAM_B) — none of the required stats
## need per-player granularity, so counters are plain fixed-size Arrays rather
## than a per-player Dictionary.
##
## Shots and cards are wired from existing GameEvents signals. Pass attempts
## are recorded directly from the state machines that resolve a pass
## (ChargeKickState's tap branch, ThrowInState) via record_pass_attempt() —
## there is no "pass" signal to listen for, since ball_struck fires for shots
## and passes alike. Possession is sampled every 30 physics ticks straight off
## MatchWorldModel's cached possessor index — no scene tree access, no
## allocation in the sampling path.
##
## Depends on: GameEvents, GameManager, MatchWorldModel, HeavyPlayerController.
## Exposes: record_shot(), record_pass_attempt(), record_foul(),
##          record_corner(), record_offside(), get_stats(), reset(),
##          is_pass_toward_teammate(), stop_possession_sampling().
##

extends Node

## Physics ticks between possession samples (0.5s at 60Hz).
const POSSESSION_SAMPLE_INTERVAL: int = 30
## charge_ratio above which a recorded shot counts as "on target" — the only
## signal data available at the ball_struck call sites is power, not aim.
const SHOT_ON_TARGET_THRESHOLD: float = 0.5
## Half-angle cosine (~35 degrees) for the "pass found a teammate" cone check.
const PASS_CONE_COS: float = 0.82
## Passes farther than this are treated as unlikely to reach anyone, whatever
## the aim.
const PASS_MAX_RANGE: float = 500.0

var shots_total: Array[int] = [0, 0]
var shots_on_target: Array[int] = [0, 0]
var passes_attempted: Array[int] = [0, 0]
var passes_completed: Array[int] = [0, 0]
var fouls: Array[int] = [0, 0]
var yellow_cards: Array[int] = [0, 0]
var red_cards: Array[int] = [0, 0]
var corners: Array[int] = [0, 0]
var offsides: Array[int] = [0, 0]

var _possession_samples: Array[int] = [0, 0]
var _total_possession_samples: int = 0
var _physics_tick_count: int = 0
var _sampling_active: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	GameEvents.ball_struck.connect(_on_ball_struck)
	GameEvents.foul_committed.connect(_on_foul_committed)
	GameEvents.offside_called.connect(_on_offside_called)
	GameEvents.corner_kick_started.connect(_on_corner_kick_started)
	GameEvents.yellow_card_shown.connect(_on_yellow_card_shown)
	GameEvents.red_card_shown.connect(_on_red_card_shown)


func _physics_process(_delta: float) -> void:
	if not _sampling_active:
		return

	_physics_tick_count += 1
	if _physics_tick_count % POSSESSION_SAMPLE_INTERVAL != 0:
		return
	if not GameManager.is_in_play() or GameManager.get_meta(&"practice_mode", false):
		return

	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return

	var possessor_index: int = world.possessor_index
	if possessor_index == MatchWorldModel.NO_INDEX:
		return

	var team: int = world.player_teams[possessor_index]
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return

	_possession_samples[team] += 1
	_total_possession_samples += 1


func record_shot(player: HeavyPlayerController, on_target: bool) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	shots_total[team] += 1
	if on_target:
		shots_on_target[team] += 1


func record_pass_attempt(player: HeavyPlayerController, completed: bool) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	passes_attempted[team] += 1
	if completed:
		passes_completed[team] += 1


func record_foul(player: HeavyPlayerController) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	fouls[team] += 1


func record_corner(team_index: int) -> void:
	if team_index != GameManager.TEAM_A and team_index != GameManager.TEAM_B:
		return
	corners[team_index] += 1


func record_offside(team_index: int) -> void:
	if team_index != GameManager.TEAM_A and team_index != GameManager.TEAM_B:
		return
	offsides[team_index] += 1


## Best-effort "did this pass find a teammate" proxy: no target/arrival concept
## exists on the ball, so this checks whether any teammate sits within a
## forward cone of the strike's aim direction, inside PASS_MAX_RANGE. Reads
## MatchWorldModel only — never the scene tree.
func is_pass_toward_teammate(player: HeavyPlayerController, aim: Vector2) -> bool:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or player.world_index < 0:
		return false

	var aim_dir: Vector2 = aim.normalized()
	if aim_dir == Vector2.ZERO:
		return false

	for teammate_index: int in world.get_teammates_of(player.world_index):
		var to_teammate: Vector2 = world.player_positions[teammate_index] - player.global_position
		var dist: float = to_teammate.length()
		if dist <= 0.0 or dist > PASS_MAX_RANGE:
			continue
		if aim_dir.dot(to_teammate / dist) >= PASS_CONE_COS:
			return true

	return false


func get_stats(team_index: int) -> Dictionary:
	var attempted: int = passes_attempted[team_index]
	var completion_pct: float = 0.0
	if attempted > 0:
		completion_pct = float(passes_completed[team_index]) / float(attempted) * 100.0

	var possession_pct: float = 50.0
	if _total_possession_samples > 0:
		possession_pct = float(_possession_samples[team_index]) / float(_total_possession_samples) * 100.0

	return {
		"possession_pct": possession_pct,
		"shots": shots_total[team_index],
		"shots_on_target": shots_on_target[team_index],
		"passes_attempted": attempted,
		"pass_completion_pct": completion_pct,
		"fouls": fouls[team_index],
		"yellow_cards": yellow_cards[team_index],
		"red_cards": red_cards[team_index],
		"corners": corners[team_index],
		"offsides": offsides[team_index],
	}


## Called by PitchScene once the full-time whistle blows — possession has no
## more meaningful frames to sample once the match is over.
func stop_possession_sampling() -> void:
	_sampling_active = false


## Called by PitchScene once the stats screen is dismissed, so the next match
## starts from a clean slate.
func reset() -> void:
	shots_total = [0, 0]
	shots_on_target = [0, 0]
	passes_attempted = [0, 0]
	passes_completed = [0, 0]
	fouls = [0, 0]
	yellow_cards = [0, 0]
	red_cards = [0, 0]
	corners = [0, 0]
	offsides = [0, 0]
	_possession_samples = [0, 0]
	_total_possession_samples = 0
	_physics_tick_count = 0
	_sampling_active = true


func _on_ball_struck(player: Node, _speed: float, charge_ratio: float, is_shot: bool) -> void:
	if not is_shot:
		return
	var shooter := player as HeavyPlayerController
	if shooter == null:
		return
	record_shot(shooter, charge_ratio > SHOT_ON_TARGET_THRESHOLD)


func _on_foul_committed(fouler: Node, _victim: Node, _position: Vector2) -> void:
	var fouling_player := fouler as HeavyPlayerController
	if fouling_player != null:
		record_foul(fouling_player)


func _on_offside_called(_offside_player: Node, defending_team: int, _position: Vector2) -> void:
	record_offside(1 - defending_team)


func _on_corner_kick_started(team: int, _position: Vector2) -> void:
	record_corner(team)


func _on_yellow_card_shown(_player: Node, team: int) -> void:
	if team == GameManager.TEAM_A or team == GameManager.TEAM_B:
		yellow_cards[team] += 1


func _on_red_card_shown(_player: Node, team: int, _is_second_yellow: bool) -> void:
	if team == GameManager.TEAM_A or team == GameManager.TEAM_B:
		red_cards[team] += 1
