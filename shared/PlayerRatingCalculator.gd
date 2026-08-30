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

const BASE_RATING: float = 6.0
const MIN_RATING: float = 1.0
const MAX_RATING: float = 10.0
## A sent-off player's rating never exceeds this, regardless of other events.
const RED_CARD_CAP: float = 3.5

const GOAL_DELTA: float = 1.2
const ASSIST_DELTA: float = 0.8
const SHOT_ON_TARGET_DELTA: float = 0.15
const SHOT_OFF_TARGET_DELTA: float = -0.05
const PASS_COMPLETED_DELTA: float = 0.04
const PASS_FAILED_DELTA: float = -0.08
const FOUL_DELTA: float = -0.15
const YELLOW_CARD_DELTA: float = -0.5
const RED_CARD_DELTA: float = -1.5
const CLEAN_SHEET_DELTA: float = 0.9
const OWN_GOAL_DELTA: float = -1.0


## player_data is accepted for interface symmetry (a future personality-driven
## modifier would read it) — the current formula is event-only.
static func calculate(_player_data: PlayerData, events: PlayerMatchEvents) -> float:
	var rating: float = BASE_RATING
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
	if events.kept_clean_sheet:
		rating += CLEAN_SHEET_DELTA

	rating = clampf(rating, MIN_RATING, MAX_RATING)
	if events.red_cards > 0:
		rating = minf(rating, RED_CARD_CAP)
	return rating
