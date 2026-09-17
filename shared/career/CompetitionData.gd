##
## CompetitionData
##
## One competition a club is entered in: a league with a table, or a knockout
## cup with a bracket. Owns its own fixture list and its own standings, so a
## season can run several competitions side by side and the calendar simply
## merges their fixtures by date.
##
## Fixture generation uses the circle method (round-robin), which guarantees
## every club plays every other exactly once per half-season with no club
## appearing twice on the same matchday.
##
## Depends on: FixtureData, LeagueTableRow, CareerDate, TeamData.
## Exposes: build_league(), build_cup(), generate_league_fixtures(),
##          draw_cup_round(), record_result(), sorted_table(), position_of(),
##          fixtures_on(), next_fixture_for(), is_complete().
##

class_name CompetitionData
extends Resource

enum Kind { LEAGUE = 0, KNOCKOUT_CUP = 1, CONTINENTAL = 2 }
enum Stage { GROUP_STAGE = 0, KNOCKOUT = 1 }

## Cup round labels, chosen by how many clubs remain.
const ROUND_LABELS: Dictionary = {
	2: "Final",
	4: "Semi-Final",
	8: "Quarter-Final",
	16: "Round of 16",
	32: "Round of 32",
}

@export var competition_name: String = "League"
@export var kind: Kind = Kind.LEAGUE
## Current stage for multi-stage tournaments (group stage vs knockout).
@export var stage: Stage = Stage.KNOCKOUT
## League indices of every participating club.
@export var participant_indices: Array[int] = []
@export var fixtures: Array[FixtureData] = []
@export var table: Array[LeagueTableRow] = []
@export var current_round: int = 1
@export var total_rounds: int = 1
## Clubs still alive in a knockout. Empty for leagues.
@export var remaining_indices: Array[int] = []
@export var winner_index: int = -1
@export var two_legged: bool = false
## Which division/tier this league belongs to (1 = top flight, 2 = second division, etc.).
@export var tier: int = 1
## Group index within the tier (-1 for undivided tiers, 0, 1, 2... for named groups).
@export var group_index: int = -1
## Number of clubs promoted or relegated at season end.
@export var promotion_slots: int = 2
@export var relegation_slots: int = 2
## Which FixtureData.Competition tag fixtures from this competition carry.
@export var fixture_tag: FixtureData.Competition = FixtureData.Competition.LEAGUE
## Multi-stage group structures: Array of Array[int] for team indices per group.
@export var group_teams: Array[Array] = []
## Multi-stage group standings: Array of Array[LeagueTableRow] per group.
@export var group_tables: Array[Array] = []
@export var group_stage_complete: bool = false


static func build_league(
	p_name: String,
	team_indices: Array[int],
	team_names: Array[String],
	p_tier: int = 1,
	p_group_index: int = -1,
	p_promotion_slots: int = 2,
	p_relegation_slots: int = 2
) -> CompetitionData:
	var c := CompetitionData.new()
	c.competition_name = p_name
	c.kind = Kind.LEAGUE
	c.stage = Stage.KNOCKOUT
	c.fixture_tag = FixtureData.Competition.LEAGUE
	c.tier = p_tier
	c.group_index = p_group_index
	c.promotion_slots = p_promotion_slots
	c.relegation_slots = p_relegation_slots
	c.participant_indices = team_indices.duplicate()
	var rows: Array[LeagueTableRow] = []
	for i: int in range(team_indices.size()):
		var label: String = team_names[i] if i < team_names.size() else "Team %d" % team_indices[i]
		rows.append(LeagueTableRow.make(team_indices[i], label))
	c.table = rows
	return c


static func build_cup(p_name: String, team_indices: Array[int], p_two_legged: bool) -> CompetitionData:
	var c := CompetitionData.new()
	c.competition_name = p_name
	c.kind = Kind.KNOCKOUT_CUP
	c.stage = Stage.KNOCKOUT
	c.fixture_tag = FixtureData.Competition.DOMESTIC_CUP
	c.participant_indices = team_indices.duplicate()
	c.remaining_indices = team_indices.duplicate()
	c.two_legged = p_two_legged
	c.current_round = 1
	return c


static func build_continental(
	p_name: String,
	team_indices: Array[int],
	p_two_legged: bool = true,
	has_group_stage: bool = false
) -> CompetitionData:
	var c := CompetitionData.new()
	c.competition_name = p_name
	c.kind = Kind.CONTINENTAL
	c.fixture_tag = FixtureData.Competition.CONTINENTAL
	c.participant_indices = team_indices.duplicate()
	c.remaining_indices = team_indices.duplicate()
	c.two_legged = p_two_legged
	c.current_round = 1
	if has_group_stage and team_indices.size() >= 4:
		c.stage = Stage.GROUP_STAGE
		c.group_stage_complete = false
	else:
		c.stage = Stage.KNOCKOUT
		c.group_stage_complete = true
	return c


## Double round-robin via the circle method. Round r pairs the fixed club at
## slot 0 against the rotating tail; every club appears exactly once per round.
## A bye (-1) is inserted for an odd participant count, and pairings against it
## simply produce no fixture.
##
## `first_date` is the first matchday; each subsequent round is `spacing_days`
## later, which is what makes league fixtures land on real weekend dates.
## If `repeat_cycles` > 1, the full double round-robin is repeated (e.g. 2 cycles = 4 matches against each team).
## If `single_round_robin` is true, only 1 leg is played per pairing (half-season).
func generate_league_fixtures(
	first_date: CareerDate,
	spacing_days: int,
	repeat_cycles: int = 1,
	single_round_robin: bool = false,
	max_rounds_cap: int = -1
) -> void:
	fixtures.clear()
	var slots_base: Array[int] = participant_indices.duplicate()
	if slots_base.size() < 2:
		total_rounds = 0
		return
	if slots_base.size() % 2 != 0:
		slots_base.append(-1)

	var half: int = slots_base.size() / 2
	var rounds_per_half: int = slots_base.size() - 1
	var single_cycle_rounds: int = rounds_per_half if single_round_robin else rounds_per_half * 2
	total_rounds = single_cycle_rounds * maxi(repeat_cycles, 1)
	if max_rounds_cap > 0:
		total_rounds = mini(total_rounds, max_rounds_cap)

	var current_round_offset: int = 0
	for cycle: int in range(maxi(repeat_cycles, 1)):
		var slots: Array[int] = slots_base.duplicate()
		for r: int in range(rounds_per_half):
			if max_rounds_cap > 0 and (current_round_offset + r) >= max_rounds_cap:
				break
			var match_date: CareerDate = first_date.advanced_by((current_round_offset + r) * spacing_days)
			var reverse_date: CareerDate = first_date.advanced_by((current_round_offset + r + rounds_per_half) * spacing_days)
			for i: int in range(half):
				var a: int = slots[i]
				var b: int = slots[slots.size() - 1 - i]
				if a == -1 or b == -1:
					continue
				# Alternate which side is home each round so no club plays a long
				# run of consecutive home or away games.
				var home: int = a if (r + i + cycle) % 2 == 0 else b
				var away: int = b if (r + i + cycle) % 2 == 0 else a

				var first_leg: FixtureData = FixtureData.make(fixture_tag, current_round_offset + r + 1, match_date, home, away)
				fixtures.append(first_leg)
				if not single_round_robin:
					if max_rounds_cap <= 0 or (current_round_offset + r + rounds_per_half) < max_rounds_cap:
						var second_leg: FixtureData = FixtureData.make(fixture_tag, current_round_offset + r + 1 + rounds_per_half, reverse_date, away, home)
						fixtures.append(second_leg)

			# Rotate: slot 0 is fixed, everything else shifts one place.
			var tail: int = slots.pop_back()
			slots.insert(1, tail)
		current_round_offset += single_cycle_rounds
		if max_rounds_cap > 0 and current_round_offset >= max_rounds_cap:
			break


## Initializes multi-stage group stage: divides participant_indices into 4-team groups,
## creates group tables, and schedules round-robin home/away fixtures for each group.
func init_group_stage(first_date: CareerDate, spacing_days: int = 14, rng: RandomNumberGenerator = null) -> void:
	stage = Stage.GROUP_STAGE
	group_stage_complete = false
	fixtures.clear()
	group_teams.clear()
	group_tables.clear()

	var pool: Array[int] = participant_indices.duplicate()
	if rng != null:
		for i: int in range(pool.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: int = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp

	var total_teams: int = pool.size()
	var group_count: int = maxi(1, total_teams / 4)
	for g: int in range(group_count):
		group_teams.append([])
		var g_rows: Array[LeagueTableRow] = []
		group_tables.append(g_rows)

	for i: int in range(total_teams):
		var g_idx: int = i % group_count
		var t_idx: int = pool[i]
		(group_teams[g_idx] as Array).append(t_idx)
		var t_data: TeamData = DataLoader.get_team(t_idx)
		var t_name: String = t_data.team_name if t_data != null else "Team %d" % t_idx
		(group_tables[g_idx] as Array).append(LeagueTableRow.make(t_idx, t_name))

	# Double round-robin (6 matchdays for 4 teams) for each group
	current_round = 1
	total_rounds = 6
	for g: int in range(group_count):
		var g_t: Array = group_teams[g]
		var slots_base: Array[int] = []
		for t_val: Variant in g_t:
			slots_base.append(int(t_val))
		if slots_base.size() % 2 != 0:
			slots_base.append(-1)
		var half: int = slots_base.size() / 2
		var rounds_per_half: int = slots_base.size() - 1

		var slots: Array[int] = slots_base.duplicate()
		for r: int in range(rounds_per_half):
			var match_date: CareerDate = first_date.advanced_by(r * spacing_days)
			var reverse_date: CareerDate = first_date.advanced_by((r + rounds_per_half) * spacing_days)
			for i: int in range(half):
				var a: int = slots[i]
				var b: int = slots[slots.size() - 1 - i]
				if a == -1 or b == -1:
					continue
				var home: int = a if (r + i) % 2 == 0 else b
				var away: int = b if (r + i) % 2 == 0 else a

				var f1: FixtureData = FixtureData.make(fixture_tag, r + 1, match_date, home, away)
				f1.round_label = "Group %s - MD %d" % [String.chr(65 + g), r + 1]
				fixtures.append(f1)

				var f2: FixtureData = FixtureData.make(fixture_tag, r + 1 + rounds_per_half, reverse_date, away, home)
				f2.round_label = "Group %s - MD %d" % [String.chr(65 + g), r + 1 + rounds_per_half]
				fixtures.append(f2)

			var tail: int = slots.pop_back()
			slots.insert(1, tail)


func group_row_for(team_index: int) -> LeagueTableRow:
	for g_rows: Variant in group_tables:
		if typeof(g_rows) == TYPE_ARRAY:
			for r: Variant in (g_rows as Array):
				var row: LeagueTableRow = r as LeagueTableRow
				if row != null and row.team_index == team_index:
					return row
	return null


func sorted_group_table(g_idx: int) -> Array[LeagueTableRow]:
	var out: Array[LeagueTableRow] = []
	if g_idx < 0 or g_idx >= group_tables.size():
		return out
	var raw: Variant = group_tables[g_idx]
	if typeof(raw) != TYPE_ARRAY:
		return out
	for r: Variant in (raw as Array):
		var row: LeagueTableRow = r as LeagueTableRow
		if row != null:
			out.append(row)
	out.sort_custom(func(a: LeagueTableRow, b: LeagueTableRow) -> bool:
		return a.sort_before(b)
	)
	return out


## Advances competition from group stage to knockout stage: qualifies top 2 teams
## from each group into remaining_indices and draws the first knockout round.
func advance_from_group_stage_to_knockout(match_date: CareerDate, rng: RandomNumberGenerator) -> void:
	stage = Stage.KNOCKOUT
	group_stage_complete = true
	remaining_indices.clear()

	for g: int in range(group_tables.size()):
		var sorted: Array[LeagueTableRow] = sorted_group_table(g)
		for q: int in range(mini(2, sorted.size())):
			remaining_indices.append(sorted[q].team_index)

	current_round = 1
	draw_cup_round(match_date, rng)


## Pairs whoever is still alive into the next knockout round. Called at the
## start of each round rather than seeding the whole bracket upfront, which is
## how a real cup draw works — you cannot know round 3 until round 2 is played.
## For non-power-of-two participant counts, seeds automatic byes to stabilize bracket.
## Final (2 teams remaining) is played as a neutral single leg.
func draw_cup_round(match_date: CareerDate, rng: RandomNumberGenerator) -> void:
	if remaining_indices.size() < 2:
		if remaining_indices.size() == 1:
			winner_index = remaining_indices[0]
		return

	var pool: Array[int] = remaining_indices.duplicate()
	# Fisher-Yates using the caller's seeded RNG, so a career replays identically.
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	# Calculate nearest lower or equal power of 2
	var n: int = pool.size()
	var p2: int = 1
	while p2 <= n:
		p2 *= 2
	p2 /= 2

	var pair_count: int = n / 2
	if p2 < n:
		# Non-power-of-two team count: seed byes so subsequent rounds become an exact power of 2.
		# Teams playing = 2 * (n - p2), Bye teams = n - 2 * (n - p2) = 2 * p2 - n.
		pair_count = n - p2

	var label: String = ""
	if pair_count * 2 < pool.size():
		label = "Preliminary Round" if current_round == 1 else "Round %d" % current_round
	else:
		label = String(ROUND_LABELS.get(pool.size(), "Round %d" % current_round))

	var is_final: bool = (pool.size() == 2)
	var round_two_legged: bool = two_legged and not is_final

	for p: int in range(pair_count):
		var home: int = pool[p * 2]
		var away: int = pool[p * 2 + 1]
		var tie: String = "%s-R%d-T%d" % [competition_name, current_round, p]

		var f1: FixtureData = FixtureData.make(fixture_tag, current_round, match_date, home, away)
		f1.round_label = label
		f1.tie_id = tie
		f1.leg = 1 if round_two_legged else 0
		fixtures.append(f1)

		if round_two_legged:
			var f2: FixtureData = FixtureData.make(fixture_tag, current_round, match_date.advanced_by(14), away, home)
			f2.round_label = label
			f2.tie_id = tie
			f2.leg = 2
			fixtures.append(f2)


## Applies a played result to the table (leagues/group stages) or advances the bracket
## (cups). Returns the club index that progressed, or -1.
func record_result(fixture: FixtureData, rng: RandomNumberGenerator) -> int:
	if kind == Kind.LEAGUE:
		var home_row: LeagueTableRow = row_for(fixture.home_team_index)
		var away_row: LeagueTableRow = row_for(fixture.away_team_index)
		if home_row != null:
			home_row.record(fixture.home_score, fixture.away_score)
		if away_row != null:
			away_row.record(fixture.away_score, fixture.home_score)
		return -1

	if stage == Stage.GROUP_STAGE:
		var g_home: LeagueTableRow = group_row_for(fixture.home_team_index)
		var g_away: LeagueTableRow = group_row_for(fixture.away_team_index)
		if g_home != null:
			g_home.record(fixture.home_score, fixture.away_score)
		if g_away != null:
			g_away.record(fixture.away_score, fixture.home_score)
		return -1

	# Knockout: leg 1 of a two-legged tie does not eliminate anyone.
	if two_legged and fixture.leg == 1:
		return -1

	var winner: int = _resolve_tie_winner(fixture, rng)
	fixture.decided_winner_index = winner
	var loser: int = fixture.home_team_index if winner == fixture.away_team_index else fixture.away_team_index
	remaining_indices.erase(loser)
	if remaining_indices.size() == 1:
		winner_index = remaining_indices[0]
	return winner


func _resolve_tie_winner(fixture: FixtureData, rng: RandomNumberGenerator) -> int:
	var home_total: int = fixture.home_score
	var away_total: int = fixture.away_score

	if two_legged and fixture.tie_id != "" and fixture.leg == 2:
		for f: FixtureData in fixtures:
			if f.tie_id != fixture.tie_id or f == fixture or not f.played:
				continue
			home_total += f.goals_for(fixture.home_team_index)
			away_total += f.goals_for(fixture.away_team_index)

	if home_total > away_total:
		return fixture.home_team_index
	if away_total > home_total:
		return fixture.away_team_index

	# Level aggregate/score: simulate extra-time & penalties via QuickSimEngine team units
	var h_team: TeamData = DataLoader.get_team(fixture.home_team_index)
	var a_team: TeamData = DataLoader.get_team(fixture.away_team_index)
	if h_team != null and a_team != null:
		var h_units: Dictionary = QuickSimEngine._calculate_team_units(h_team, h_team.lineup_indices)
		var a_units: Dictionary = QuickSimEngine._calculate_team_units(a_team, a_team.lineup_indices)
		var h_rating: float = float(h_units.get("overall", 50.0))
		var a_rating: float = float(a_units.get("overall", 50.0))
		var diff: float = (h_rating - a_rating) / 100.0
		# Extra time / shootout win probability with slight home boost (0.02) if not neutral
		var home_prob: float = clampf(0.50 + diff * 0.40 + (0.02 if fixture.leg != 0 else 0.0), 0.15, 0.85)
		return fixture.home_team_index if rng.randf() < home_prob else fixture.away_team_index

	return fixture.home_team_index if rng.randf() < 0.50 else fixture.away_team_index


func row_for(team_index: int) -> LeagueTableRow:
	for r: LeagueTableRow in table:
		if r.team_index == team_index:
			return r
	return null


## Table ordered by the standard football tiebreakers.
func sorted_table() -> Array[LeagueTableRow]:
	var copy: Array[LeagueTableRow] = table.duplicate()
	copy.sort_custom(func(a: LeagueTableRow, b: LeagueTableRow) -> bool:
		return a.sort_before(b)
	)
	return copy


func position_of(team_index: int) -> int:
	var ordered: Array[LeagueTableRow] = sorted_table()
	for i: int in range(ordered.size()):
		if ordered[i].team_index == team_index:
			return i + 1
	return ordered.size()


func fixtures_on(date: CareerDate) -> Array[FixtureData]:
	var out: Array[FixtureData] = []
	if date == null:
		return out
	for f: FixtureData in fixtures:
		if f.date != null and f.date.equals(date):
			out.append(f)
	return out


func next_fixture_for(team_index: int, from_date: CareerDate) -> FixtureData:
	var best: FixtureData = null
	for f: FixtureData in fixtures:
		if f.played or not f.involves(team_index) or f.date == null:
			continue
		if from_date != null and f.date.is_before(from_date):
			continue
		if best == null or f.date.is_before(best.date):
			best = f
	return best


func unplayed_count() -> int:
	var n: int = 0
	for f: FixtureData in fixtures:
		if not f.played:
			n += 1
	return n


func is_complete() -> bool:
	if kind == Kind.LEAGUE:
		return unplayed_count() == 0
	if stage == Stage.GROUP_STAGE:
		return false
	return winner_index != -1


## True when every fixture of the current round or stage has been played and a
## new draw is needed.
func cup_round_finished() -> bool:
	if kind == Kind.LEAGUE:
		return false
	if stage == Stage.GROUP_STAGE:
		return unplayed_count() == 0
	for f: FixtureData in fixtures:
		if f.round_number == current_round and not f.played:
			return false
	return true
