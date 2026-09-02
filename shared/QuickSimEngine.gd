##
## QuickSimEngine
##
## Probabilistic match outcome engine and stochastic match simulator.
## Calculates the exact analytical probability distribution of all possible match
## outcomes using a bivariate Poisson / Dixon-Coles model parameterized by:
##   - Positional unit ratings (GK, DEF, MID, ATT) and individual player attributes
##   - Player form and mood modifiers
##   - Manager tactical sliders (defensive line, pressing, tempo, width) & traits bitmask
##   - Referee personality (strictness, consistency, composure, unprofessionalism)
##   - Home ground advantage
##
## Produces:
##   - Analytical MatchProbabilities (Home/Draw/Away %, Expected Goals, Over 2.5 %,
##     BTTS %, Clean Sheets %, top exact scorelines, tactical matchup insights)
##   - Stochastic QuickSimResult (final score, chronological goal/card events,
##     full team traditional stats, advanced Moneyball analytics, and per-player
##     events + ratings for all 22 players).
##
## Depends on: TeamData, PlayerData, ManagerData, RefereeData, PlayerRatingCalculator,
##             GameManager, MatchStatsTracker, DataLoader.
## Exposes: calculate_probabilities(), simulate_match(), apply_to_match_stats_tracker(),
##          calculate_team_units(), get_star_rating_value(), get_star_rating_string().
##

class_name QuickSimEngine
extends RefCounted

class MatchProbabilities:
	var home_win_pct: float = 0.0
	var draw_pct: float = 0.0
	var away_win_pct: float = 0.0
	var home_xg: float = 0.0
	var away_xg: float = 0.0
	var over_2_5_pct: float = 0.0
	var btts_pct: float = 0.0
	var home_clean_sheet_pct: float = 0.0
	var away_clean_sheet_pct: float = 0.0
	var scoreline_probs: Array[Dictionary] = [] # {"score": "1-0", "prob_pct": 14.2, "home": 1, "away": 0}
	var tactical_insights: Array[String] = []
	var home_unit_ratings: Dictionary = {} # {"gk": float, "def": float, "mid": float, "att": float, "overall": float}
	var away_unit_ratings: Dictionary = {}

class MatchEventRecord:
	var minute: int = 0
	var event_type: String = "" # "goal", "yellow_card", "red_card"
	var team: int = 0
	var player_name: String = ""
	var squad_index: int = 0
	var assist_player_name: String = ""
	var assist_squad_index: int = -1
	var description: String = ""

class QuickSimResult:
	var home_score: int = 0
	var away_score: int = 0
	var winner: int = -1 # 0 = home, 1 = away, -1 = draw
	var probabilities: MatchProbabilities = null
	var events: Array[MatchEventRecord] = []
	var home_stats: Dictionary = {}
	var away_stats: Dictionary = {}
	var home_advanced_stats: Dictionary = {}
	var away_advanced_stats: Dictionary = {}
	var player_events: Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents] = {}
	var player_ratings: Dictionary[int, float] = {}


## Baseline goals expected in a neutral top-tier 90-minute match.
const BASE_MATCH_GOALS: float = 1.32
## Maximum score evaluated in the discrete probability distribution grid.
const MAX_SCORE_GRID: int = 8
## Dixon-Coles low-score correlation parameter rho.
const DIXON_COLES_RHO: float = -0.04
## Home advantage xG adjustment.
const HOME_ADVANTAGE_XG_BOOST: float = 0.28
const AWAY_ADVANTAGE_XG_PENALTY: float = -0.16
const HOME_POSSESSION_BIAS: float = 3.5

## Trait bitmask constants from ManagerData.
const TRAIT_HOT_HEAD: int = 1
const TRAIT_LOYALIST: int = 2
const TRAIT_PRAGMATIST: int = 4
const TRAIT_VISIONARY: int = 8
const TRAIT_DISCIPLINARIAN: int = 16
const TRAIT_MIND_GAMES: int = 32
const TRAIT_SENTIMENTAL: int = 64
const TRAIT_MEDIA_SAVVY: int = 128
const TRAIT_VOLATILE: int = 256
const TRAIT_IDEALIST: int = 512


## Calculates the complete analytical outcome probability distribution.
static func calculate_probabilities(
	home_team: TeamData,
	away_team: TeamData,
	home_manager: ManagerData,
	away_manager: ManagerData,
	referee: RefereeData,
	home_lineup_indices: Array[int] = [],
	away_lineup_indices: Array[int] = [],
	is_neutral_venue: bool = false
) -> MatchProbabilities:
	var probs := MatchProbabilities.new()

	var h_lineup: Array[int] = home_lineup_indices if home_lineup_indices.size() == 11 else home_team.lineup_indices
	var a_lineup: Array[int] = away_lineup_indices if away_lineup_indices.size() == 11 else away_team.lineup_indices

	if h_lineup.size() < 11:
		h_lineup = _make_default_lineup(home_team.squad.size())
	if a_lineup.size() < 11:
		a_lineup = _make_default_lineup(away_team.squad.size())

	# 1. Positional unit calculations
	var home_units: Dictionary = _calculate_team_units(home_team, h_lineup)
	var away_units: Dictionary = _calculate_team_units(away_team, a_lineup)
	probs.home_unit_ratings = home_units
	probs.away_unit_ratings = away_units

	# 2. Manager tactical matchup & traits
	var home_tactical_mult: float = 1.0
	var away_tactical_mult: float = 1.0
	var insights: Array[String] = []

	if home_manager != null and away_manager != null:
		# Mind Games: rattles opponent composure
		if (home_manager.traits & TRAIT_MIND_GAMES) != 0:
			away_tactical_mult *= 0.94
			insights.append("%s applies mind games, reducing opponent composure." % home_manager.manager_name)
		if (away_manager.traits & TRAIT_MIND_GAMES) != 0:
			home_tactical_mult *= 0.94
			insights.append("%s attempts mind games against the home side." % away_manager.manager_name)

		# Idealist: increases attacking xG and conceding xG
		if (home_manager.traits & TRAIT_IDEALIST) != 0:
			home_tactical_mult *= 1.12
			away_tactical_mult *= 1.10
			insights.append("%s adheres strictly to expansive attacking football." % home_manager.manager_name)
		if (away_manager.traits & TRAIT_IDEALIST) != 0:
			away_tactical_mult *= 1.12
			home_tactical_mult *= 1.10

		# Pragmatist: stabilizes team against blowouts
		if (home_manager.traits & TRAIT_PRAGMATIST) != 0:
			away_tactical_mult *= 0.92
		if (away_manager.traits & TRAIT_PRAGMATIST) != 0:
			home_tactical_mult *= 0.92

		# Defensive line vs opponent attacking pace
		if home_manager.defensive_line > 0.65 and float(away_units["att"]) > 75.0:
			away_tactical_mult *= 1.08
			insights.append("High defensive line leaves space behind for %s's pace." % away_team.team_name)
		if away_manager.defensive_line > 0.65 and float(home_units["att"]) > 75.0:
			home_tactical_mult *= 1.08

		# High pressing vs technical midfield
		if home_manager.pressing_intensity > 0.70:
			if float(away_units["mid"]) < 70.0:
				home_tactical_mult *= 1.06
				insights.append("%s's aggressive press pressures opponent midfield." % home_team.team_name)
			else:
				away_tactical_mult *= 1.04

	# 3. Referee influence
	if referee != null:
		if referee.strictness > 0.75:
			insights.append("Strict referee (%s) is expected to whistle tight fouls." % referee.referee_name)
		if not is_neutral_venue and referee.composure < 0.40:
			home_tactical_mult *= 1.05
			insights.append("Referee %s may be susceptible to home crowd pressure." % referee.referee_name)

	# 4. Expected Goals (lambda) computation
	var home_att_ratio: float = float(home_units["att"]) / maxf(float(away_units["def"]), 20.0)
	var away_att_ratio: float = float(away_units["att"]) / maxf(float(home_units["def"]), 20.0)
	var mid_diff: float = (float(home_units["mid"]) - float(away_units["mid"])) / 100.0

	var lambda_h: float = BASE_MATCH_GOALS * home_att_ratio * (1.0 + mid_diff * 0.4) * home_tactical_mult
	var lambda_a: float = BASE_MATCH_GOALS * away_att_ratio * (1.0 - mid_diff * 0.4) * away_tactical_mult

	if not is_neutral_venue:
		lambda_h += HOME_ADVANTAGE_XG_BOOST
		lambda_a = maxf(lambda_a + AWAY_ADVANTAGE_XG_PENALTY, 0.20)
		insights.append("Home advantage gives %s an edge in tempo and territory." % home_team.team_name)

	lambda_h = clampf(lambda_h, 0.25, 4.5)
	lambda_a = clampf(lambda_a, 0.20, 4.5)

	probs.home_xg = lambda_h
	probs.away_xg = lambda_a
	probs.tactical_insights = insights

	# 5. Bivariate Poisson / Dixon-Coles Probability Matrix
	var grid: Array[Array] = []
	for _i: int in range(MAX_SCORE_GRID + 1):
		var row: Array[float] = []
		for _j: int in range(MAX_SCORE_GRID + 1):
			row.append(0.0)
		grid.append(row)

	var total_prob: float = 0.0
	var win_h: float = 0.0
	var draw_val: float = 0.0
	var win_a: float = 0.0
	var over_2_5: float = 0.0
	var home_zero: float = 0.0
	var away_zero: float = 0.0

	var score_entries: Array[Dictionary] = []

	for x: int in range(MAX_SCORE_GRID + 1):
		var p_x: float = _poisson_pmf(lambda_h, x)
		for y: int in range(MAX_SCORE_GRID + 1):
			var p_y: float = _poisson_pmf(lambda_a, y)
			var tau: float = _dixon_coles_tau(x, y, lambda_h, lambda_a, DIXON_COLES_RHO)
			var prob: float = p_x * p_y * tau
			prob = maxf(prob, 0.0)
			grid[x][y] = prob
			total_prob += prob

			if x > y:
				win_h += prob
			elif x == y:
				draw_val += prob
			else:
				win_a += prob

			if x + y > 2:
				over_2_5 += prob
			if x == 0:
				home_zero += prob
			if y == 0:
				away_zero += prob

			var entry: Dictionary = {
				"score": "%d-%d" % [x, y],
				"prob": prob,
				"prob_pct": 0.0,
				"home": x,
				"away": y
			}
			score_entries.append(entry)

	# Normalize probabilities to sum to 100%
	var norm: float = 1.0 / maxf(total_prob, 0.0001)
	probs.home_win_pct = win_h * norm * 100.0
	probs.draw_pct = draw_val * norm * 100.0
	probs.away_win_pct = win_a * norm * 100.0
	probs.over_2_5_pct = over_2_5 * norm * 100.0
	probs.home_clean_sheet_pct = away_zero * norm * 100.0
	probs.away_clean_sheet_pct = home_zero * norm * 100.0
	probs.btts_pct = (1.0 - (home_zero + away_zero - grid[0][0]) * norm) * 100.0
	probs.btts_pct = clampf(probs.btts_pct, 0.0, 100.0)

	for entry: Dictionary in score_entries:
		entry["prob_pct"] = float(entry["prob"]) * norm * 100.0

	score_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["prob"]) > float(b["prob"])
	)

	var top_scorelines: Array[Dictionary] = []
	for k: int in range(mini(8, score_entries.size())):
		top_scorelines.append(score_entries[k])
	probs.scoreline_probs = top_scorelines

	return probs


## Simulates full match events and creates comprehensive match stats.
static func simulate_match(
	home_team: TeamData,
	away_team: TeamData,
	home_manager: ManagerData,
	away_manager: ManagerData,
	referee: RefereeData,
	home_lineup_indices: Array[int] = [],
	away_lineup_indices: Array[int] = [],
	is_neutral_venue: bool = false
) -> QuickSimResult:
	var result := QuickSimResult.new()
	var probs: MatchProbabilities = calculate_probabilities(
		home_team, away_team, home_manager, away_manager, referee,
		home_lineup_indices, away_lineup_indices, is_neutral_venue
	)
	result.probabilities = probs

	var h_lineup: Array[int] = home_lineup_indices if home_lineup_indices.size() == 11 else home_team.lineup_indices
	var a_lineup: Array[int] = away_lineup_indices if away_lineup_indices.size() == 11 else away_team.lineup_indices
	if h_lineup.size() < 11:
		h_lineup = _make_default_lineup(home_team.squad.size())
	if a_lineup.size() < 11:
		a_lineup = _make_default_lineup(away_team.squad.size())

	# 1. Sample final score from probability distribution
	var sampled_score: Vector2i = _sample_scoreline(probs.home_xg, probs.away_xg)
	result.home_score = sampled_score.x
	result.away_score = sampled_score.y

	if result.home_score > result.away_score:
		result.winner = GameManager.TEAM_A
	elif result.away_score > result.home_score:
		result.winner = GameManager.TEAM_B
	else:
		result.winner = -1

	# 2. Generate per-player event containers
	var all_player_events: Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents] = {}
	for slot: int in range(11):
		var h_idx: int = h_lineup[slot]
		var h_key: int = GameManager.TEAM_A * 1000 + h_idx
		all_player_events[h_key] = PlayerRatingCalculator.PlayerMatchEvents.new()

		var a_idx: int = a_lineup[slot]
		var a_key: int = GameManager.TEAM_B * 1000 + a_idx
		all_player_events[a_key] = PlayerRatingCalculator.PlayerMatchEvents.new()

	# 3. Simulate goals and assign scorers / assists
	var match_events: Array[MatchEventRecord] = []
	_generate_goals(result.home_score, GameManager.TEAM_A, home_team, h_lineup, all_player_events, match_events)
	_generate_goals(result.away_score, GameManager.TEAM_B, away_team, a_lineup, all_player_events, match_events)

	# 4. Simulate fouls, yellow cards, red cards based on referee & player aggression
	_generate_discipline_events(referee, home_team, away_team, h_lineup, a_lineup, all_player_events, match_events)

	# Sort chronological events
	match_events.sort_custom(func(a: MatchEventRecord, b: MatchEventRecord) -> bool:
		return a.minute < b.minute
	)
	result.events = match_events

	# 5. Synthesize team traditional & advanced stats
	var possession_home: float = clampf(50.0 + (float(probs.home_unit_ratings["mid"]) - float(probs.away_unit_ratings["mid"])) * 0.35 + (HOME_POSSESSION_BIAS if not is_neutral_venue else 0.0), 32.0, 68.0)
	var possession_away: float = 100.0 - possession_home

	var home_tempo: float = home_manager.tempo if home_manager != null else 0.5
	var away_tempo: float = away_manager.tempo if away_manager != null else 0.5
	var match_tempo_mult: float = 0.8 + (home_tempo + away_tempo) * 0.25

	var h_shots_total: int = int(roundf((probs.home_xg * 5.2 + float(randi_range(3, 7))) * match_tempo_mult))
	var a_shots_total: int = int(roundf((probs.away_xg * 5.0 + float(randi_range(2, 6))) * match_tempo_mult))
	h_shots_total = maxi(h_shots_total, result.home_score)
	a_shots_total = maxi(a_shots_total, result.away_score)

	var h_shots_on_target: int = int(roundf(result.home_score + float(h_shots_total - result.home_score) * 0.38))
	var a_shots_on_target: int = int(roundf(result.away_score + float(a_shots_total - result.away_score) * 0.38))
	h_shots_on_target = clampi(h_shots_on_target, result.home_score, h_shots_total)
	a_shots_on_target = clampi(a_shots_on_target, result.away_score, a_shots_total)

	var base_passes: float = 480.0 * match_tempo_mult
	var h_passes_attempted: int = int(roundf(base_passes * (possession_home / 50.0)))
	var a_passes_attempted: int = int(roundf(base_passes * (possession_away / 50.0)))

	var h_comp_pct: float = clampf(74.0 + float(probs.home_unit_ratings["mid"]) * 0.15, 68.0, 92.0)
	var a_comp_pct: float = clampf(74.0 + float(probs.away_unit_ratings["mid"]) * 0.15, 68.0, 92.0)
	var h_passes_completed: int = int(roundf(float(h_passes_attempted) * (h_comp_pct / 100.0)))
	var a_passes_completed: int = int(roundf(float(a_passes_attempted) * (a_comp_pct / 100.0)))

	var h_corners: int = randi_range(2, 8) + (2 if result.home_score > 0 else 0)
	var a_corners: int = randi_range(1, 6) + (2 if result.away_score > 0 else 0)

	var h_offsides: int = randi_range(1, 4) + (2 if away_manager != null and away_manager.defensive_line > 0.6 else 0)
	var a_offsides: int = randi_range(1, 4) + (2 if home_manager != null and home_manager.defensive_line > 0.6 else 0)

	var h_fouls: int = 0
	var a_fouls: int = 0
	var h_yellows: int = 0
	var a_yellows: int = 0
	var h_reds: int = 0
	var a_reds: int = 0

	for ev: MatchEventRecord in match_events:
		if ev.event_type == "yellow_card":
			if ev.team == GameManager.TEAM_A:
				h_yellows += 1
			else:
				a_yellows += 1
		elif ev.event_type == "red_card":
			if ev.team == GameManager.TEAM_A:
				h_reds += 1
			else:
				a_reds += 1

	for key: int in all_player_events:
		var p_ev: PlayerRatingCalculator.PlayerMatchEvents = all_player_events[key]
		if key / 1000 == GameManager.TEAM_A:
			h_fouls += p_ev.fouls
		else:
			a_fouls += p_ev.fouls

	result.home_stats = {
		"possession_pct": possession_home,
		"shots": h_shots_total,
		"shots_on_target": h_shots_on_target,
		"passes_attempted": h_passes_attempted,
		"pass_completion_pct": h_comp_pct,
		"fouls": h_fouls,
		"yellow_cards": h_yellows,
		"red_cards": h_reds,
		"corners": h_corners,
		"offsides": h_offsides,
	}

	result.away_stats = {
		"possession_pct": possession_away,
		"shots": a_shots_total,
		"shots_on_target": a_shots_on_target,
		"passes_attempted": a_passes_attempted,
		"pass_completion_pct": a_comp_pct,
		"fouls": a_fouls,
		"yellow_cards": a_yellows,
		"red_cards": a_reds,
		"corners": a_corners,
		"offsides": a_offsides,
	}

	# Advanced stats
	var h_xg_actual: float = probs.home_xg * (0.85 + randf() * 0.3)
	var a_xg_actual: float = probs.away_xg * (0.85 + randf() * 0.3)
	var h_psxg: float = float(result.home_score) * 0.72 + float(h_shots_on_target - result.home_score) * 0.28
	var a_psxg: float = float(result.away_score) * 0.72 + float(a_shots_on_target - result.away_score) * 0.28
	var h_gk_prevented: float = a_psxg - float(result.away_score)
	var a_gk_prevented: float = h_psxg - float(result.home_score)

	var h_field_tilt: float = clampf(possession_home + (probs.home_xg - probs.away_xg) * 4.0, 30.0, 75.0)
	var a_field_tilt: float = 100.0 - h_field_tilt

	var h_press: float = home_manager.pressing_intensity if home_manager != null else 0.5
	var a_press: float = away_manager.pressing_intensity if away_manager != null else 0.5
	var h_ppda: float = clampf(14.0 - h_press * 8.0 + randf_range(-1.0, 1.0), 5.5, 22.0)
	var a_ppda: float = clampf(14.0 - a_press * 8.0 + randf_range(-1.0, 1.0), 5.5, 22.0)

	var h_packing: int = int(roundf(float(h_passes_completed) * 0.18 + float(probs.home_unit_ratings["mid"]) * 0.4))
	var a_packing: int = int(roundf(float(a_passes_completed) * 0.18 + float(probs.away_unit_ratings["mid"]) * 0.4))
	var h_impect: int = int(roundf(float(h_shots_total) * 1.5 + float(h_corners)))
	var a_impect: int = int(roundf(float(a_shots_total) * 1.5 + float(a_corners)))

	var h_prog_passes: int = int(roundf(float(h_passes_completed) * 0.12))
	var a_prog_passes: int = int(roundf(float(a_passes_completed) * 0.12))
	var h_prog_carries: int = randi_range(12, 26)
	var a_prog_carries: int = randi_range(10, 24)

	var h_xt: float = h_xg_actual * 0.85 + float(h_prog_passes) * 0.04
	var a_xt: float = a_xg_actual * 0.85 + float(a_prog_passes) * 0.04

	var h_vaep: float = float(result.home_score) * 1.2 + h_xg_actual * 0.9 - a_xg_actual * 0.4
	var a_vaep: float = float(result.away_score) * 1.2 + a_xg_actual * 0.9 - h_xg_actual * 0.4

	result.home_advanced_stats = {
		"xg": h_xg_actual,
		"psxg": h_psxg,
		"goals_prevented": h_gk_prevented,
		"xt_delta": h_xt,
		"field_tilt_pct": h_field_tilt,
		"ppda": h_ppda,
		"packing_total": h_packing,
		"impect_total": h_impect,
		"progressive_passes": h_prog_passes,
		"progressive_carries": h_prog_carries,
		"vaep_total": h_vaep,
	}

	result.away_advanced_stats = {
		"xg": a_xg_actual,
		"psxg": a_psxg,
		"goals_prevented": a_gk_prevented,
		"xt_delta": a_xt,
		"field_tilt_pct": a_field_tilt,
		"ppda": a_ppda,
		"packing_total": a_packing,
		"impect_total": a_impect,
		"progressive_passes": a_prog_passes,
		"progressive_carries": a_prog_carries,
		"vaep_total": a_vaep,
	}

	# 6. Distribute remaining event volumes to players
	_distribute_player_match_stats(
		GameManager.TEAM_A, home_team, h_lineup, result.home_stats, result.home_advanced_stats,
		result.home_score, result.away_score, all_player_events
	)
	_distribute_player_match_stats(
		GameManager.TEAM_B, away_team, a_lineup, result.away_stats, result.away_advanced_stats,
		result.away_score, result.home_score, all_player_events
	)

	result.player_events = all_player_events

	# 7. Compute all player ratings
	var ratings: Dictionary[int, float] = {}
	for key: int in all_player_events:
		var team_id: int = key / 1000
		var sq_idx: int = key % 1000
		var t_data: TeamData = home_team if team_id == GameManager.TEAM_A else away_team
		var p_data: PlayerData = t_data.squad[sq_idx] if sq_idx < t_data.squad.size() else null
		if p_data != null:
			var r: float = PlayerRatingCalculator.calculate(p_data, all_player_events[key])
			ratings[key] = r
	result.player_ratings = ratings

	return result


## Pushes the QuickSimResult into live singletons (GameManager, MatchStatsTracker)
## and accumulates career stats on PlayerData, ManagerData, and RefereeData.
static func apply_to_match_stats_tracker(
	sim_result: QuickSimResult,
	home_team: TeamData,
	away_team: TeamData,
	referee: RefereeData = null,
	home_manager: ManagerData = null,
	away_manager: ManagerData = null
) -> void:
	# 1. Update GameManager state
	GameManager.score = [sim_result.home_score, sim_result.away_score]
	GameManager.current_phase = GameManager.MatchPhase.FULL_TIME
	GameManager.match_time = GameManager.match_duration
	GameManager.simulated_match_time = GameManager.SIMULATED_MATCH_DURATION

	# 2. Populate MatchStatsTracker traditional stats
	MatchStatsTracker.reset()
	MatchStatsTracker.stop_possession_sampling()

	MatchStatsTracker.shots_total[0] = sim_result.home_stats.get("shots", 0)
	MatchStatsTracker.shots_total[1] = sim_result.away_stats.get("shots", 0)
	MatchStatsTracker.shots_on_target[0] = sim_result.home_stats.get("shots_on_target", 0)
	MatchStatsTracker.shots_on_target[1] = sim_result.away_stats.get("shots_on_target", 0)
	MatchStatsTracker.passes_attempted[0] = sim_result.home_stats.get("passes_attempted", 0)
	MatchStatsTracker.passes_attempted[1] = sim_result.away_stats.get("passes_attempted", 0)

	var h_comp_num: int = int(roundf(float(MatchStatsTracker.passes_attempted[0]) * float(sim_result.home_stats.get("pass_completion_pct", 80.0)) / 100.0))
	var a_comp_num: int = int(roundf(float(MatchStatsTracker.passes_attempted[1]) * float(sim_result.away_stats.get("pass_completion_pct", 80.0)) / 100.0))
	MatchStatsTracker.passes_completed[0] = h_comp_num
	MatchStatsTracker.passes_completed[1] = a_comp_num

	MatchStatsTracker.fouls[0] = sim_result.home_stats.get("fouls", 0)
	MatchStatsTracker.fouls[1] = sim_result.away_stats.get("fouls", 0)
	MatchStatsTracker.yellow_cards[0] = sim_result.home_stats.get("yellow_cards", 0)
	MatchStatsTracker.yellow_cards[1] = sim_result.away_stats.get("yellow_cards", 0)
	MatchStatsTracker.red_cards[0] = sim_result.home_stats.get("red_cards", 0)
	MatchStatsTracker.red_cards[1] = sim_result.away_stats.get("red_cards", 0)
	MatchStatsTracker.corners[0] = sim_result.home_stats.get("corners", 0)
	MatchStatsTracker.corners[1] = sim_result.away_stats.get("corners", 0)
	MatchStatsTracker.offsides[0] = sim_result.home_stats.get("offsides", 0)
	MatchStatsTracker.offsides[1] = sim_result.away_stats.get("offsides", 0)

	# 3. Populate MatchStatsTracker advanced stats
	MatchStatsTracker.xg[0] = sim_result.home_advanced_stats.get("xg", 0.0)
	MatchStatsTracker.xg[1] = sim_result.away_advanced_stats.get("xg", 0.0)
	MatchStatsTracker.psxg[0] = sim_result.home_advanced_stats.get("psxg", 0.0)
	MatchStatsTracker.psxg[1] = sim_result.away_advanced_stats.get("psxg", 0.0)
	MatchStatsTracker.goals_prevented[0] = sim_result.home_advanced_stats.get("goals_prevented", 0.0)
	MatchStatsTracker.goals_prevented[1] = sim_result.away_advanced_stats.get("goals_prevented", 0.0)
	MatchStatsTracker.xt_delta[0] = sim_result.home_advanced_stats.get("xt_delta", 0.0)
	MatchStatsTracker.xt_delta[1] = sim_result.away_advanced_stats.get("xt_delta", 0.0)
	MatchStatsTracker.packing_total[0] = sim_result.home_advanced_stats.get("packing_total", 0)
	MatchStatsTracker.packing_total[1] = sim_result.away_advanced_stats.get("packing_total", 0)
	MatchStatsTracker.impect_total[0] = sim_result.home_advanced_stats.get("impect_total", 0)
	MatchStatsTracker.impect_total[1] = sim_result.away_advanced_stats.get("impect_total", 0)
	MatchStatsTracker.progressive_passes[0] = sim_result.home_advanced_stats.get("progressive_passes", 0)
	MatchStatsTracker.progressive_passes[1] = sim_result.away_advanced_stats.get("progressive_passes", 0)
	MatchStatsTracker.progressive_carries[0] = sim_result.home_advanced_stats.get("progressive_carries", 0)
	MatchStatsTracker.progressive_carries[1] = sim_result.away_advanced_stats.get("progressive_carries", 0)
	MatchStatsTracker.vaep_total[0] = sim_result.home_advanced_stats.get("vaep_total", 0.0)
	MatchStatsTracker.vaep_total[1] = sim_result.away_advanced_stats.get("vaep_total", 0.0)

	# 4. Inject PlayerMatchEvents into MatchStatsTracker dictionary
	for key: int in sim_result.player_events:
		var dest: PlayerRatingCalculator.PlayerMatchEvents = MatchStatsTracker.get_player_events(key)
		var src: PlayerRatingCalculator.PlayerMatchEvents = sim_result.player_events[key]
		dest.goals = src.goals
		dest.assists = src.assists
		dest.shots_on_target = src.shots_on_target
		dest.shots_off_target = src.shots_off_target
		dest.passes_completed = src.passes_completed
		dest.passes_failed = src.passes_failed
		dest.fouls = src.fouls
		dest.yellow_cards = src.yellow_cards
		dest.red_cards = src.red_cards
		dest.own_goals = src.own_goals
		dest.kept_clean_sheet = src.kept_clean_sheet
		dest.xg = src.xg
		dest.xa = src.xa
		dest.xt_delta = src.xt_delta
		dest.psxg = src.psxg
		dest.goals_prevented = src.goals_prevented
		dest.packing_count = src.packing_count
		dest.impect_count = src.impect_count
		dest.progressive_passes = src.progressive_passes
		dest.progressive_carries = src.progressive_carries
		dest.tackles_won = src.tackles_won
		dest.interceptions = src.interceptions
		dest.vaep = src.vaep

	# 5. Persist career stats for all players involved
	for key: int in sim_result.player_events:
		var team_id: int = key / 1000
		var sq_idx: int = key % 1000
		var p_data: PlayerData = home_team.squad[sq_idx] if team_id == GameManager.TEAM_A else away_team.squad[sq_idx]
		if p_data != null:
			var events: PlayerRatingCalculator.PlayerMatchEvents = sim_result.player_events[key]
			p_data.accumulate_match_stats(events)
			if sim_result.player_ratings.has(key):
				p_data.last_match_rating = sim_result.player_ratings[key]
				# Form drift: high rating boosts form, low rating depresses form
				var r: float = p_data.last_match_rating
				p_data.form = clampf(p_data.form * 0.8 + r * 0.2, 3.0, 10.0)

	# 6. Persist manager career stats
	var winner: int = sim_result.winner
	if home_manager != null:
		home_manager.matches_managed += 1
		home_manager.goals_scored += sim_result.home_score
		home_manager.goals_conceded += sim_result.away_score
		if winner == GameManager.TEAM_A:
			home_manager.wins += 1
		elif winner < 0:
			home_manager.draws += 1
		else:
			home_manager.losses += 1

	if away_manager != null:
		away_manager.matches_managed += 1
		away_manager.goals_scored += sim_result.away_score
		away_manager.goals_conceded += sim_result.home_score
		if winner == GameManager.TEAM_B:
			away_manager.wins += 1
		elif winner < 0:
			away_manager.draws += 1
		else:
			away_manager.losses += 1

	# 7. Persist referee career stats
	if referee != null:
		referee.matches_officiated += 1
		referee.fouls_awarded += (sim_result.home_stats.get("fouls", 0) + sim_result.away_stats.get("fouls", 0))
		referee.red_cards_issued += (sim_result.home_stats.get("red_cards", 0) + sim_result.away_stats.get("red_cards", 0))
		var m_key: String = RefereeData.make_matchup_key(home_team.team_name, away_team.team_name)
		var matchup: Dictionary = referee.get_or_create_matchup(m_key)
		matchup["matches"] = int(matchup.get("matches", 0)) + 1
		matchup["fouls_awarded"] = int(matchup.get("fouls_awarded", 0)) + referee.fouls_awarded



## Calculates positional unit ratings (GK, DEF, MID, ATT, overall) on a 30-99 scale.
static func calculate_team_units(team: TeamData, lineup_indices: Array[int] = []) -> Dictionary:
	if team == null:
		return {"gk": 50.0, "def": 50.0, "mid": 50.0, "att": 50.0, "overall": 50.0}
	var lineup: Array[int] = lineup_indices
	if lineup.size() < 11:
		if team.lineup_indices.size() == 11:
			lineup = team.lineup_indices
		else:
			lineup = _make_default_lineup(team.squad.size())
	return _calculate_team_units(team, lineup)


## Calculates star rating numeric value (e.g. 1.0 to 5.0) from overall rating.
static func get_star_rating_value(overall: float) -> float:
	if overall >= 85.0:
		return 5.0
	elif overall >= 80.0:
		return 4.5
	elif overall >= 75.0:
		return 4.0
	elif overall >= 70.0:
		return 3.5
	elif overall >= 65.0:
		return 3.0
	elif overall >= 60.0:
		return 2.5
	elif overall >= 55.0:
		return 2.0
	else:
		return 1.5


## Returns formatted star rating string (e.g. "★★★★½") from overall rating.
static func get_star_rating_string(overall: float) -> String:
	var stars: float = get_star_rating_value(overall)
	if stars >= 5.0:
		return "★★★★★"
	elif stars >= 4.5:
		return "★★★★½"
	elif stars >= 4.0:
		return "★★★★☆"
	elif stars >= 3.5:
		return "★★★½☆"
	elif stars >= 3.0:
		return "★★★☆☆"
	elif stars >= 2.5:
		return "★★½☆☆"
	elif stars >= 2.0:
		return "★★☆☆☆"
	else:
		return "★½☆☆☆"


# --- Private Mathematical & Simulation Helpers --------------------------------

static func _calculate_team_units(team: TeamData, lineup_indices: Array[int]) -> Dictionary:
	var gk_score: float = 0.0
	var def_score: float = 0.0
	var mid_score: float = 0.0
	var att_score: float = 0.0
	var def_count: int = 0
	var mid_count: int = 0
	var att_count: int = 0

	for slot: int in range(mini(11, lineup_indices.size())):
		var sq_idx: int = lineup_indices[slot]
		if sq_idx < 0 or sq_idx >= team.squad.size():
			continue
		var p: PlayerData = team.squad[sq_idx]
		var form_mod: float = 1.0 + (p.form - 6.5) * 0.04

		if slot == 0 or p.position_role == "GK":
			gk_score = (p.reflexes * 35.0 + p.composure * 25.0 + p.vision * 20.0 + (p.mass / 100.0) * 10.0 + 10.0) * form_mod
		elif slot in [1, 2, 3, 4] or p.position_role in ["CB", "LB", "RB"]:
			var def_val: float = ((p.mass / 100.0) * 25.0 + p.aggression * 25.0 + (p.top_speed / 250.0) * 20.0 + p.composure * 15.0 + p.vision * 15.0) * form_mod
			def_score += def_val
			def_count += 1
		elif slot in [5, 6, 7] or p.position_role in ["DM", "CM", "LM", "RM", "AM"]:
			var mid_val: float = (p.vision * 30.0 + p.composure * 25.0 + p.close_control * 25.0 + (p.top_speed / 250.0) * 10.0 + (p.stamina_max / 100.0) * 10.0) * form_mod
			mid_score += mid_val
			mid_count += 1
		else:
			var att_val: float = ((p.top_speed / 250.0) * 25.0 + p.close_control * 25.0 + p.composure * 25.0 + p.vision * 15.0 + p.aggression * 10.0) * form_mod
			att_score += att_val
			att_count += 1

	var avg_gk: float = clampf(gk_score, 30.0, 99.0)
	var avg_def: float = clampf(def_score / maxf(float(def_count), 1.0), 30.0, 99.0)
	var avg_mid: float = clampf(mid_score / maxf(float(mid_count), 1.0), 30.0, 99.0)
	var avg_att: float = clampf(att_score / maxf(float(att_count), 1.0), 30.0, 99.0)
	var overall: float = (avg_gk * 0.15) + (avg_def * 0.30) + (avg_mid * 0.30) + (avg_att * 0.25)

	return {
		"gk": avg_gk,
		"def": avg_def,
		"mid": avg_mid,
		"att": avg_att,
		"overall": overall
	}


static func _make_default_lineup(squad_size: int) -> Array[int]:
	var arr: Array[int] = []
	for i in range(mini(11, squad_size)):
		arr.append(i)
	return arr


static func _poisson_pmf(lambda_val: float, k: int) -> float:
	if k < 0:
		return 0.0
	var p: float = exp(-lambda_val)
	for i in range(1, k + 1):
		p *= (lambda_val / float(i))
	return p


static func _dixon_coles_tau(x: int, y: int, lambda_x: float, lambda_y: float, rho: float) -> float:
	if x == 0 and y == 0:
		return 1.0 - lambda_x * lambda_y * rho
	elif x == 0 and y == 1:
		return 1.0 + lambda_x * rho
	elif x == 1 and y == 0:
		return 1.0 + lambda_y * rho
	elif x == 1 and y == 1:
		return 1.0 - rho
	return 1.0


static func _sample_scoreline(lambda_h: float, lambda_a: float) -> Vector2i:
	var h: int = _sample_poisson(lambda_h)
	var a: int = _sample_poisson(lambda_a)
	return Vector2i(clampi(h, 0, 9), clampi(a, 0, 9))


static func _sample_poisson(lambda_val: float) -> int:
	var l: float = exp(-lambda_val)
	var k: int = 0
	var p: float = 1.0
	while p > l and k < 12:
		k += 1
		p *= randf()
	return maxi(k - 1, 0)


static func _generate_goals(
	num_goals: int,
	team_id: int,
	team_data: TeamData,
	lineup: Array[int],
	events_map: Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents],
	events_list: Array[MatchEventRecord]
) -> void:
	if num_goals <= 0:
		return

	# Weight player goal candidates based on slot and attributes
	for _g: int in range(num_goals):
		var scorer_slot: int = _pick_scorer_slot(team_data, lineup)
		var scorer_squad_idx: int = lineup[scorer_slot]
		var scorer_p: PlayerData = team_data.squad[scorer_squad_idx]
		var scorer_key: int = team_id * 1000 + scorer_squad_idx

		# Assist candidate
		var assist_slot: int = -1
		var assist_squad_idx: int = -1
		var assist_name: String = ""
		if randf() < 0.78: # 78% of goals assisted
			assist_slot = _pick_assist_slot(scorer_slot, lineup)
			if assist_slot >= 0:
				assist_squad_idx = lineup[assist_slot]
				assist_name = team_data.squad[assist_squad_idx].player_name
				var a_key: int = team_id * 1000 + assist_squad_idx
				if events_map.has(a_key):
					events_map[a_key].assists += 1
					events_map[a_key].xa += 0.55

		if events_map.has(scorer_key):
			events_map[scorer_key].goals += 1
			events_map[scorer_key].shots_on_target += 1
			events_map[scorer_key].xg += 0.65

		var rec := MatchEventRecord.new()
		rec.minute = randi_range(2, 90)
		rec.event_type = "goal"
		rec.team = team_id
		rec.player_name = scorer_p.player_name
		rec.squad_index = scorer_squad_idx
		rec.assist_player_name = assist_name
		rec.assist_squad_index = assist_squad_idx
		if assist_name != "":
			rec.description = "Goal! %s scores for %s (assist: %s)." % [scorer_p.player_name, team_data.team_name, assist_name]
		else:
			rec.description = "Goal! %s finishes clinical strike for %s." % [scorer_p.player_name, team_data.team_name]
		events_list.append(rec)


static func _pick_scorer_slot(team: TeamData, lineup: Array[int]) -> int:
	var weights: Array[float] = [0.0, 0.04, 0.08, 0.08, 0.04, 0.10, 0.14, 0.14, 0.32, 0.34, 0.32]
	var total: float = 0.0
	for i in range(mini(weights.size(), lineup.size())):
		var sq_idx: int = lineup[i]
		var p: PlayerData = team.squad[sq_idx]
		weights[i] *= (p.close_control * 1.5 + p.composure * 1.2 + 0.2)
		total += weights[i]

	var r: float = randf() * total
	var cum: float = 0.0
	for i in range(mini(weights.size(), lineup.size())):
		cum += weights[i]
		if r <= cum:
			return i
	return 8


static func _pick_assist_slot(scorer_slot: int, lineup: Array[int]) -> int:
	var candidates: Array[int] = []
	for i: int in range(1, mini(11, lineup.size())):
		if i != scorer_slot:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	return candidates[randi() % candidates.size()]


static func _generate_discipline_events(
	referee: RefereeData,
	home_team: TeamData,
	away_team: TeamData,
	h_lineup: Array[int],
	a_lineup: Array[int],
	events_map: Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents],
	events_list: Array[MatchEventRecord]
) -> void:
	var strict: float = referee.strictness if referee != null else 0.5
	var base_fouls_per_team: int = int(roundf(5.0 + strict * 9.0 + randf_range(-2.0, 2.0)))

	for team_id: int in [GameManager.TEAM_A, GameManager.TEAM_B]:
		var t_data: TeamData = home_team if team_id == GameManager.TEAM_A else away_team
		var lineup: Array[int] = h_lineup if team_id == GameManager.TEAM_A else a_lineup
		var team_fouls: int = maxi(base_fouls_per_team + randi_range(-2, 3), 2)

		for _f in range(team_fouls):
			# Distribute fouls to defensive / midfield aggressive players
			var foul_slot: int = randi_range(1, 8)
			if foul_slot < lineup.size():
				var foul_sq_idx: int = lineup[foul_slot]
				var foul_key: int = team_id * 1000 + foul_sq_idx
				if events_map.has(foul_key):
					events_map[foul_key].fouls += 1

		# Yellow cards (1 to 4 cards typical)
		var num_yellows: int = int(roundf(float(team_fouls) * (0.08 + strict * 0.10)))
		num_yellows = clampi(num_yellows, 0, 4)

		for _y in range(num_yellows):
			var y_slot: int = randi_range(1, mini(10, lineup.size() - 1))
			var y_sq_idx: int = lineup[y_slot]
			var y_p: PlayerData = t_data.squad[y_sq_idx]
			var y_key: int = team_id * 1000 + y_sq_idx
			if events_map.has(y_key):
				events_map[y_key].yellow_cards += 1

			var y_rec := MatchEventRecord.new()
			y_rec.minute = randi_range(10, 88)
			y_rec.event_type = "yellow_card"
			y_rec.team = team_id
			y_rec.player_name = y_p.player_name
			y_rec.squad_index = y_sq_idx
			y_rec.description = "Yellow Card shown to %s (%s)." % [y_p.player_name, t_data.team_name]
			events_list.append(y_rec)

		# Red cards (rare event)
		if randf() < (0.02 + strict * 0.08):
			var r_slot: int = randi_range(1, mini(6, lineup.size() - 1))
			var r_sq_idx: int = lineup[r_slot]
			var r_p: PlayerData = t_data.squad[r_sq_idx]
			var r_key: int = team_id * 1000 + r_sq_idx
			if events_map.has(r_key):
				events_map[r_key].red_cards += 1

			var r_rec := MatchEventRecord.new()
			r_rec.minute = randi_range(30, 85)
			r_rec.event_type = "red_card"
			r_rec.team = team_id
			r_rec.player_name = r_p.player_name
			r_rec.squad_index = r_sq_idx
			r_rec.description = "RED CARD! %s is sent off for %s!" % [r_p.player_name, t_data.team_name]
			events_list.append(r_rec)


static func _distribute_player_match_stats(
	team_id: int,
	team_data: TeamData,
	lineup: Array[int],
	team_stats: Dictionary,
	team_adv_stats: Dictionary,
	team_goals: int,
	opp_goals: int,
	events_map: Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents]
) -> void:
	var passes_comp: int = int(team_stats.get("passes_attempted", 400)) * int(team_stats.get("pass_completion_pct", 80)) / 100
	var passes_fail: int = int(team_stats.get("passes_attempted", 400)) - passes_comp
	var shots_tot: int = team_stats.get("shots", 10)
	var shots_on_tgt: int = team_stats.get("shots_on_target", 4)
	var _shots_off_tgt: int = shots_tot - shots_on_tgt

	var team_packing: int = team_adv_stats.get("packing_total", 50)
	var team_impect: int = team_adv_stats.get("impect_total", 15)
	var team_prog_passes: int = team_adv_stats.get("progressive_passes", 30)
	var team_prog_carries: int = team_adv_stats.get("progressive_carries", 18)
	var team_xt: float = team_adv_stats.get("xt_delta", 1.2)
	var team_vaep: float = team_adv_stats.get("vaep_total", 2.0)

	for slot: int in range(mini(11, lineup.size())):
		var sq_idx: int = lineup[slot]
		var key: int = team_id * 1000 + sq_idx
		var _p_data: PlayerData = team_data.squad[sq_idx]
		var ev: PlayerRatingCalculator.PlayerMatchEvents = events_map.get(key)
		if ev == null:
			continue

		if slot == 0:
			# Goalkeeper
			ev.kept_clean_sheet = (opp_goals == 0)
			ev.psxg = team_adv_stats.get("psxg", 1.0)
			ev.goals_prevented = team_adv_stats.get("goals_prevented", 0.0)
			ev.passes_completed = int(roundf(float(passes_comp) * 0.05))
			ev.passes_failed = int(roundf(float(passes_fail) * 0.08))
			ev.vaep = ev.goals_prevented * 0.4
		elif slot in [1, 2, 3, 4]:
			# Defenders
			ev.passes_completed = int(roundf(float(passes_comp) * 0.09))
			ev.passes_failed = int(roundf(float(passes_fail) * 0.08))
			ev.tackles_won = randi_range(2, 5)
			ev.interceptions = randi_range(2, 6)
			ev.packing_count = int(roundf(float(team_packing) * 0.06))
			ev.progressive_passes = int(roundf(float(team_prog_passes) * 0.08))
			ev.progressive_carries = int(roundf(float(team_prog_carries) * 0.08))
			ev.xt_delta = team_xt * 0.05
			ev.vaep = team_vaep * 0.06
		elif slot in [5, 6, 7]:
			# Midfielders
			ev.passes_completed = int(roundf(float(passes_comp) * 0.15))
			ev.passes_failed = int(roundf(float(passes_fail) * 0.12))
			ev.tackles_won = randi_range(1, 4)
			ev.interceptions = randi_range(1, 4)
			ev.packing_count = int(roundf(float(team_packing) * 0.16))
			ev.impect_count = int(roundf(float(team_impect) * 0.14))
			ev.progressive_passes = int(roundf(float(team_prog_passes) * 0.18))
			ev.progressive_carries = int(roundf(float(team_prog_carries) * 0.16))
			ev.xt_delta = team_xt * 0.18
			ev.vaep = team_vaep * 0.14
			if ev.shots_on_target == 0 and randf() < 0.4:
				ev.shots_off_target = 1
		else:
			# Forwards / Attackers
			ev.passes_completed = int(roundf(float(passes_comp) * 0.06))
			ev.passes_failed = int(roundf(float(passes_fail) * 0.08))
			ev.tackles_won = randi_range(0, 2)
			ev.interceptions = randi_range(0, 2)
			ev.impect_count = int(roundf(float(team_impect) * 0.20))
			ev.progressive_carries = int(roundf(float(team_prog_carries) * 0.14))
			ev.xt_delta = team_xt * 0.14
			ev.vaep = team_vaep * 0.16
			if ev.shots_on_target == 0 and randf() < 0.6:
				ev.shots_on_target = 1
				ev.shots_off_target = randi_range(0, 2)
