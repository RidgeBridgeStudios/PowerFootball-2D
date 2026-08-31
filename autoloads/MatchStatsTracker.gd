##
## MatchStatsTracker (Autoload singleton)
##
## Per-match counting stats for the full-time stats screen: possession, shots,
## passes, fouls, cards, corners and offsides. The original stats here are all
## TEAM aggregates (index 0 = TEAM_A, index 1 = TEAM_B) — plain fixed-size
## Arrays. End-of-match player ratings additionally need per-player
## granularity, tracked alongside in a Dictionary[int, PlayerMatchEvents].
##
## PlayerData has no player_id field, so the per-player key is synthesized as
## `team * 1000 + squad_index`. squad_index (HeavyPlayerController.squad_index)
## is stable per real player and correctly follows a substitution — PitchScene
## reassigns it to the incoming player's squad index before reapplying data —
## so a starter and the substitute who replaces them in the same pitch slot
## never share a bucket. The key decodes back to (team, squad_index), which
## DataLoader.get_player() resolves to a PlayerData at any time, including
## after a red card sending has cleared the player's MatchWorldModel slot.
##
## Shots and cards are wired from existing GameEvents signals. Pass attempts
## are recorded directly from the state machines that resolve a pass
## (ChargeKickState's tap branch, ThrowInState) via record_pass_attempt() —
## there is no "pass" signal to listen for, since ball_struck fires for shots
## and passes alike. Possession is sampled every 30 physics ticks straight off
## MatchWorldModel's cached possessor index — no scene tree access, no
## allocation in the sampling path.
##
## Also owns the macro anti-snowball Team Momentum accumulator: continuous
## exponential decay plus discrete event impulses (shot on target, tackle
## won, goal conceded, anticipatory turnover, a 5-pass sequence in the
## opponent's half), quadratically self-dampened and published via
## GameEvents.team_momentum_updated. See "Macro momentum accumulator" below.
##
## Depends on: GameEvents, GameManager, MatchWorldModel, DataLoader,
##             HeavyPlayerController, PlayerRatingCalculator.
## Exposes: record_shot(), record_pass_attempt(), record_foul(),
##          record_corner(), record_offside(), record_goal(), record_assist(),
##          record_own_goal(), get_player_events(), compute_all_ratings(),
##          get_stats(), reset(), init_players(),
##          is_pass_toward_teammate(), stop_possession_sampling(),
##          team_momentum — see GameEvents.team_momentum_updated instead of
##          reading this directly.
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

## --- Macro momentum accumulator (anti-snowball) ------------------------------
## Team Momentum (POWERFOOTBALL_MASTER_VISION.md Part V / the architecture
## plan) — a continuously-decaying, discretely-impulsed scalar per team,
## quadratically self-dampened so no single event chain produces a runaway
## blowout. Publishes via GameEvents.team_momentum_updated; MatchWorldModel
## caches it, MoodSystem reads it as an ambient composure drift, PitchScene
## reacts to a sharp swing with a touchline shout.
const MOMENTUM_DECAY_LAMBDA: float = 0.015
## Minimum change worth publishing — applies to both discrete impulses and
## continuous decay catch-up, same idea as ManagerDirector's urgency epsilon.
const MOMENTUM_PUBLISH_EPSILON: float = 0.01

## Discrete event impulse weights. Positive = confidence-building for the team
## that generated the event, negative = confidence-damaging. SHOT_ON_TARGET,
## GOAL_CONCEDED and TURNOVER_ERROR are the task-spec values; TACKLE_WON and
## PASS_SEQUENCE are extrapolated at the same relative scale (see
## AGENTS_ERRATA.md).
const MOMENTUM_SHOT_ON_TARGET: float = 0.15
const MOMENTUM_TACKLE_WON: float = 0.10
const MOMENTUM_PASS_SEQUENCE: float = 0.05
const MOMENTUM_GOAL_CONCEDED: float = -0.45
const MOMENTUM_TURNOVER_ERROR: float = -0.20

## Consecutive completed passes, in the opponent's attacking half, needed to
## register a PASS_SEQUENCE momentum tick — see _record_pass_sequence().
const PASS_SEQUENCE_LENGTH: int = 5

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

var team_momentum: Array[float] = [0.0, 0.0]
## Last value actually broadcast via GameEvents.team_momentum_updated per
## team — decay only re-publishes once it has drifted past
## MOMENTUM_PUBLISH_EPSILON from this, so continuous decay does not spam the
## signal bus at 60Hz. See _maybe_publish_momentum().
var _last_published_momentum: Array[float] = [0.0, 0.0]
## Consecutive completed passes per team since the last incomplete pass —
## see record_pass_attempt() / _record_pass_sequence().
var _consecutive_passes: Array[int] = [0, 0]

## Per-player match events, keyed by `team * 1000 + squad_index`. Populated by
## init_players() at bind time and lazily extended by _on_substitution_made()
## for anyone who comes on later — every entry is allocated once and mutated
## in place for the rest of the match.
var _player_events: Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents] = {}
## Last player on each team (index 0/1) whose pass attempt completed —
## the naive "who gets the assist" proxy on the next goal for that team.
var _last_passer_by_team: Array[HeavyPlayerController] = [null, null]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	GameEvents.ball_struck.connect(_on_ball_struck)
	GameEvents.foul_committed.connect(_on_foul_committed)
	GameEvents.offside_called.connect(_on_offside_called)
	GameEvents.corner_kick_started.connect(_on_corner_kick_started)
	GameEvents.yellow_card_shown.connect(_on_yellow_card_shown)
	GameEvents.red_card_shown.connect(_on_red_card_shown)
	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.substitution_made.connect(_on_substitution_made)
	GameEvents.tackle_won.connect(_on_tackle_won)
	GameEvents.anticipatory_turnover_predicted.connect(_on_turnover_predicted)


func _physics_process(delta: float) -> void:
	if not _sampling_active:
		return

	_update_momentum_decay(delta)

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
		_get_or_create_events(player).shots_on_target += 1
	else:
		_get_or_create_events(player).shots_off_target += 1


func record_pass_attempt(player: HeavyPlayerController, completed: bool) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	passes_attempted[team] += 1
	if completed:
		passes_completed[team] += 1
		_last_passer_by_team[team] = player
		_get_or_create_events(player).passes_completed += 1
		_record_pass_sequence(team, player)
	else:
		_get_or_create_events(player).passes_failed += 1
		_consecutive_passes[team] = 0


## --- Macro momentum accumulator ----------------------------------------------

## Continuous exponential decay toward equilibrium, run every physics frame so
## the half-life math stays accurate regardless of the 30-tick possession
## sampling cadence below. Only publishes once decay has moved a team's value
## past MOMENTUM_PUBLISH_EPSILON since the last broadcast, so this does not
## spam GameEvents at 60Hz.
func _update_momentum_decay(delta: float) -> void:
	if not GameManager.is_in_play():
		return
	var decay_factor: float = exp(-MOMENTUM_DECAY_LAMBDA * delta)
	for t: int in range(2):
		var decayed: float = team_momentum[t] * decay_factor
		team_momentum[t] = decayed
		_maybe_publish_momentum(t)


## Shared impulse application for every discrete momentum event — quadratic
## anti-snowball dampening (gamma(M) = 1 - M^2) means marginal impulse gains
## shrink to zero as momentum approaches +/-1, so no event chain can produce
## an unbounded runaway (see POWERFOOTBALL_MASTER_VISION.md / architecture
## plan "Anti-Snowball Momentum Accumulator").
func _apply_momentum_impulse(team: int, raw_impulse: float) -> void:
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	var current_m: float = team_momentum[team]
	var effective_impulse: float = raw_impulse * (1.0 - (current_m * current_m))
	team_momentum[team] = clampf(current_m + effective_impulse, -1.0, 1.0)
	_maybe_publish_momentum(team, true)


## force always publishes — a discrete event is always worth broadcasting
## even if its dampened effective impulse was tiny; decay ticks (force=false)
## only publish once they've drifted past MOMENTUM_PUBLISH_EPSILON.
func _maybe_publish_momentum(team: int, force: bool = false) -> void:
	if force or absf(team_momentum[team] - _last_published_momentum[team]) > MOMENTUM_PUBLISH_EPSILON:
		_last_published_momentum[team] = team_momentum[team]
		GameEvents.team_momentum_updated.emit(team, team_momentum[team])


func _on_tackle_won(winner: Node, _loser: Node) -> void:
	var w := winner as HeavyPlayerController
	if w != null and is_instance_valid(w):
		_apply_momentum_impulse(w.team, MOMENTUM_TACKLE_WON)


## GameEvents.anticipatory_turnover_predicted fires with the INTERCEPTING
## team (see MatchWorldModel._physics_process) — the turnover penalty belongs
## to whoever is about to lose the ball, i.e. the other team.
func _on_turnover_predicted(intercepting_team: int) -> void:
	_apply_momentum_impulse(1 - intercepting_team, MOMENTUM_TURNOVER_ERROR)


## Territorial control and rhythm: PASS_SEQUENCE_LENGTH consecutive completed
## passes by the same team while the ball stays in the opponent's attacking
## half. Resets on any incomplete pass (record_pass_attempt()) or once it
## fires, so it re-arms rather than firing every pass past the threshold.
func _record_pass_sequence(team: int, player: HeavyPlayerController) -> void:
	if not _is_in_opponent_half(team, player.global_position):
		_consecutive_passes[team] = 0
		return
	_consecutive_passes[team] += 1
	if _consecutive_passes[team] >= PASS_SEQUENCE_LENGTH:
		_consecutive_passes[team] = 0
		_apply_momentum_impulse(team, MOMENTUM_PASS_SEQUENCE)


## Team 0 attacks +X, team 1 attacks -X (FormationAnchorMath / soccer-physics.md
## convention) — "opponent half" is x > pitch centre for team 0, x < centre
## for team 1.
func _is_in_opponent_half(team: int, pos: Vector2) -> bool:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false
	var centre_x: float = world.get_pitch_centre_x()
	return pos.x > centre_x if team == 0 else pos.x < centre_x


func record_foul(player: HeavyPlayerController) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	fouls[team] += 1
	_get_or_create_events(player).fouls += 1


## +1.2 rating event for the scorer. The strike that produced this goal was
## already counted as a "shot on target" by _on_ball_struck (is_shot fires
## before the ball reaches the net) — decrement it back out so a goal isn't
## double-credited as both a goal and a separate shot-on-target bonus.
func record_goal(player: HeavyPlayerController) -> void:
	if player == null or not is_instance_valid(player):
		return
	var events: PlayerRatingCalculator.PlayerMatchEvents = _get_or_create_events(player)
	events.goals += 1
	if events.shots_on_target > 0:
		events.shots_on_target -= 1


func record_assist(player: HeavyPlayerController) -> void:
	if player == null or not is_instance_valid(player):
		return
	_get_or_create_events(player).assists += 1


func record_own_goal(player: HeavyPlayerController) -> void:
	if player == null or not is_instance_valid(player):
		return
	_get_or_create_events(player).own_goals += 1


## Returns this player's event counters, creating an empty (all-zero) entry
## if this is the first time they have been referenced.
func get_player_events(player_id: int) -> PlayerRatingCalculator.PlayerMatchEvents:
	if not _player_events.has(player_id):
		_player_events[player_id] = PlayerRatingCalculator.PlayerMatchEvents.new()
	return _player_events[player_id]


## Runs PlayerRatingCalculator over every tracked player and returns
## player_id (team * 1000 + squad_index) -> rating. Also resolves clean sheet
## for each tracked goalkeeper and writes the result onto PlayerData for
## career persistence (PlayerData.last_match_rating is reserved for exactly
## this).
func compute_all_ratings() -> Dictionary[int, float]:
	var ratings: Dictionary[int, float] = {}

	var live_keys: Dictionary[int, bool] = {}
	var world: MatchWorldModel = MatchWorldModel.instance
	if world != null:
		for node: HeavyPlayerController in world.player_nodes:
			if node == null or not is_instance_valid(node):
				continue
			live_keys[_player_key(node)] = true

	for key: int in _player_events:
		var team: int = key / 1000
		var squad_index: int = key % 1000
		var player_data: PlayerData = DataLoader.get_player(team, squad_index)
		if player_data == null:
			continue

		var events: PlayerRatingCalculator.PlayerMatchEvents = _player_events[key]
		events.kept_clean_sheet = _resolve_clean_sheet(player_data, team, key, live_keys)

		var rating: float = PlayerRatingCalculator.calculate(player_data, events)
		ratings[key] = rating
		player_data.last_match_rating = rating

	return ratings


## True when this tracked player is a goalkeeper who is still on the live
## roster (i.e. not sent off — is_slot_live() would false-negative here since
## a red-carded player's own slot is cleared, so membership in live_keys,
## gathered once up front, is what actually distinguishes "still out there"
## from "removed mid-match") and their team's opponents are scoreless.
func _resolve_clean_sheet(player_data: PlayerData, team: int, key: int, live_keys: Dictionary[int, bool]) -> bool:
	if player_data.position_role != "GK":
		return false
	if not live_keys.has(key):
		return false
	var opponent_team: int = 1 - team
	return GameManager.score[opponent_team] == 0


func _get_or_create_events(player: HeavyPlayerController) -> PlayerRatingCalculator.PlayerMatchEvents:
	var key: int = _player_key(player)
	if not _player_events.has(key):
		_player_events[key] = PlayerRatingCalculator.PlayerMatchEvents.new()
	return _player_events[key]


func _player_key(player: HeavyPlayerController) -> int:
	return player.team * 1000 + player.squad_index


## Called once by PitchScene right after _bind_players(), before
## GameManager.start_match() — pre-allocates a PlayerMatchEvents for every
## player currently on the pitch (the starting XI on both squads) so anyone
## who appears but generates zero events still shows up on the ratings page
## at the 6.0 baseline. Reserves who come on later are added lazily by
## _on_substitution_made().
func init_players() -> void:
	_player_events.clear()
	_last_passer_by_team = [null, null]

	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return
	for node: HeavyPlayerController in world.player_nodes:
		if node == null or not is_instance_valid(node):
			continue
		_get_or_create_events(node)


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
	_player_events.clear()
	_last_passer_by_team = [null, null]
	team_momentum = [0.0, 0.0]
	_last_published_momentum = [0.0, 0.0]
	_consecutive_passes = [0, 0]


func _on_ball_struck(player: Node, _speed: float, charge_ratio: float, is_shot: bool) -> void:
	if not is_shot:
		return
	var shooter := player as HeavyPlayerController
	if shooter == null:
		return
	var on_target: bool = charge_ratio > SHOT_ON_TARGET_THRESHOLD
	record_shot(shooter, on_target)
	if on_target:
		_apply_momentum_impulse(shooter.team, MOMENTUM_SHOT_ON_TARGET)


func _on_foul_committed(fouler: Node, _victim: Node, _position: Vector2) -> void:
	var fouling_player := fouler as HeavyPlayerController
	if fouling_player != null:
		record_foul(fouling_player)


func _on_offside_called(_offside_player: Node, defending_team: int, _position: Vector2) -> void:
	record_offside(1 - defending_team)


func _on_corner_kick_started(team: int, _position: Vector2) -> void:
	record_corner(team)


func _on_yellow_card_shown(player: Node, team: int) -> void:
	if team == GameManager.TEAM_A or team == GameManager.TEAM_B:
		yellow_cards[team] += 1
	var carded_player := player as HeavyPlayerController
	if carded_player != null and is_instance_valid(carded_player):
		_get_or_create_events(carded_player).yellow_cards += 1


func _on_red_card_shown(player: Node, team: int, _is_second_yellow: bool) -> void:
	if team == GameManager.TEAM_A or team == GameManager.TEAM_B:
		red_cards[team] += 1
	var carded_player := player as HeavyPlayerController
	if carded_player != null and is_instance_valid(carded_player):
		_get_or_create_events(carded_player).red_cards += 1


## Attributes a goal to whoever last touched the ball (GoalZone passes
## Pseudo3DBall.last_touched_by through as scorer). scorer.team != team means
## the touch was on the defending side — an own goal, not a goal for them.
## The assist proxy is simply the last completed pass on the scoring team,
## which is the best signal available: the ball has no target/arrival concept
## to trace a specific pass through to a specific shot.
func _on_goal_scored(team: int, scorer: Node) -> void:
	if GameManager.shootout_active:
		return  # Shootout kicks are not run-of-play performances.

	_apply_momentum_impulse(1 - team, MOMENTUM_GOAL_CONCEDED)

	var scoring_player := scorer as HeavyPlayerController
	if scoring_player == null or not is_instance_valid(scoring_player):
		return

	if scoring_player.team == team:
		record_goal(scoring_player)
		var assist_player: HeavyPlayerController = _last_passer_by_team[team]
		if assist_player != null and is_instance_valid(assist_player) and assist_player != scoring_player:
			record_assist(assist_player)
	else:
		record_own_goal(scoring_player)


## Ensures a substitute has a rating entry even if they never touch the ball
## again before full time — otherwise "appeared but generated zero events"
## would silently drop them off the ratings page.
func _on_substitution_made(team: int, _player_out_idx: int, player_in_idx: int) -> void:
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	var key: int = team * 1000 + player_in_idx
	if not _player_events.has(key):
		_player_events[key] = PlayerRatingCalculator.PlayerMatchEvents.new()
