##
## CareerSaveData
##
## The complete state of one manager career — the root object CareerManager
## operates on and CareerSerializer writes to disk. Everything that must
## survive quitting the game hangs off this.
##
## One deliberate exclusion: the LEAGUE ITSELF (squads, attributes, staff)
## lives in DataLoader.league and is saved alongside via DataLoader.save_league()
## into the same slot directory, rather than being duplicated here. Two copies
## of every PlayerData would guarantee they eventually disagree.
##
## Depends on: ManagerCareerProfile, CompetitionData, PlayerCareerState,
##             ClubFinances, BoardState, TrainingSchedule, InboxItem,
##             WorldEvent, ScoutReport, TransferOffer, CareerDate.
## Exposes: the fields below, state_for(), competition(), league_competition(),
##          user_team_name(), next_user_fixture(), season_label().
##

class_name CareerSaveData
extends Resource

## Bumped whenever the on-disk shape changes. CareerSerializer migrates
## anything older; anything newer is refused rather than half-read.
const SAVE_VERSION: int = 1

## Season phases drive what the calendar allows on a given day.
enum Phase { PRE_SEASON = 0, REGULAR_SEASON = 1, OFF_SEASON = 2 }

const PHASE_NAMES: Array[String] = ["Pre-Season", "Regular Season", "Off-Season"]

@export var save_version: int = SAVE_VERSION
@export var slot_index: int = 0
@export var save_name: String = "New Career"
@export var created_iso: String = ""
@export var last_played_iso: String = ""

## --- Identity ------------------------------------------------------------------
@export var profile: ManagerCareerProfile = null
@export var user_team_index: int = 0

## --- Calendar ------------------------------------------------------------------
@export var today: CareerDate = null
@export var season_start_year: int = 2026
@export var phase: Phase = Phase.PRE_SEASON
## Deterministic career RNG seed — reseeded per save so a career replays the
## same way, and so two slots never share a random stream.
@export var rng_seed: int = 0

## --- Competitions ---------------------------------------------------------------
@export var competitions: Array[CompetitionData] = []
## Completed seasons: {year, club, position, points, comp_results, trophies}
@export var season_archive: Array[Dictionary] = []
## Division/tier rosters: team indices in Tier 1 (Premier) and Tier 2 (Championship).
@export var tier_1_indices: Array[int] = []
@export var tier_2_indices: Array[int] = []
@export var continental_indices: Array[int] = []

## --- Per-club career state --------------------------------------------------------
## player_key (team*1000+squad_index) -> PlayerCareerState. Covers EVERY club in
## the league, not just the user's — AI squads age, get injured, and develop too.
@export var player_states: Dictionary = {}
## team_index -> ClubFinances. Only the user's club is fully simulated; AI clubs
## carry a lightweight record so transfer budgets stay meaningful.
@export var club_finances: Dictionary = {}
@export var board: BoardState = null
@export var training: TrainingSchedule = null

## --- Inbox, events, market ----------------------------------------------------------
@export var inbox: Array[InboxItem] = []
@export var world_events: Array[WorldEvent] = []
@export var scout_reports: Array[ScoutReport] = []
@export var shortlist_keys: Array[int] = []
@export var active_offers: Array[TransferOffer] = []
## Scout name -> region/competition they are assigned to.
@export var scout_assignments: Dictionary = {}

## --- Flags --------------------------------------------------------------------
@export var transfer_window_open: bool = true
@export var is_sacked: bool = false
@export var unemployed: bool = false
@export var awaiting_match_result: bool = false
## Fixture handed to the retired real-time match layer by play_next_fixture(), so
## a returned result can be attributed. Unused by the quick-sim path.
@export var pending_fixture_round: int = -1
@export var pending_fixture_competition: int = -1


static func make_new(
	p_profile: ManagerCareerProfile,
	p_team_index: int,
	p_start: CareerDate,
	p_seed: int
) -> CareerSaveData:
	var c := CareerSaveData.new()
	c.profile = p_profile
	c.user_team_index = p_team_index
	c.today = p_start.copy()
	c.season_start_year = p_start.year
	c.rng_seed = p_seed
	c.created_iso = p_start.to_iso()
	c.last_played_iso = p_start.to_iso()
	c.phase = Phase.PRE_SEASON
	return c


func phase_name() -> String:
	return PHASE_NAMES[clampi(int(phase), 0, PHASE_NAMES.size() - 1)]


## "2026/27" — the label every season-scoped screen prints.
func season_label() -> String:
	return "%d/%02d" % [season_start_year, (season_start_year + 1) % 100]


func state_for(player_key: int) -> PlayerCareerState:
	return player_states.get(player_key, null) as PlayerCareerState


func state_for_squad(team_index: int, squad_index: int) -> PlayerCareerState:
	return state_for(team_index * 1000 + squad_index)


func finances_for(team_index: int) -> ClubFinances:
	return club_finances.get(team_index, null) as ClubFinances


func user_finances() -> ClubFinances:
	return finances_for(user_team_index)


func competition(comp_kind: FixtureData.Competition) -> CompetitionData:
	for c: CompetitionData in competitions:
		if c.fixture_tag == comp_kind:
			return c
	return null


func league_competition() -> CompetitionData:
	for c: CompetitionData in competitions:
		if c.kind == CompetitionData.Kind.LEAGUE and c.participant_indices.has(user_team_index):
			return c
	return competition(FixtureData.Competition.LEAGUE)


func continental_competition() -> CompetitionData:
	return competition(FixtureData.Competition.CONTINENTAL)


func cup_competition() -> CompetitionData:
	return competition(FixtureData.Competition.DOMESTIC_CUP)


## Every fixture across every competition scheduled for one date.
func fixtures_on(date: CareerDate) -> Array[FixtureData]:
	var out: Array[FixtureData] = []
	for c: CompetitionData in competitions:
		out.append_array(c.fixtures_on(date))
	return out


## The user's next unplayed fixture in any competition.
func next_user_fixture() -> FixtureData:
	var best: FixtureData = null
	for c: CompetitionData in competitions:
		var f: FixtureData = c.next_fixture_for(user_team_index, today)
		if f == null:
			continue
		if best == null or f.date.is_before(best.date):
			best = f
	return best


func days_until_next_fixture() -> int:
	var f: FixtureData = next_user_fixture()
	if f == null or f.date == null or today == null:
		return -1
	return today.days_until(f.date)


## The user's last N results across all competitions, oldest first.
func recent_user_results(count: int) -> Array[FixtureData]:
	var played: Array[FixtureData] = []
	for c: CompetitionData in competitions:
		for f: FixtureData in c.fixtures:
			if f.played and f.involves(user_team_index):
				played.append(f)
	played.sort_custom(func(a: FixtureData, b: FixtureData) -> bool:
		if a.date == null or b.date == null:
			return false
		return a.date.is_before(b.date)
	)
	if played.size() <= count:
		return played
	return played.slice(played.size() - count, played.size())


func unread_inbox_count() -> int:
	var n: int = 0
	for item: InboxItem in inbox:
		if not item.is_read:
			n += 1
	return n


func pending_decision_count() -> int:
	var n: int = 0
	for item: InboxItem in inbox:
		if item.requires_decision():
			n += 1
	return n


func shortlist_contains(player_key: int) -> bool:
	return shortlist_keys.has(player_key)


func report_for(player_key: int) -> ScoutReport:
	for r: ScoutReport in scout_reports:
		if r.target_key() == player_key:
			return r
	return null


## Squad-wide average morale, weighted by player reputation so a disgruntled
## star drags the dressing room down further than a disgruntled reserve.
func squad_morale(team: TeamData) -> float:
	if team == null or team.squad.is_empty():
		return 0.5
	var total: float = 0.0
	var weight_total: float = 0.0
	for p: PlayerData in team.squad:
		var w: float = 0.5 + p.player_reputation
		total += p.morale * w
		weight_total += w
	if weight_total <= 0.0:
		return 0.5
	return clampf(total / weight_total, 0.0, 1.0)


func log_event(event: WorldEvent) -> void:
	world_events.append(event)
	# The log is a rolling history, not an infinite ledger — a long career
	# would otherwise grow the save file without bound.
	while world_events.size() > 600:
		world_events.remove_at(0)
