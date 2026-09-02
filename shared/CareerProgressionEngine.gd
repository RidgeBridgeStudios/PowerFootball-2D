##
## CareerProgressionEngine
##
## Pure-logic progression engine and dynamic career simulator.
## Evaluates match outcomes and off-pitch career state transitions across:
##   - Club stature and reputation drift (upset bonuses, expectations)
##   - Manager reputation and board confidence dynamics
##   - Player fame (reputation), FM-style personality ego drift, and morale
##   - Referee match performance evaluation and dynamic league-wide respect
##   - Financial payroll deductions and contract progressions
##
## Depends on: TeamData, PlayerData, ManagerData, RefereeData, PlayerRatingCalculator.
## Exposes: process_matchday_progression(), evaluate_club_expectation(),
##          apply_payroll_deduction().
##

class_name CareerProgressionEngine
extends RefCounted


class ProgressionReport:
	var home_team_rep_delta: float = 0.0
	var away_team_rep_delta: float = 0.0
	var home_mgr_confidence_delta: float = 0.0
	var away_mgr_confidence_delta: float = 0.0
	var referee_match_rating: float = 7.0
	var referee_respect_delta: float = 0.0
	var notable_developments: Array[String] = []


## Processes complete matchday progression for two clubs, their managers, their players, and the match official.
static func process_matchday_progression(
	home_team: TeamData,
	away_team: TeamData,
	home_mgr: ManagerData,
	away_mgr: ManagerData,
	ref: RefereeData,
	home_score: int,
	away_score: int,
	fouls_count: int = 0,
	yellows_count: int = 0,
	reds_count: int = 0,
	penalties_count: int = 0,
	player_events: Dictionary = {},
	player_ratings: Dictionary = {}
) -> ProgressionReport:
	var report := ProgressionReport.new()

	# 1. Team reputation and stature dynamics based on expectation
	var rep_diff: float = home_team.reputation - away_team.reputation
	# Home advantage baseline expectation is +0.10
	var expected_home_win_margin: float = rep_diff * 2.0 + 0.20
	var actual_margin: float = float(home_score - away_score)

	var home_result_factor: float = (actual_margin - expected_home_win_margin) * 0.015
	home_result_factor = clampf(home_result_factor, -0.04, 0.04)

	home_team.update_reputation(home_result_factor)
	away_team.update_reputation(-home_result_factor)

	report.home_team_rep_delta = home_result_factor
	report.away_team_rep_delta = -home_result_factor

	# 2. Manager reputation & board confidence dynamics
	if home_mgr != null:
		var home_conf_delta: float = (actual_margin - expected_home_win_margin) * 0.025
		if home_score > away_score:
			home_conf_delta += 0.02
		elif home_score < away_score:
			home_conf_delta -= 0.02
		home_mgr.update_board_confidence(home_conf_delta)
		home_mgr.update_reputation(home_result_factor * 0.8)
		report.home_mgr_confidence_delta = home_conf_delta

	if away_mgr != null:
		var away_conf_delta: float = (-actual_margin + expected_home_win_margin) * 0.025
		if away_score > home_score:
			away_conf_delta += 0.02
		elif away_score < home_score:
			away_conf_delta -= 0.02
		away_mgr.update_board_confidence(away_conf_delta)
		away_mgr.update_reputation(-home_result_factor * 0.8)
		report.away_mgr_confidence_delta = away_conf_delta

	# 3. Referee evaluation and dynamic respect drift
	if ref != null:
		var prev_respect: float = ref.respect_rating
		var controversy: float = 0.0
		if penalties_count >= 2:
			controversy += float(penalties_count - 1) * 0.8
		if reds_count >= 2:
			controversy += float(reds_count - 1) * 0.5
		if absi(fouls_count - 24) > 12:
			controversy += 0.4

		var perf_score: float = ref.evaluate_match_performance(
			fouls_count, yellows_count, reds_count, penalties_count, controversy
		)
		ref.apply_match_evaluation(perf_score)
		report.referee_match_rating = perf_score
		report.referee_respect_delta = ref.respect_rating - prev_respect

		if perf_score < 5.0:
			report.notable_developments.append(
				"Controversial officiating by %s: Respect rating dropped to %.0f%%." % [
					ref.referee_name, ref.respect_rating * 100.0
				]
			)

	# 4. Player development, fame (reputation), ego drift, and morale
	_process_team_players(home_team, 0, player_ratings, player_events, report)
	_process_team_players(away_team, 1, player_ratings, player_events, report)

	return report


## Evaluates squad players for fame growth, personality drift, and morale.
static func _process_team_players(
	team: TeamData,
	team_side: int,
	ratings: Dictionary,
	events: Dictionary,
	report: ProgressionReport
) -> void:
	for slot in range(team.squad.size()):
		var p: PlayerData = team.squad[slot]
		var key: int = team_side * 1000 + slot
		var has_played: bool = ratings.has(key)

		if has_played:
			var rating: float = float(ratings[key])
			p.last_match_rating = rating
			# Form drift
			p.form = clampf(p.form * 0.75 + rating * 0.25, 1.0, 10.0)

			# Fame (reputation) growth from match rating
			if rating >= 7.5:
				var rep_gain: float = (rating - 7.0) * 0.015
				p.player_reputation = clampf(p.player_reputation + rep_gain, 0.05, 0.99)

			# Event-based fame
			if events.has(key):
				var ev_obj: Variant = events[key]
				if ev_obj is PlayerRatingCalculator.PlayerMatchEvents:
					var ev: PlayerRatingCalculator.PlayerMatchEvents = ev_obj as PlayerRatingCalculator.PlayerMatchEvents
					if ev.goals > 0:
						p.player_reputation = clampf(p.player_reputation + float(ev.goals) * 0.02, 0.05, 0.99)
					if ev.assists > 0:
						p.player_reputation = clampf(p.player_reputation + float(ev.assists) * 0.01, 0.05, 0.99)

			# Dynamic personality & ego drift:
			# If a player becomes famous (reputation > 0.75) and has low professionalism (< 0.55),
			# their ambition expands and temperament becomes volatile (ego drift).
			if p.player_reputation > 0.75 and p.professionalism < 0.55:
				p.ambition = minf(p.ambition + 0.01, 0.98)
				p.temperament = maxf(p.temperament - 0.01, 0.20)
				if p.loyalty > 0.30:
					p.loyalty = maxf(p.loyalty - 0.01, 0.15)
				report.notable_developments.append(
					"%s's rising fame is causing growing ego and contract ambition." % p.player_name
				)

			# High determination helps recovery from poor matches
			if rating < 5.5 and p.determination >= 0.75:
				p.morale = clampf(p.morale + 0.02, 0.2, 1.0) # Determined to bounce back
			elif rating < 5.5:
				p.morale = clampf(p.morale - 0.05, 0.1, 1.0)
			else:
				p.morale = clampf(p.morale + 0.03, 0.1, 1.0)
		else:
			# Player did not feature in match
			p.form = clampf(p.form - 0.05, 4.0, 10.0)
			# Unused "Star Player" or "Important" player loses morale
			match p.squad_status:
				"Star Player":
					p.morale = clampf(p.morale - 0.08, 0.1, 1.0)
					if p.morale < 0.40:
						report.notable_developments.append(
							"Star player %s is disgruntled over lack of playing time." % p.player_name
						)
				"Important":
					p.morale = clampf(p.morale - 0.04, 0.1, 1.0)
				_:
					pass
