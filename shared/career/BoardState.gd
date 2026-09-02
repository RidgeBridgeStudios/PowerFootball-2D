##
## BoardState
##
## The board's relationship with the human manager: what they expect, how
## satisfied they currently are, what they have been asked for, and how close
## the manager is to being sacked.
##
## Confidence is deliberately slow-moving and asymmetric — it falls faster than
## it rises, and a run of results moves it far more than any single match. The
## sack trigger is not a bare threshold either: it requires sustained low
## confidence across a defined window, so one bad afternoon never ends a job.
##
## Depends on: CareerDate.
## Exposes: the fields below, make_for_club(), apply_result(), confidence_label(),
##          expectation_label(), should_sack(), file_request(), resolve_request().
##

class_name BoardState
extends Resource

## What the board expects by season's end, set at hire from club reputation.
enum Expectation {
	AVOID_RELEGATION = 0,
	LOWER_MIDTABLE = 1,
	MIDTABLE = 2,
	UPPER_MIDTABLE = 3,
	QUALIFY_CONTINENTAL = 4,
	CHALLENGE_TITLE = 5,
	WIN_TITLE = 6,
}

const EXPECTATION_NAMES: Array[String] = [
	"Avoid Relegation", "Finish in the Bottom Half", "Achieve a Mid-Table Finish",
	"Finish in the Top Half", "Qualify for Continental Football",
	"Challenge for the Title", "Win the League",
]

## Target finishing position as a FRACTION of the table, per expectation.
const EXPECTATION_TARGET_FRACTION: Array[float] = [0.90, 0.75, 0.55, 0.42, 0.28, 0.15, 0.06]

enum RequestKind {
	TRANSFER_BUDGET = 0,
	WAGE_BUDGET = 1,
	TRAINING_FACILITIES = 2,
	YOUTH_FACILITIES = 3,
	STADIUM_EXPANSION = 4,
	SCOUTING_NETWORK = 5,
	NEW_STAFF = 6,
}

const REQUEST_NAMES: Array[String] = [
	"Increase Transfer Budget", "Increase Wage Budget", "Upgrade Training Facilities",
	"Upgrade Youth Facilities", "Expand the Stadium", "Expand the Scouting Network",
	"Recruit Additional Staff",
]

## Confidence below this, sustained for SACK_GRACE_MATCHES, ends the job.
const SACK_THRESHOLD: float = 0.22
const SACK_GRACE_MATCHES: int = 5
## Confidence gains are damped relative to losses — see apply_result().
const CONFIDENCE_GAIN_SCALE: float = 0.65

@export var club_name: String = ""
@export var expectation: Expectation = Expectation.MIDTABLE
@export_range(0.0, 1.0) var confidence: float = 0.65
## Board's read of how the season is actually tracking, 0..1, recomputed from
## league position each matchday. Shown next to confidence so the manager can
## see expectation vs trajectory separately, FM-style.
@export_range(0.0, 1.0) var trajectory: float = 0.5
## Consecutive matchdays confidence has sat below SACK_THRESHOLD.
@export var matches_below_threshold: int = 0
@export var patience_notes: Array[String] = []

## Facility levels, 1 (dilapidated) to 5 (state of the art). Feed the training
## and youth systems as multipliers.
@export_range(1, 5) var training_facilities: int = 3
@export_range(1, 5) var youth_facilities: int = 3
@export_range(1, 5) var scouting_range: int = 2
@export var stadium_capacity: int = 24000

## Requests the manager has filed: [{kind, filed_iso, status, response}]
## status: "pending" | "approved" | "partial" | "rejected"
@export var pending_requests: Array[Dictionary] = []
## Requests already answered, newest last.
@export var request_history: Array[Dictionary] = []
## Board refuses a second request of the same kind inside this many days.
@export var request_cooldown_days: int = 60
@export var takeover_pending: bool = false
@export var owner_name: String = "The Board"


static func make_for_club(club: TeamData, capacity: int) -> BoardState:
	var b := BoardState.new()
	b.club_name = club.team_name
	b.stadium_capacity = capacity
	b.confidence = 0.65
	b.expectation = expectation_from_reputation(club.reputation)
	# Facilities track club stature — a Continental Giant does not train on a
	# public park.
	var facility_level: int = clampi(int(round(club.reputation * 5.0)) + 1, 1, 5)
	b.training_facilities = facility_level
	b.youth_facilities = clampi(facility_level - 1, 1, 5)
	b.scouting_range = clampi(facility_level - 1, 1, 5)
	return b


static func expectation_from_reputation(reputation: float) -> Expectation:
	if reputation >= 0.88:
		return Expectation.WIN_TITLE
	if reputation >= 0.76:
		return Expectation.CHALLENGE_TITLE
	if reputation >= 0.64:
		return Expectation.QUALIFY_CONTINENTAL
	if reputation >= 0.50:
		return Expectation.UPPER_MIDTABLE
	if reputation >= 0.36:
		return Expectation.MIDTABLE
	if reputation >= 0.22:
		return Expectation.LOWER_MIDTABLE
	return Expectation.AVOID_RELEGATION


func expectation_label() -> String:
	return EXPECTATION_NAMES[clampi(int(expectation), 0, EXPECTATION_NAMES.size() - 1)]


func target_position(team_count: int) -> int:
	var frac: float = EXPECTATION_TARGET_FRACTION[clampi(int(expectation), 0, EXPECTATION_TARGET_FRACTION.size() - 1)]
	return clampi(int(round(frac * float(team_count))), 1, maxi(team_count, 1))


## Recomputes the board's read of the season and nudges confidence toward it.
## Called once per matchday after the table updates.
func apply_result(league_position: int, team_count: int, won: bool, drew: bool, was_upset: bool) -> void:
	var target: int = target_position(team_count)
	# +1.0 when comfortably beating the target, -1.0 when far below it.
	var position_gap: float = float(target - league_position) / maxf(float(team_count) * 0.5, 1.0)
	trajectory = clampf(0.5 + position_gap * 0.5, 0.0, 1.0)

	var delta: float = position_gap * 0.06
	if won:
		delta += 0.035
	elif drew:
		delta += 0.005
	else:
		delta -= 0.045
	if was_upset:
		# Beating a much better side buys real goodwill; losing to a much worse
		# one costs more than a normal defeat.
		delta += 0.05 if won else -0.05

	# Asymmetry: good news is discounted, bad news lands in full.
	if delta > 0.0:
		delta *= CONFIDENCE_GAIN_SCALE
	confidence = clampf(confidence + delta, 0.0, 1.0)

	if confidence < SACK_THRESHOLD:
		matches_below_threshold += 1
	else:
		matches_below_threshold = 0


func should_sack() -> bool:
	return matches_below_threshold >= SACK_GRACE_MATCHES


func confidence_label() -> String:
	if confidence >= 0.85:
		return "Untouchable"
	if confidence >= 0.68:
		return "Secure"
	if confidence >= 0.50:
		return "Satisfied"
	if confidence >= 0.34:
		return "Uncertain"
	if confidence >= SACK_THRESHOLD:
		return "Under Pressure"
	return "Sack Race"


func has_recent_request(kind: RequestKind, today: CareerDate) -> bool:
	for r: Dictionary in request_history:
		if int(r.get("kind", -1)) != int(kind):
			continue
		var filed: CareerDate = CareerDate.from_iso(String(r.get("filed_iso", "")))
		if filed.days_until(today) < request_cooldown_days:
			return true
	for r2: Dictionary in pending_requests:
		if int(r2.get("kind", -1)) == int(kind):
			return true
	return false


func file_request(kind: RequestKind, amount: int, today: CareerDate) -> void:
	pending_requests.append({
		"kind": int(kind),
		"amount": amount,
		"filed_iso": today.to_iso() if today != null else "",
		"status": "pending",
		"response": "",
	})


## Board verdict on one filed request. Confidence and the club's finances both
## weigh in: a board that rates the manager grants more, and a broke club
## grants less regardless of how well the manager is doing.
func evaluate_request(request: Dictionary, affordability: float, rng: RandomNumberGenerator) -> Dictionary:
	var favour: float = confidence * 0.55 + trajectory * 0.25 + clampf(affordability, 0.0, 1.0) * 0.20
	var roll: float = rng.randf()
	var outcome: String = "rejected"
	var granted_fraction: float = 0.0

	if roll < favour - 0.25:
		outcome = "approved"
		granted_fraction = 1.0
	elif roll < favour + 0.15:
		outcome = "partial"
		granted_fraction = lerpf(0.25, 0.65, favour)

	request["status"] = outcome
	request["granted_fraction"] = granted_fraction
	return request


func resolve_request(index: int, verdict: Dictionary) -> void:
	if index < 0 or index >= pending_requests.size():
		return
	pending_requests.remove_at(index)
	request_history.append(verdict)
	while request_history.size() > 40:
		request_history.remove_at(0)


func facility_multiplier(level: int) -> float:
	# Level 1 = 0.72x, level 3 = 1.0x, level 5 = 1.28x.
	return 0.72 + float(clampi(level, 1, 5) - 1) * 0.14
