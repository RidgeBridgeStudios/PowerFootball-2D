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
##          apply_result_reaction(), apply_pass_starvation_penalty(),
##          describe_drivers().
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

## Clique detection & social sub-graph dynamics constants (docs/Social Dynamics Simulation Engine Implementation.md)
const CLIQUE_TRUST_THRESHOLD: float = 0.70
const NATIONALITY_AFFINITY_BONUS: float = 0.10
const LANGUAGE_AFFINITY_BONUS: float = 0.05
const SHARED_RESENTMENT_BONUS: float = 0.10
const RESENTMENT_TRUST_CEILING: float = 0.40
const PEER_DIFFUSION_DAMPING: float = 0.35
const MAX_DIFFUSION_STEP: float = 0.08


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


static func apply_substitution_reaction(
	data: PlayerData,
	minute: int,
	goal_diff: int,
	rating: float
) -> void:
	if data == null:
		return
	var delta: float = -0.03
	# Subbed off early (before 60') while game is close stings more
	if minute < 60 and absi(goal_diff) <= 1:
		delta -= 0.04
	# Bad personal performance explains the sub
	if rating < 6.0:
		delta += 0.015
	# PrideGlory (256): substitution hit is doubled
	if data.has_trait(256):
		delta *= 2.0

	data.morale = clampf(data.morale + delta, 0.0, 1.0)


## --- Pass Starvation / Ego Catering ----------------------------------------------

## Ego / catering pass-starvation morale penalty (docs/SOCIAL_SIMULATION_ARCHITECTURE.md §4.3).
## A star who touches the ball meaningfully below their player_reputation-implied
## expectation sours.
## expected_share = lerp(0.06, 0.14, player_reputation)
## actual_share = touches_player / touches_team
## delta = clampf((actual_share - expected_share) * 1.5, -0.08, 0.04)
## Asymmetric clamp: failing to feed a star hurts harder (-0.08) than overfeeding rewards (+0.04).
static func calculate_pass_starvation_delta(
	player_reputation: float,
	player_touches: int,
	team_touches: int
) -> float:
	if team_touches <= 0:
		return 0.0
	var actual_share: float = float(player_touches) / float(team_touches)
	var expected_share: float = lerpf(0.06, 0.14, clampf(player_reputation, 0.0, 1.0))
	return clampf((actual_share - expected_share) * 1.5, -0.08, 0.04)


static func apply_pass_starvation_penalty(
	data: PlayerData,
	player_touches: int,
	team_touches: int
) -> float:
	if data == null or team_touches <= 0:
		return 0.0
	# Goalkeepers are shot-stoppers and do not participate in pass-starvation ego dynamics.
	if data.position_role == "GK":
		return 0.0
	var delta: float = calculate_pass_starvation_delta(data.player_reputation, player_touches, team_touches)
	data.morale = clampf(data.morale + delta, 0.0, 1.0)
	return delta


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


## --- Squad Clique & Faction Dynamics -------------------------------------------

## Computes pairwise social affinity between two players in a squad based on mutual trust,
## shared nationality/language (NationDatabase), shared manager resentment, and rivalry friction.
static func calculate_social_affinity(
	p_i: PlayerData,
	state_i: PlayerCareerState,
	p_j: PlayerData,
	state_j: PlayerCareerState,
	key_i: int,
	key_j: int
) -> float:
	var t_ij: float = 0.5
	var r_ij: float = 0.0
	if state_i != null and state_i.relationships.has(key_j):
		var rel_ij: RelationshipData = state_i.relationships[key_j] as RelationshipData
		if rel_ij != null:
			t_ij = rel_ij.trust
			r_ij = rel_ij.rivalry_score

	var t_ji: float = 0.5
	var r_ji: float = 0.0
	if state_j != null and state_j.relationships.has(key_i):
		var rel_ji: RelationshipData = state_j.relationships[key_i] as RelationshipData
		if rel_ji != null:
			t_ji = rel_ji.trust
			r_ji = rel_ji.rivalry_score

	var base_trust: float = minf(t_ij, t_ji)
	var max_rivalry: float = maxf(r_ij, r_ji)

	# Shared nationality or language bonus from NationDatabase
	var cultural_bonus: float = 0.0
	if p_i != null and p_j != null:
		if NationDatabase.share_nationality(p_i.nationality, p_j.nationality):
			cultural_bonus = NATIONALITY_AFFINITY_BONUS
		elif NationDatabase.share_language(p_i.nationality, p_j.nationality):
			cultural_bonus = LANGUAGE_AFFINITY_BONUS

	# Shared manager resentment: disaffected players bonding over low manager trust
	var resentment_bonus: float = 0.0
	if state_i != null and state_j != null:
		if state_i.manager_trust < RESENTMENT_TRUST_CEILING and state_j.manager_trust < RESENTMENT_TRUST_CEILING:
			var res_i: float = 1.0 - state_i.manager_trust
			var res_j: float = 1.0 - state_j.manager_trust
			resentment_bonus = SHARED_RESENTMENT_BONUS * minf(res_i, res_j)

	var rivalry_penalty: float = max_rivalry * 0.5
	return clampf(base_trust + cultural_bonus + resentment_bonus - rivalry_penalty, 0.0, 1.0)


## Detects maximal cohesive cliques (size >= 3) within the squad's social graph
## using 64-bit bitmask Bron-Kerbosch with pivoting. Zero heap allocations during recursion.
static func detect_squad_cliques(
	team: TeamData,
	career: CareerSaveData,
	team_index: int = -1,
	threshold: float = CLIQUE_TRUST_THRESHOLD
) -> Array[PackedInt32Array]:
	var results: Array[PackedInt32Array] = []
	if team == null or team.squad.is_empty():
		return results

	var n: int = mini(team.squad.size(), 62)
	if n < 3:
		return results

	var t_idx: int = team_index
	if t_idx < 0:
		t_idx = career.user_team_index if career != null else 0

	var keys: PackedInt32Array = PackedInt32Array()
	keys.resize(n)
	var states: Array[PlayerCareerState] = []
	states.resize(n)

	for i in range(n):
		keys[i] = t_idx * 1000 + i
		states[i] = career.state_for_squad(t_idx, i) if career != null else null

	var adj: PackedInt64Array = PackedInt64Array()
	adj.resize(n)
	for i in range(n):
		adj[i] = 0

	for i in range(n):
		var p_i: PlayerData = team.squad[i]
		var st_i: PlayerCareerState = states[i]
		var key_i: int = keys[i]
		for j in range(i + 1, n):
			var p_j: PlayerData = team.squad[j]
			var st_j: PlayerCareerState = states[j]
			var key_j: int = keys[j]
			var affinity: float = calculate_social_affinity(p_i, st_i, p_j, st_j, key_i, key_j)
			if affinity >= threshold:
				adj[i] = adj[i] | (1 << j)
				adj[j] = adj[j] | (1 << i)

	var clique_masks: PackedInt64Array = PackedInt64Array()
	var all_candidates: int = (1 << n) - 1
	_bron_kerbosch_pivot(0, all_candidates, 0, adj, clique_masks)

	for idx in range(clique_masks.size()):
		var mask: int = clique_masks[idx]
		var clique_keys: PackedInt32Array = PackedInt32Array()
		for bit in range(n):
			if (mask & (1 << bit)) != 0:
				clique_keys.append(keys[bit])
		results.append(clique_keys)

	return results


static func _bron_kerbosch_pivot(
	r_mask: int,
	p_mask: int,
	x_mask: int,
	adj: PackedInt64Array,
	cliques: PackedInt64Array
) -> void:
	if p_mask == 0 and x_mask == 0:
		if _popcount(r_mask) >= 3:
			cliques.append(r_mask)
		return

	var p_or_x: int = p_mask | x_mask
	var max_cnt: int = -1
	var pivot_u: int = -1
	var temp: int = p_or_x
	while temp > 0:
		var u: int = _lowest_set_bit_index(temp)
		var bit_u: int = 1 << u
		var neighbors_in_p: int = _popcount(p_mask & adj[u])
		if neighbors_in_p > max_cnt:
			max_cnt = neighbors_in_p
			pivot_u = u
		temp &= ~bit_u

	var candidates: int = p_mask & (~adj[pivot_u] if pivot_u >= 0 else -1)
	while candidates > 0:
		var v: int = _lowest_set_bit_index(candidates)
		var bit_v: int = 1 << v
		_bron_kerbosch_pivot(
			r_mask | bit_v,
			p_mask & adj[v],
			x_mask & adj[v],
			adj,
			cliques
		)
		p_mask &= ~bit_v
		x_mask |= bit_v
		candidates &= ~bit_v


static func _popcount(mask: int) -> int:
	var count: int = 0
	var m: int = mask
	while m > 0:
		m &= m - 1
		count += 1
	return count


static func _lowest_set_bit_index(mask: int) -> int:
	if mask <= 0:
		return -1
	var lsb: int = mask & -mask
	var idx: int = 0
	if (lsb >> 32) != 0:
		lsb >>= 32
		idx += 32
	if (lsb & 0xFFFF0000) != 0:
		lsb >>= 16
		idx += 16
	if (lsb & 0x0000FF00) != 0:
		lsb >>= 8
		idx += 8
	if (lsb & 0x000000F0) != 0:
		lsb >>= 4
		idx += 4
	if (lsb & 0x0000000C) != 0:
		lsb >>= 2
		idx += 2
	if (lsb & 0x00000002) != 0:
		idx += 1
	return idx


## Determines the faction leader of a clique based on leadership traits,
## reputation, age, and form standing.
static func get_clique_leader(
	team: TeamData,
	career: CareerSaveData,
	clique_player_keys: PackedInt32Array
) -> int:
	if clique_player_keys.is_empty():
		return -1

	var best_key: int = clique_player_keys[0]
	var best_score: float = -999.0

	for k in range(clique_player_keys.size()):
		var p_key: int = clique_player_keys[k]
		var squad_idx: int = p_key % 1000
		if squad_idx < 0 or squad_idx >= team.squad.size():
			continue
		var p: PlayerData = team.squad[squad_idx]
		if p == null:
			continue

		var score: float = p.player_reputation * 0.50
		# Trait weights: CaptainMaterial (64), VeteranLeader (512), Talisman (16), Vocal (256)
		if p.has_trait(64):
			score += 0.35
		if p.has_trait(512):
			score += 0.25
		if p.has_trait(16):
			score += 0.15
		if p.has_trait(256):
			score += 0.10
		if p.get_age() >= 28:
			score += 0.10
		score += (p.form - 6.0) * 0.05

		if score > best_score:
			best_score = score
			best_key = p_key

	return best_key


## Propagates faction leader morale swings to clique members via peer diffusion with numerical damping.
## Strictly non-expansive, bounded within [0.0, 1.0], preventing runaway feedback loops.
static func propagate_clique_morale(
	team: TeamData,
	career: CareerSaveData,
	team_index: int = -1,
	damping: float = PEER_DIFFUSION_DAMPING
) -> void:
	if team == null or team.squad.is_empty():
		return

	var t_idx: int = team_index
	if t_idx < 0:
		t_idx = career.user_team_index if career != null else 0

	var cliques: Array[PackedInt32Array] = detect_squad_cliques(team, career, t_idx)
	if cliques.is_empty():
		return

	var squad_size: int = team.squad.size()

	for clique: PackedInt32Array in cliques:
		if clique.size() < 2:
			continue

		var leader_key: int = get_clique_leader(team, career, clique)
		var leader_idx: int = leader_key % 1000
		if leader_idx < 0 or leader_idx >= squad_size:
			continue
		var leader_p: PlayerData = team.squad[leader_idx]
		if leader_p == null:
			continue
		var leader_state: PlayerCareerState = career.state_for_squad(t_idx, leader_idx) if career != null else null
		var leader_morale: float = leader_p.morale

		var member_deltas: PackedFloat32Array = PackedFloat32Array()
		member_deltas.resize(clique.size())
		var sum_peer_morale: float = 0.0
		var peer_count: int = 0

		for c_idx in range(clique.size()):
			var eval_key: int = clique[c_idx]
			if eval_key == leader_key:
				member_deltas[c_idx] = 0.0
				continue
			var eval_sq_idx: int = eval_key % 1000
			if eval_sq_idx < 0 or eval_sq_idx >= squad_size:
				member_deltas[c_idx] = 0.0
				continue
			var eval_p: PlayerData = team.squad[eval_sq_idx]
			if eval_p == null:
				member_deltas[c_idx] = 0.0
				continue

			var st: PlayerCareerState = career.state_for_squad(t_idx, eval_sq_idx) if career != null else null
			var affinity: float = calculate_social_affinity(eval_p, st, leader_p, leader_state, eval_key, leader_key)
			var raw_gap: float = leader_morale - eval_p.morale

			var susceptibility: float = 1.0
			# Traits altering susceptibility: PressureImmune (4), LoneWolf (1024), Volatile (2048)
			if eval_p.has_trait(4) or eval_p.has_trait(1024):
				susceptibility *= 0.50
			elif eval_p.has_trait(2048):
				susceptibility *= 1.25

			var step: float = clampf(damping * affinity * raw_gap * susceptibility, -MAX_DIFFUSION_STEP, MAX_DIFFUSION_STEP)
			member_deltas[c_idx] = step
			sum_peer_morale += eval_p.morale
			peer_count += 1

		# Apply member updates
		for c_idx in range(clique.size()):
			var apply_key: int = clique[c_idx]
			if apply_key == leader_key:
				continue
			var apply_sq_idx: int = apply_key % 1000
			if apply_sq_idx >= 0 and apply_sq_idx < squad_size:
				var apply_p: PlayerData = team.squad[apply_sq_idx]
				if apply_p != null:
					apply_p.morale = clampf(apply_p.morale + member_deltas[c_idx], 0.0, 1.0)

		# Leader experiences heavily damped reciprocal feedback from clique consensus
		if peer_count > 0:
			var avg_peer_morale: float = sum_peer_morale / float(peer_count)
			var leader_feedback_step: float = clampf(
				0.10 * damping * (avg_peer_morale - leader_p.morale),
				-MAX_DIFFUSION_STEP * 0.5,
				MAX_DIFFUSION_STEP * 0.5
			)
			leader_p.morale = clampf(leader_p.morale + leader_feedback_step, 0.0, 1.0)
