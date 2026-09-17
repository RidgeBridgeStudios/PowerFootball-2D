##
## PlayerRatingCalculator
##
## Pure function: turns one player's accumulated match events into a 1.0-10.0
## rating. No state, no signals, no Node — MatchStatsTracker owns collecting
## the events; this only knows how to score them.
##
## Depends on: PlayerData.
## Exposes: PlayerMatchEvents, calculate(player_data, events)
##

class_name PlayerRatingCalculator
extends RefCounted

## Per-player counters for one match. Allocated once per player (by
## MatchStatsTracker) and mutated in place for the rest of the match — never
## re-instantiated mid-match.
class PlayerMatchEvents:
	var goals: int = 0
	var assists: int = 0
	var shots_on_target: int = 0
	var shots_off_target: int = 0
	var passes_completed: int = 0
	var passes_failed: int = 0
	var fouls: int = 0
	var yellow_cards: int = 0
	var red_cards: int = 0
	var own_goals: int = 0
	var kept_clean_sheet: bool = false
	var xg: float = 0.0
	var xa: float = 0.0
	var xt_delta: float = 0.0
	var psxg: float = 0.0
	var goals_prevented: float = 0.0
	var packing_count: int = 0
	var impect_count: int = 0
	var progressive_passes: int = 0
	var progressive_carries: int = 0
	var tackles_won: int = 0
	var interceptions: int = 0
	var vaep: float = 0.0
	var touches: int = 0
	## Teammate squad_index -> interaction/pass count
	var teammate_interactions: Dictionary[int, int] = {}
	## Teammate squad_index -> assists provided
	var teammate_assists: Dictionary[int, int] = {}

	func get_touches() -> int:
		if touches > 0:
			return touches
		return passes_completed + passes_failed + shots_on_target + shots_off_target + tackles_won + interceptions


## Rating a player who did nothing notable either way finishes on — the centre
## of the distribution, not the bottom of it. Calibration: raised 6.0 -> 6.70.
## At 6.0 the whole population sat below the real-world average and every
## rating was a climb out of a hole, so an ordinary shift by a centre-back
## (few events, all small) scored as a bad game.
const BASE_RATING: float = 6.70
const MIN_RATING: float = 1.0
const MAX_RATING: float = 10.0
## A sent-off player's rating is confined to this band. Calibration: the old
## single 3.5 cap put a red card two full points below the worst rating real
## match ratings ever hand out; a sending-off is a terrible afternoon, not an
## unrecognisable one.
const RED_CARD_CAP: float = 5.80
const RED_CARD_FLOOR: float = 5.20

## Half-width of the rating distribution. The summed event deltas are passed
## through SPREAD * tanh(sum / SPREAD) before being added to BASE_RATING, which
## keeps the curve linear for ordinary performances and compresses the tails —
## so ratings bunch around the base and thin out toward the extremes, instead
## of the old model's unbounded linear sum where a high-volume passer could
## out-rate a hat-trick on completed-pass deltas alone. Asymptotes at
## BASE_RATING +/- SPREAD (4.10 to 9.30).
const RATING_SPREAD: float = 2.60

## Event deltas, rebalanced against the compression curve above so the
## resulting bands land where match ratings actually sit:
##   ordinary shift        6.6 - 6.8
##   strong performance    7.3 - 7.8
##   match-winning / hat-trick  8.2 - 9.4
##   catastrophic          5.2 - 5.8
const GOAL_DELTA: float = 0.95
const ASSIST_DELTA: float = 0.50
const SHOT_ON_TARGET_DELTA: float = 0.10
const SHOT_OFF_TARGET_DELTA: float = -0.04
## Calibration: cut 0.04 -> 0.005. A 90-minute midfielder completes 40-70
## passes; at 0.04 that alone was worth +1.6 to +2.8, which is more than a
## hat-trick and is why volume passers dominated the old distribution.
const PASS_COMPLETED_DELTA: float = 0.005
const PASS_FAILED_DELTA: float = -0.025
const FOUL_DELTA: float = -0.12
const YELLOW_CARD_DELTA: float = -0.40
const RED_CARD_DELTA: float = -1.50
const CLEAN_SHEET_DELTA: float = 0.40
const OWN_GOAL_DELTA: float = -1.00
const TACKLE_WON_DELTA: float = 0.06
const INTERCEPTION_DELTA: float = 0.045
const PROGRESSIVE_ACTION_DELTA: float = 0.03
const PACKING_BONUS_DELTA: float = 0.010
const VAEP_DELTA: float = 0.60
const GOALS_PREVENTED_DELTA: float = 0.55


## player_data is accepted for interface symmetry (a future personality-driven
## modifier would read it) — the current formula incorporates traditional and advanced metrics.
static func calculate(_player_data: PlayerData, events: PlayerMatchEvents) -> float:
	var rating: float = 0.0
	rating += float(events.goals) * GOAL_DELTA
	rating += float(events.assists) * ASSIST_DELTA
	rating += float(events.shots_on_target) * SHOT_ON_TARGET_DELTA
	rating += float(events.shots_off_target) * SHOT_OFF_TARGET_DELTA
	rating += float(events.passes_completed) * PASS_COMPLETED_DELTA
	rating += float(events.passes_failed) * PASS_FAILED_DELTA
	rating += float(events.fouls) * FOUL_DELTA
	rating += float(events.yellow_cards) * YELLOW_CARD_DELTA
	rating += float(events.red_cards) * RED_CARD_DELTA
	rating += float(events.own_goals) * OWN_GOAL_DELTA
	rating += float(events.tackles_won) * TACKLE_WON_DELTA
	rating += float(events.interceptions) * INTERCEPTION_DELTA
	rating += float(events.progressive_passes + events.progressive_carries) * PROGRESSIVE_ACTION_DELTA
	rating += float(events.packing_count) * PACKING_BONUS_DELTA
	rating += events.vaep * VAEP_DELTA
	rating += events.goals_prevented * GOALS_PREVENTED_DELTA
	if events.kept_clean_sheet:
		rating += CLEAN_SHEET_DELTA

	# Compress the summed deltas into the distribution. tanh is linear near zero
	# — an ordinary game's small deltas are barely touched — and saturates at
	# the tails, so no single high-volume counter can run the rating away.
	rating = BASE_RATING + RATING_SPREAD * tanh(rating / RATING_SPREAD)

	rating = clampf(rating, MIN_RATING, MAX_RATING)
	if events.red_cards > 0:
		rating = clampf(rating, RED_CARD_FLOOR, RED_CARD_CAP)
	return rating

