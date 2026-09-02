##
## ScoutingNetwork
##
## Assigns scouts, advances their reports, and surfaces what they find.
##
## Scouting is uncertainty reduction (see ScoutReport): a target starts as a
## wide band around its true ability and narrows as a scout watches it. This
## class owns WHO is watching WHAT and how fast, and the discovery process that
## puts new names in front of the manager in the first place.
##
## Depends on: ScoutReport, StaffData, TeamData, PlayerData, PlayerCareerState,
##             CareerDate, CareerSaveData.
## Exposes: available_scouts(), assign_scout(), advance_reports(),
##          discover_targets(), ensure_report(), opposition_report().
##

class_name ScoutingNetwork
extends RefCounted

## Reports one scout can meaningfully progress at once. Spreading a scout
## thinner than this slows every report proportionally.
const REPORTS_PER_SCOUT: int = 4
## Chance per scouting day that an assigned scout turns up a NEW name.
const DISCOVERY_CHANCE: float = 0.06
## A discovered player this young with this much headroom is a "wonderkid" and
## is reported with a flourish.
const WONDERKID_MAX_AGE: int = 20
const WONDERKID_MIN_HEADROOM: int = 18


static func available_scouts(team: TeamData) -> Array[StaffData]:
	var out: Array[StaffData] = []
	if team == null:
		return out
	for s: StaffData in team.staff:
		if s.role.nocasecmp_to("Chief Scout") == 0 or s.role.to_lower().contains("scout"):
			out.append(s)
	return out


## Judging ability of the scout assigned to a report, or 0 if unassigned.
static func scout_quality(team: TeamData, scout_name: String) -> float:
	if team == null or scout_name == "":
		return 0.0
	for s: StaffData in team.staff:
		if s.staff_name == scout_name:
			return s.judging_ability
	return 0.0


## How many reports a given scout currently carries.
static func caseload(career: CareerSaveData, scout_name: String) -> int:
	var n: int = 0
	for r: ScoutReport in career.scout_reports:
		if r.assigned_scout_name == scout_name and r.stage <= ScoutReport.Stage.SCOUTED:
			n += 1
	return n


static func assign_scout(report: ScoutReport, scout_name: String) -> void:
	if report != null:
		report.assigned_scout_name = scout_name


## One day of scouting across every active report. A scout carrying more than
## REPORTS_PER_SCOUT targets makes proportionally slower progress on each.
static func advance_reports(career: CareerSaveData, user_team: TeamData, today: CareerDate) -> Array[ScoutReport]:
	var newly_ready: Array[ScoutReport] = []
	for r: ScoutReport in career.scout_reports:
		if r.assigned_scout_name == "" or r.stage > ScoutReport.Stage.SCOUTED:
			continue
		var quality: float = scout_quality(user_team, r.assigned_scout_name)
		if quality <= 0.0:
			continue
		var load: int = caseload(career, r.assigned_scout_name)
		var spread: float = clampf(float(REPORTS_PER_SCOUT) / maxf(float(load), 1.0), 0.25, 1.0)
		var was_ready: bool = r.is_bid_ready()
		r.advance(quality * spread, today)
		if not was_ready and r.is_bid_ready():
			newly_ready.append(r)
	return newly_ready


## Ensures a report exists for a target, creating a blank one if not. The bias
## is drawn once, here, so a given club's read of a player stays consistent.
static func ensure_report(
	career: CareerSaveData,
	target_team_index: int,
	target_squad_index: int,
	data: PlayerData,
	state: PlayerCareerState,
	club_name: String,
	today: CareerDate,
	rng: RandomNumberGenerator
) -> ScoutReport:
	var key: int = target_team_index * 1000 + target_squad_index
	var existing: ScoutReport = career.report_for(key)
	if existing != null:
		return existing

	var report: ScoutReport = ScoutReport.make(
		target_team_index,
		target_squad_index,
		data.player_name,
		club_name,
		data.position_role,
		data.calculate_overall_rating(),
		state.potential_ability if state != null else data.calculate_overall_rating(),
		today,
		rng.randf_range(-1.0, 1.0)
	)
	career.scout_reports.append(report)
	return report


## Assigned scouts occasionally turn up players nobody asked them to watch.
## Returns any newly discovered reports, flagged as wonderkids where they are.
static func discover_targets(
	career: CareerSaveData,
	user_team: TeamData,
	teams: Array[TeamData],
	today: CareerDate,
	rng: RandomNumberGenerator
) -> Array[ScoutReport]:
	var found: Array[ScoutReport] = []
	var scouts: Array[StaffData] = available_scouts(user_team)
	if scouts.is_empty() or teams.is_empty():
		return found

	for scout: StaffData in scouts:
		# A better scout finds more, and finds it sooner.
		if rng.randf() > DISCOVERY_CHANCE * (0.5 + scout.judging_ability):
			continue

		# Pick a club that is not the user's, then a player from it.
		var attempts: int = 0
		while attempts < 6:
			attempts += 1
			var team_index: int = rng.randi_range(0, teams.size() - 1)
			if team_index == career.user_team_index:
				continue
			var team: TeamData = teams[team_index]
			if team == null or team.squad.is_empty():
				continue
			var squad_index: int = rng.randi_range(0, team.squad.size() - 1)
			var key: int = team_index * 1000 + squad_index
			if career.report_for(key) != null:
				continue

			var data: PlayerData = team.squad[squad_index]
			var state: PlayerCareerState = career.state_for(key)
			var report: ScoutReport = ensure_report(
				career, team_index, squad_index, data, state, team.team_name, today, rng
			)
			# A discovery arrives with a head start — the scout has already
			# seen enough to bother mentioning them.
			report.assigned_scout_name = scout.staff_name
			report.knowledge = clampf(0.18 + scout.judging_ability * 0.15, 0.0, 0.6)
			report.advance(scout.judging_ability, today)
			found.append(report)
			break
	return found


static func is_wonderkid(report: ScoutReport, age: int) -> bool:
	if report == null or age > WONDERKID_MAX_AGE:
		return false
	return (report.true_potential - report.true_overall) >= WONDERKID_MIN_HEADROOM


## Pre-match dossier on an upcoming opponent. Reads the live league state
## rather than any stored scouting, because a manager can always watch the
## next opponent — the quality of the READ is what varies with staff.
static func opposition_report(
	opponent: TeamData,
	opponent_manager: ManagerData,
	table_row: LeagueTableRow,
	analyst_quality: float
) -> Dictionary:
	var key_players: Array[String] = []
	var threats: Array[PlayerData] = opponent.squad.duplicate()
	threats.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		return a.calculate_overall_rating() > b.calculate_overall_rating()
	)
	var shown: int = 3 if analyst_quality < 0.6 else 5
	for i: int in range(mini(shown, threats.size())):
		var p: PlayerData = threats[i]
		key_players.append("%s (%s, %d)" % [p.player_name, p.position_role, p.calculate_overall_rating()])

	var shape: String = opponent.formation_override
	if shape == "" and opponent_manager != null:
		shape = opponent_manager.preferred_formation

	# A weak analyst gives a vaguer tactical read.
	var style: String = "Unclear"
	if opponent_manager != null:
		if analyst_quality >= 0.5:
			if opponent_manager.pressing_intensity >= 0.7:
				style = "Aggressive high press — expect to be hurried on the ball"
			elif opponent_manager.tempo >= 0.7:
				style = "Direct and vertical — they will attack the space in behind"
			elif opponent_manager.defensive_line <= 0.35:
				style = "Deep, compact block — they will invite pressure and counter"
			else:
				style = "Balanced, patient build-up"
		else:
			style = "Our analyst could not form a clear picture"

	var set_piece_threat: float = 0.0
	for p2: PlayerData in opponent.squad:
		if p2.has_trait(1024): # DeadBallSpecialist
			set_piece_threat = maxf(set_piece_threat, 0.8)
		set_piece_threat = maxf(set_piece_threat, (p2.mass - 70.0) / 40.0 * 0.5)

	return {
		"formation": shape,
		"style": style,
		"key_players": key_players,
		"form": table_row.form_string(5) if table_row != null else "",
		"position": 0,
		"set_piece_threat": clampf(set_piece_threat, 0.0, 1.0),
		"confidence": clampf(analyst_quality, 0.0, 1.0),
	}
