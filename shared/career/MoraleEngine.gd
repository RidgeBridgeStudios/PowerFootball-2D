##
## MoraleEngine
##
## Owns player morale between matches.
##
## DRIVES morale from the things that actually move a footballer: playing
## time against the status they were promised, results, personal form,
## contract satisfaction, how the manager treats them, and the dressing
## room around them. Each driver is a separate signed contribution so the
## UI can show a player exactly why they are unhappy, FM-style.
##
## Before the manager-only pivot this was also the bridge that wrote career
## morale onto the live 22-player match entities at kickoff (seeding the
## Layer 3 MoodSystem tier and Layer 2 TrustSystem memory). That path went
## with the real-time match layer; morale now reaches a match only through
## the statistical QuickSimEngine ratings.
##
## The seeding maths is calibrated so the DEFAULT authored player (morale 0.70,
## form 6.5) lands exactly on NORMAL — see seed_mood_value().
##
## Depends on: PlayerData, PlayerCareerState, CareerSaveData, RelationshipData,
##             TeamData.
## Exposes: seed_mood_value(), evaluate_drivers(), daily_drift(),
##          apply_result_reaction(), describe_drivers().
##

class_name MoraleEngine
extends RefCounted

## The authored neutral baseline. A player sitting exactly here maps to a
## 0.5 mood scalar — dead centre of the normal band.
const NEUTRAL_MORALE: float = 0.70
const NEUTRAL_FORM: float = 6.5

## Seeding coefficients. The morale slope is ASYMMETRIC on purpose: SLUMP is
## a heavy penalty (-18% speed, +25% accel time, composure -0.20, doubled kick
## scatter), so it has to be reserved for genuine unhappiness rather than mere
## restlessness. A symmetric 0.70 slope dropped a merely "Restless" player
## (morale 0.45) to 0.346 and into SLUMP; 0.56 on the downside keeps the
## boundary where the morale_label() bands say it should be.
##
## Verified boundaries at form 6.5: SLUMP below morale 0.397, STREAK at or
## above morale 0.943. Calibration anchors:
##   morale 0.70 / form 6.5  -> 0.500  (NORMAL — the authored default)
##   morale 0.45 / form 6.2  -> 0.346  (NORMAL — "Restless", flat but not slumping)
##   morale 0.35 / form 6.5  -> 0.304  (SLUMP  — "Unhappy", threshold 0.33)
##   morale 0.30 / form 6.5  -> 0.276  (SLUMP  — prolonged unhappy career state)
##   morale 0.95 / form 6.5  -> 0.675  (STREAK — riding a contract renewal)
const MORALE_TO_MOOD_DOWN: float = 0.56
const MORALE_TO_MOOD_UP: float = 0.70
const FORM_TO_MOOD: float = 0.045
## Sharpness only trims the edges — an undercooked player is flat, not slumping.
const SHARPNESS_TO_MOOD: float = 0.08

## Per-driver weights. These sum to the total swing one evaluation can apply.
const W_PLAYING_TIME: float = 0.34
const W_RESULTS: float = 0.22
const W_FORM: float = 0.14
const W_CONTRACT: float = 0.12
const W_MANAGER: float = 0.10
const W_DRESSING_ROOM: float = 0.08

## Morale moves toward its computed target at this rate per evaluation, so a
## single bad week never flips a happy player into revolt.
const MORALE_LERP_RATE: float = 0.22


## --- Morale-to-mood seeding -----------------------------------------------------

## Maps persistent career state onto the 0..1 mood scalar the ratings model uses.
## Pure and side-effect free so it can be unit-reasoned about and previewed in
## the UI.
static func seed_mood_value(morale: float, form: float, sharpness: float) -> float:
	var mood: float = 0.5
	var morale_delta: float = clampf(morale, 0.0, 1.0) - NEUTRAL_MORALE
	var slope: float = MORALE_TO_MOOD_UP if morale_delta >= 0.0 else MORALE_TO_MOOD_DOWN
	mood += morale_delta * slope
	mood += (clampf(form, 0.0, 10.0) - NEUTRAL_FORM) * FORM_TO_MOOD
	mood += (clampf(sharpness, 0.0, 1.0) - 0.6) * SHARPNESS_TO_MOOD
	return clampf(mood, 0.0, 1.0)


## --- Morale drivers -------------------------------------------------------------

## One named contribution to a player's morale target.
class Driver:
	var label: String = ""
	## Signed, roughly -1..1 before weighting.
	var value: float = 0.0
	var weight: float = 0.0
	var detail: String = ""

	func contribution() -> float:
		return value * weight


## Evaluates every morale driver for one player and returns them individually,
## so the squad screen can render "why is he unhappy" rather than a bare number.
static func evaluate_drivers(
	data: PlayerData,
	state: PlayerCareerState,
	team_matches_played: int,
	team_form_factor: float,
	squad_harmony: float,
	median_squad_wage: int
) -> Array[Driver]:
	var drivers: Array[Driver] = []
	if data == null or state == null:
		return drivers

	# 1. Playing time against the status they were promised.
	var expected: float = state.contract.expected_minutes_share() if state.contract != null else 0.5
	var actual: float = state.minutes_share(team_matches_played)
	var pt := Driver.new()
	pt.label = "Playing Time"
	pt.weight = W_PLAYING_TIME
	if team_matches_played <= 0:
		pt.value = 0.0
		pt.detail = "Season has not started"
	else:
		# Normalised shortfall/surplus against the promise. Falling short hurts
		# more than exceeding it helps — a squad player given extra minutes is
		# pleased; a star left out is furious.
		var gap: float = actual - expected
		pt.value = clampf(gap / maxf(expected, 0.15), -1.0, 1.0)
		if pt.value < 0.0:
			pt.value *= 1.5
			pt.value = maxf(pt.value, -1.0)
		pt.detail = "%d%% of minutes, promised %s" % [
			int(round(actual * 100.0)),
			state.contract.status_name() if state.contract != null else "Regular Starter"
		]
	drivers.append(pt)

	# 2. How the team is doing.
	var res := Driver.new()
	res.label = "Team Results"
	res.weight = W_RESULTS
	res.value = clampf((team_form_factor - 0.45) * 2.4, -1.0, 1.0)
	res.detail = "Recent form %d%%" % int(round(team_form_factor * 100.0))
	drivers.append(res)

	# 3. Their own form.
	var frm := Driver.new()
	frm.label = "Personal Form"
	frm.weight = W_FORM
	frm.value = clampf((data.form - NEUTRAL_FORM) / 2.0, -1.0, 1.0)
	frm.detail = "Average rating %.2f" % data.form
	drivers.append(frm)

	# 4. Contract satisfaction — wage relative to the squad, and how much time
	#    is left. An ambitious player on an expiring deal agitates.
	var con := Driver.new()
	con.label = "Contract"
	con.weight = W_CONTRACT
	var wage_ratio: float = 1.0
	if median_squad_wage > 0 and state.contract != null:
		wage_ratio = float(state.contract.wage_weekly) / float(median_squad_wage)
	# A player worth more than the squad average expects to be paid more.
	var deserved: float = 0.6 + data.player_reputation * 1.6
	var wage_gap: float = clampf((wage_ratio - deserved) / maxf(deserved, 0.5), -1.0, 1.0)
	con.value = wage_gap
	if state.wants_new_contract:
		con.value = minf(con.value - 0.4, 1.0)
	con.detail = "Earning %.2fx squad median" % wage_ratio
	drivers.append(con)

	# 5. The manager themselves.
	var mgr := Driver.new()
	mgr.label = "Manager Relationship"
	mgr.weight = W_MANAGER
	mgr.value = clampf((state.manager_trust - 0.5) * 2.0, -1.0, 1.0)
	mgr.detail = _trust_label(state.manager_trust)
	drivers.append(mgr)

	# 6. The dressing room around them — their own feuds plus overall harmony.
	var room := Driver.new()
	room.label = "Dressing Room"
	room.weight = W_DRESSING_ROOM
	var worst_rivalry: float = 0.0
	for other_key: int in state.relationships:
		var rel: RelationshipData = state.relationships[other_key] as RelationshipData
		if rel != null:
			worst_rivalry = maxf(worst_rivalry, rel.rivalry_score)
	room.value = clampf((squad_harmony - 0.5) * 1.6 - worst_rivalry * 1.2, -1.0, 1.0)
	# CaptainMaterial (64), VeteranLeader (512) and Talisman (16) players are
	# personally more resilient to a rocky dressing room, the same way
	# PressureImmune (4) blunts the SLUMP tier above — a leader is who a bad
	# dressing room affects least, not who fixes it for everyone else.
	if room.value < 0.0 and (data.has_trait(64) or data.has_trait(512) or data.has_trait(16)):
		room.value *= 0.5
	room.detail = "Feud in the squad" if worst_rivalry >= 0.5 else "Settled"
	drivers.append(room)

	return drivers


## Collapses the drivers into a morale target and eases the player toward it.
## Returns the new morale so the caller can detect a threshold crossing.
static func apply_drivers(data: PlayerData, drivers: Array[Driver]) -> float:
	if data == null:
		return 0.5
	var sum: float = 0.0
	for d: Driver in drivers:
		sum += d.contribution()
	# Drivers are signed around zero; morale is 0..1 centred on NEUTRAL_MORALE.
	var target: float = clampf(NEUTRAL_MORALE + sum * 0.55, 0.05, 1.0)

	# Temperament decides how fast a player swings. A volatile character
	# reaches their target in a fraction of the time a level head does.
	var responsiveness: float = lerpf(1.6, 0.6, clampf(data.temperament, 0.0, 1.0))
	data.morale = clampf(
		lerpf(data.morale, target, MORALE_LERP_RATE * responsiveness), 0.0, 1.0
	)
	return data.morale


## Immediate reaction to one result, applied on matchday before the slower
## weekly driver pass. Keeps a thrashing feeling like a thrashing.
static func apply_result_reaction(data: PlayerData, played: bool, goal_diff: int, rating: float) -> void:
	if data == null:
		return
	var delta: float = 0.0
	if goal_diff > 0:
		delta += 0.035 + minf(float(goal_diff), 4.0) * 0.008
	elif goal_diff < 0:
		delta -= 0.045 + minf(float(-goal_diff), 4.0) * 0.010
	else:
		delta += 0.002

	if played:
		# Personal performance colours how a player takes the team result.
		delta += (rating - 6.5) * 0.020
	else:
		# Being left out of a win still stings a little.
		delta -= 0.012

	# Determination pulls a player back up after a bad day rather than down.
	if delta < 0.0:
		delta *= lerpf(1.3, 0.55, clampf(data.determination, 0.0, 1.0))

	# PrideGlory (256) players simply feel results harder, in both directions.
	if data.has_trait(256):
		delta *= 1.35

	data.morale = clampf(data.morale + delta, 0.0, 1.0)


## --- Reputation ------------------------------------------------------------------

## A standout or poor match rating nudges player_reputation, so fame is
## actually earned over a career rather than sitting fixed at its authored
## seed. Deliberately small per match — reputation is meant to move over
## seasons, not swing on one performance — and damped for older players,
## whose reputation is already largely settled.
const REPUTATION_GAIN_EXCELLENT: float = 0.006
const REPUTATION_GAIN_GOOD: float = 0.0025
const REPUTATION_LOSS_POOR: float = -0.004


static func apply_reputation_drift(data: PlayerData, rating: float, age: int) -> void:
	if data == null or rating <= 0.0:
		return
	var delta: float = 0.0
	if rating >= 8.0:
		delta = REPUTATION_GAIN_EXCELLENT
	elif rating >= 7.0:
		delta = REPUTATION_GAIN_GOOD
	elif rating <= 4.5:
		delta = REPUTATION_LOSS_POOR
	if delta == 0.0:
		return
	# A young player's reputation is still being written; a veteran's rarely
	# moves much on one match.
	delta *= lerpf(1.4, 0.7, clampf(float(age - 18) / 15.0, 0.0, 1.0))
	data.player_reputation = clampf(data.player_reputation + delta, 0.02, 0.99)


## Slow pull back toward the neutral baseline on days when nothing happens, so
## an extreme morale state decays instead of persisting all season untouched.
static func daily_drift(data: PlayerData) -> void:
	if data == null:
		return
	data.morale = move_toward(data.morale, NEUTRAL_MORALE, 0.004)


static func _trust_label(t: float) -> String:
	if t >= 0.78:
		return "Trusts the manager completely"
	if t >= 0.60:
		return "Positive"
	if t >= 0.42:
		return "Neutral"
	if t >= 0.25:
		return "Doubts the manager"
	return "Wants the manager gone"


static func morale_label(morale: float) -> String:
	if morale >= 0.85:
		return "Delighted"
	if morale >= 0.70:
		return "Happy"
	if morale >= 0.55:
		return "Content"
	if morale >= 0.40:
		return "Restless"
	if morale >= 0.25:
		return "Unhappy"
	return "Furious"


static func morale_color(morale: float) -> Color:
	if morale >= 0.70:
		return Color(0.30, 0.82, 0.42)
	if morale >= 0.55:
		return Color(0.72, 0.82, 0.35)
	if morale >= 0.40:
		return Color(0.92, 0.76, 0.30)
	if morale >= 0.25:
		return Color(0.93, 0.55, 0.25)
	return Color(0.90, 0.32, 0.32)


## One-line summary of the single strongest negative driver, for the unhappy
## players list.
static func describe_drivers(drivers: Array[Driver]) -> String:
	var worst: Driver = null
	for d: Driver in drivers:
		if worst == null or d.contribution() < worst.contribution():
			worst = d
	if worst == null or worst.contribution() >= -0.02:
		return "No concerns"
	return "%s — %s" % [worst.label, worst.detail]
