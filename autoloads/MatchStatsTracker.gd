##
## MatchStatsTracker (Autoload singleton)
##
## Per-match statistics container and ratings accessor.
##
## Before the manager-only pivot this singleton was a live in-match collector:
## it sampled possession from MatchWorldModel every 30 physics ticks, connected
## to 13 real-time GameEvents (ball_struck, foul_committed, offside_called,
## tackle_won, ...), maintained the anti-snowball team-momentum accumulator and
## counted Moneyball analytics as the 22-player match played out.
##
## All of that was Layer 1-3 match-engine machinery and has been archived under
## legacy/. What remains is the part QuickSimEngine and MatchStatsUI actually
## need: a flat container that QuickSimEngine.apply_to_match_stats_tracker()
## writes a simulated result into, and that MatchStatsUI reads back for the
## full-time review.
##
## Depends on: PlayerRatingCalculator, PlayerData, DataLoader, GameManager.
## Exposes: get_player_events(), compute_all_ratings(), get_stats(),
##          get_advanced_stats(), reset(), stop_possession_sampling().
##
## Traditional, advanced and zone stat fields are public because QuickSimEngine
## assigns them directly, exactly as it did before the pivot.
##

extends Node

## --- Traditional Team Stats --------------------------------------------------
var shots_total: Array[int] = [0, 0]
var shots_on_target: Array[int] = [0, 0]
var passes_attempted: Array[int] = [0, 0]
var passes_completed: Array[int] = [0, 0]
var fouls: Array[int] = [0, 0]
var yellow_cards: Array[int] = [0, 0]
var red_cards: Array[int] = [0, 0]
var corners: Array[int] = [0, 0]
var offsides: Array[int] = [0, 0]

## --- Advanced / Moneyball Team Stats -----------------------------------------
var xg: Array[float] = [0.0, 0.0]
var psxg: Array[float] = [0.0, 0.0]
var goals_prevented: Array[float] = [0.0, 0.0]
var xt_delta: Array[float] = [0.0, 0.0]
var packing_total: Array[int] = [0, 0]
var impect_total: Array[int] = [0, 0]
var progressive_passes: Array[int] = [0, 0]
var progressive_carries: Array[int] = [0, 0]
var vaep_total: Array[float] = [0.0, 0.0]

## Zone & touch counters, read back by get_advanced_stats().
var final_third_touches: Array[int] = [0, 0]
var defensive_actions_opp_half: Array[int] = [0, 0]
var opp_passes_def_half: Array[int] = [0, 0]

## Possession samples, read back by get_stats(). Nothing writes these any more
## (there is no live sampler), so possession_pct reports its neutral 50.0
## fallback — identical to the value the quick-sim path produced before the
## pivot, since a simulated match never populated them either.
var _possession_samples: Array[int] = [0, 0]
var _total_possession_samples: int = 0

## Per-player match events, keyed by `team * 1000 + squad_index`. QuickSimEngine
## injects one entry per simulated player; every entry is allocated once and
## mutated in place.
var _player_events: Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents] = {}


## Clears every counter ahead of a new match. QuickSimEngine calls this before
## publishing a simulated result.
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
	xg = [0.0, 0.0]
	psxg = [0.0, 0.0]
	goals_prevented = [0.0, 0.0]
	xt_delta = [0.0, 0.0]
	packing_total = [0, 0]
	impect_total = [0, 0]
	progressive_passes = [0, 0]
	progressive_carries = [0, 0]
	vaep_total = [0.0, 0.0]
	final_third_touches = [0, 0]
	defensive_actions_opp_half = [0, 0]
	opp_passes_def_half = [0, 0]
	_possession_samples = [0, 0]
	_total_possession_samples = 0
	_player_events.clear()


## Retained so QuickSimEngine's publish sequence stays unchanged. There is no
## live possession sampler to stop any more.
func stop_possession_sampling() -> void:
	pass


func get_player_events(player_id: int) -> PlayerRatingCalculator.PlayerMatchEvents:
	if not _player_events.has(player_id):
		_player_events[player_id] = PlayerRatingCalculator.PlayerMatchEvents.new()
	return _player_events[player_id]


func compute_all_ratings() -> Dictionary[int, float]:
	var ratings: Dictionary[int, float] = {}

	for key: int in _player_events:
		var team: int = key / 1000
		var squad_index: int = key % 1000
		var player_data: PlayerData = DataLoader.get_player(team, squad_index)
		if player_data == null:
			continue

		var events: PlayerRatingCalculator.PlayerMatchEvents = _player_events[key]
		events.kept_clean_sheet = _resolve_clean_sheet(player_data, team)

		if player_data.position_role == "GK":
			var opponent_team: int = 1 - team
			var conceded: int = GameManager.score[opponent_team]
			events.goals_prevented = events.psxg - float(conceded)

		var rating: float = PlayerRatingCalculator.calculate(player_data, events)
		ratings[key] = rating
		player_data.last_match_rating = rating
		player_data.accumulate_match_stats(events)

	return ratings


func _resolve_clean_sheet(player_data: PlayerData, team: int) -> bool:
	if player_data.position_role != "GK":
		return false
	var opponent_team: int = 1 - team
	return GameManager.score[opponent_team] == 0


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


func get_advanced_stats(team_index: int) -> Dictionary:
	var total_ft_touches: int = final_third_touches[0] + final_third_touches[1]
	var field_tilt: float = 50.0
	if total_ft_touches > 0:
		field_tilt = float(final_third_touches[team_index]) / float(total_ft_touches) * 100.0

	var opp_passes_in_def_zone: int = opp_passes_def_half[team_index]
	var def_actions_in_att_zone: int = defensive_actions_opp_half[team_index]
	var ppda_val: float = 0.0
	if def_actions_in_att_zone > 0:
		ppda_val = float(opp_passes_in_def_zone) / float(def_actions_in_att_zone)

	var opp_team: int = 1 - team_index
	var goals_conceded: int = GameManager.score[opp_team]
	var gk_prevented: float = psxg[opp_team] - float(goals_conceded)

	return {
		"xg": xg[team_index],
		"psxg": psxg[team_index],
		"goals_prevented": gk_prevented,
		"xt_delta": xt_delta[team_index],
		"field_tilt_pct": field_tilt,
		"ppda": ppda_val,
		"packing_total": packing_total[team_index],
		"impect_total": impect_total[team_index],
		"progressive_passes": progressive_passes[team_index],
		"progressive_carries": progressive_carries[team_index],
		"vaep_total": vaep_total[team_index],
	}
