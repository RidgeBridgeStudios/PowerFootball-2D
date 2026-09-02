##
## RefereeData
##
## Pure data container for one referee: identity, personality, and career stats.
## Saveable as a .tres resource, same discipline as PlayerData — this never
## touches a Node. MatchReferee reads the personality fields to make live
## per-foul decisions during a match and writes career stats back at FULL_TIME;
## the personality fields themselves are never mutated at runtime.
##
## Depends on: nothing.
## Exposes: the fields below, get_fouls_per_match(), get_penalties_per_match(),
##          get_or_create_matchup(key), make_matchup_key(a, b), make_default().
##

class_name RefereeData
extends Resource

## --- Identity ------------------------------------------------------------------

@export var referee_name: String = ""
@export var nationality: String = ""
## 1–100. Higher = more years experience, but NOT correlated with quality.
@export var experience: int = 50

## --- Personality — independent 0..1 attributes, fixed for the referee's career -

## 0 = lets almost everything go, 1 = whistles every brush of contact.
@export_range(0.0, 1.0) var strictness: float = 0.5
## 0 = wildly varies standards across the match, 1 = applies the same threshold every call.
@export_range(0.0, 1.0) var consistency: float = 0.5
## 0 = rattled by crowd/game intensity, affecting leniency, 1 = unaffected by match temperature.
@export_range(0.0, 1.0) var composure: float = 0.5
## 0 = fully impartial, 1 = will quietly favour one team (team is decided at match start).
@export_range(0.0, 1.0) var unprofessionalism: float = 0.0
## 0 = considers all factors before deciding, 1 = decides in the heat of the moment and gets it wrong more.
@export_range(0.0, 1.0) var incoherence: float = 0.0
## 0 = unknown, 1 = highly respected; affects how much teams "expect" favouritism from them.
@export_range(0.0, 1.0) var reputation: float = 0.5
## League-wide respect rating (0.0 = widely distrusted, 1.0 = universally revered authority).
## Degrades after matches with high controversy, erratic penalties, or poor consistency;
## increases with clean, composed, consistent displays.
@export_range(0.0, 1.0) var respect_rating: float = 0.50

## Rolling match officiating ratings (0.0 - 10.0).
var recent_match_ratings: Array[float] = []

## --- Career stats (persisted across matches) ------------------------------------

## Total matches officiated.
var matches_officiated: int = 0
## Total fouls awarded lifetime.
var fouls_awarded: int = 0
## Total penalties awarded lifetime.
var penalties_awarded: int = 0
## Total red cards (future-proofing; not implemented yet but tracked).
var red_cards_issued: int = 0
## Per-matchup history: key is a matchup_key string ("TeamA|TeamB", sorted),
## value is a Dictionary with keys: matches, fouls_awarded, penalties_awarded.
var matchup_history: Dictionary = {}


func get_fouls_per_match() -> float:
	if matches_officiated == 0:
		return 0.0
	return float(fouls_awarded) / float(matches_officiated)


func get_penalties_per_match() -> float:
	if matches_officiated == 0:
		return 0.0
	return float(penalties_awarded) / float(matches_officiated)


## Returns or creates the history entry for a given matchup key.
func get_or_create_matchup(key: String) -> Dictionary:
	if not matchup_history.has(key):
		matchup_history[key] = {"matches": 0, "fouls_awarded": 0, "penalties_awarded": 0}
	return matchup_history[key]


static func make_matchup_key(team_a_name: String, team_b_name: String) -> String:
	var names: Array[String] = [team_a_name, team_b_name]
	names.sort()
	return "%s|%s" % [names[0], names[1]]


static func make_default(referee_name: String, nationality: String) -> RefereeData:
	var r := RefereeData.new()
	r.referee_name = referee_name
	r.nationality = nationality
	return r


## Evaluates officiating performance from match events and returns a match rating (0.0 - 10.0).
func evaluate_match_performance(fouls: int, yellows: int, reds: int, penalties: int, controversy_score: float = 0.0) -> float:
	var base_score: float = 7.0
	# Deviations from normal match baseline
	var foul_penalty: float = maxf(0.0, float(fouls - 22)) * 0.08
	var card_penalty: float = maxf(0.0, float(yellows + reds * 2 - 4)) * 0.15
	var penalty_penalty: float = maxf(0.0, float(penalties - 1)) * 0.40
	# Incoherence & unprofessionalism magnify controversy impact
	var personality_flaw: float = (incoherence * 0.6 + unprofessionalism * 0.4)
	var scaled_controversy: float = controversy_score * (1.0 + personality_flaw)
	var score: float = base_score - foul_penalty - card_penalty - penalty_penalty - scaled_controversy + (consistency * 0.8) + (composure * 0.6)
	return clampf(score, 1.0, 10.0)


## Applies match rating and updates respect_rating and reputation.
func apply_match_evaluation(perf_score: float) -> void:
	recent_match_ratings.append(perf_score)
	if recent_match_ratings.size() > 10:
		recent_match_ratings.pop_front()
	# Performance delta relative to standard baseline 6.5
	var delta: float = (perf_score - 6.5) * 0.02
	respect_rating = clampf(respect_rating + delta, 0.05, 0.99)
	reputation = clampf(reputation + delta * 0.5, 0.05, 0.99)
