##
## RelationshipData
##
## One directed edge in the club relationship graph: how player A regards
## player B (or how a player regards the manager). Directed on purpose — a
## senior pro can rate a youngster far higher than the youngster rates them.
##
## trust here is the PERSISTENT, between-match memory. It is distinct from
## entities/player/TrustSystem.gd, which is the in-match, per-90-minutes
## accumulator that resets at kickoff. CareerManager seeds the in-match system
## from this one before every match (see seed_match_trust()), which is the
## bridge that makes off-pitch fallout visible in on-pitch passing.
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

## The in-match TrustSystem multiplier band this maps onto. Kept identical to
## TrustSystem.TRUST_MULT_MIN/MAX so a seeded value and an earned value mean
## exactly the same thing to PassUtilityScorer.
const MATCH_MULT_MIN: float = 0.85
const MATCH_MULT_MAX: float = 1.15


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
