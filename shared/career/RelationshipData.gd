##
## RelationshipData
##
## One directed edge in the club relationship graph: how player A regards
## player B (or how a player regards the manager). Directed on purpose — a
## senior pro can rate a youngster far higher than the youngster rates them.
##
## trust here is the PERSISTENT, between-match memory. The in-match accumulator
## it used to seed before every match (seed_match_trust()) belonged to the
## pre-pivot real-time match layer archived under legacy/, so nothing in the live
## quick-sim path consumes trust yet.
##
## Depends on: nothing.
## Exposes: the fields below, adjust_trust(), adjust_rivalry(), note(),
##          to_match_multiplier(), relation_label().
##

class_name RelationshipData
extends Resource

## 0.0 = actively will not pass to them, 0.5 = neutral, 1.0 = inseparable.
@export_range(0.0, 1.0) var trust: float = 0.5
## 0.0 = no friction, 1.0 = open feud.
@export_range(0.0, 1.0) var rivalry_score: float = 0.0
## Tagged history, newest last. Capped at HISTORY_CAP entries.
@export var history: Array[String] = []
## Career day-ordinal of the last meaningful interaction, for decay toward
## neutral when two players simply stop having anything to do with each other.
@export var last_interaction_ordinal: int = 0

const HISTORY_CAP: int = 12
## Trust drifts this far back toward neutral per 30 idle days.
const MONTHLY_DECAY: float = 0.02

## The in-match pass-utility multiplier band this maps onto, kept identical to the
## retired in-match trust band so a seeded value and an earned value would mean
## the same thing. Both consumers were archived under legacy/.
const MATCH_MULT_MIN: float = 0.85
const MATCH_MULT_MAX: float = 1.15

## Manager relationship keys live OUTSIDE the 0-21999 player_key space.
## Key = MANAGER_RELATIONSHIP_KEY_BASE + league_team_index (docs/SOCIAL_SIMULATION_ARCHITECTURE.md §2.3).
const MANAGER_RELATIONSHIP_KEY_BASE: int = 100000

## Base benching resentment trust delta per match (scaled by 1.0 - loyalty)
const BENCHING_RESENTMENT_BASE_TRUST_DELTA: float = -0.06

## Match micro-event impact constants (docs/SOCIAL_SIMULATION_ARCHITECTURE.md §2.2)
const PASS_COMPLETION_TRUST_DELTA: float = 0.01
const PASS_COMPLETION_TRUST_CAP: float = 0.05
const PASS_INTERCEPT_TRUST_DELTA: float = -0.02
const PASS_INTERCEPT_TRUST_CAP: float = -0.08
const ASSIST_TRUST_DELTA: float = 0.04
const GOAL_CONVERTED_TRUST_DELTA: float = 0.03
const RED_CARD_RIVALRY_DELTA: float = 0.05
const RED_CARD_TRUST_DELTA: float = -0.03
const OWN_GOAL_TRUST_DELTA: float = -0.02
const CLEAN_SHEET_TRUST_DELTA: float = 0.02


static func manager_relationship_key(league_team_index: int) -> int:
	return MANAGER_RELATIONSHIP_KEY_BASE + league_team_index


static func is_manager_key(key: int) -> bool:
	return key >= MANAGER_RELATIONSHIP_KEY_BASE



func adjust_trust(delta: float, reason: String, ordinal: int) -> void:
	trust = clampf(trust + delta, 0.0, 1.0)
	last_interaction_ordinal = ordinal
	if reason != "":
		note(reason)


func adjust_rivalry(delta: float, reason: String, ordinal: int) -> void:
	rivalry_score = clampf(rivalry_score + delta, 0.0, 1.0)
	last_interaction_ordinal = ordinal
	if reason != "":
		note(reason)


func note(entry: String) -> void:
	history.append(entry)
	while history.size() > HISTORY_CAP:
		history.remove_at(0)


## Pulls trust back toward 0.5 and rivalry toward 0.0 for every 30 days since
## the last interaction. Called once per in-game month by CareerManager.
func decay_toward_neutral(current_ordinal: int) -> void:
	var idle_days: int = maxi(current_ordinal - last_interaction_ordinal, 0)
	if idle_days < 30:
		return
	var steps: float = float(idle_days) / 30.0
	var pull: float = MONTHLY_DECAY * steps
	trust = move_toward(trust, 0.5, pull)
	rivalry_score = move_toward(rivalry_score, 0.0, pull)
	last_interaction_ordinal = current_ordinal


## Converts the persistent 0..1 trust into the in-match pass-utility
## multiplier band, with rivalry biting on top: two players who trust each
## other but are in an open feud still will not look for one another.
func to_match_multiplier() -> float:
	var effective: float = clampf(trust - rivalry_score * 0.5, 0.0, 1.0)
	return lerpf(MATCH_MULT_MIN, MATCH_MULT_MAX, effective)


func relation_label() -> String:
	if rivalry_score >= 0.6:
		return "Feud"
	if rivalry_score >= 0.3:
		return "Friction"
	if trust >= 0.8:
		return "Close"
	if trust >= 0.62:
		return "Good"
	if trust <= 0.2:
		return "Distrust"
	if trust <= 0.38:
		return "Strained"
	return "Neutral"


static func neutral(ordinal: int) -> RelationshipData:
	var r := RelationshipData.new()
	r.last_interaction_ordinal = ordinal
	return r


## Batches match micro-events between two teammates into this relationship edge
## per docs/SOCIAL_SIMULATION_ARCHITECTURE.md §2.2.
func batch_match_micro_events(
	passes_completed: int,
	passes_failed: int,
	assists_to: int,
	assists_from: int,
	teammate_red_card: bool,
	teammate_own_goal: bool,
	clean_sheet: bool,
	ordinal: int
) -> void:
	var trust_delta: float = 0.0

	# 1. Pass completion trust (+0.01 per completion, capped at +0.05 per match)
	if passes_completed > 0:
		trust_delta += clampf(float(passes_completed) * PASS_COMPLETION_TRUST_DELTA, 0.0, PASS_COMPLETION_TRUST_CAP)

	# 2. Misplaced passes under pressure / interceptions (-0.02 per failure, capped at -0.08 per match)
	if passes_failed > 0:
		trust_delta += clampf(float(passes_failed) * PASS_INTERCEPT_TRUST_DELTA, PASS_INTERCEPT_TRUST_CAP, 0.0)

	# 3. Direct goal / assist synergy
	if assists_from > 0:
		trust_delta += float(assists_from) * ASSIST_TRUST_DELTA
	if assists_to > 0:
		trust_delta += float(assists_to) * GOAL_CONVERTED_TRUST_DELTA

	# 4. Disciplinary and critical blunders
	if teammate_red_card:
		trust_delta += RED_CARD_TRUST_DELTA
		adjust_rivalry(RED_CARD_RIVALRY_DELTA, "teammate red card", ordinal)
	if teammate_own_goal:
		trust_delta += OWN_GOAL_TRUST_DELTA
		note("teammate own goal")

	# 5. Clean sheet defensive solidity
	if clean_sheet:
		trust_delta += CLEAN_SHEET_TRUST_DELTA

	if not is_zero_approx(trust_delta):
		var reason: String = ""
		if assists_from > 0 or assists_to > 0:
			reason = "goal combination"
		elif passes_failed > 2:
			reason = "misplaced pass under pressure"
		adjust_trust(trust_delta, reason, ordinal)

