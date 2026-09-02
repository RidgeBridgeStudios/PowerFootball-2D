##
## FixtureData
##
## One scheduled match in the career calendar. Every competition — league, cup,
## continental — produces these, so the calendar and the "next fixture" logic
## only ever deal with one shape.
##
## Depends on: CareerDate.
## Exposes: the fields below, make(), involves(), opponent_of(), is_home_for(),
##          result_char_for(), score_line().
##

class_name FixtureData
extends Resource

enum Competition { LEAGUE = 0, DOMESTIC_CUP = 1, CONTINENTAL = 2, FRIENDLY = 3 }

const COMPETITION_NAMES: Array[String] = [
	"League", "Domestic Cup", "Continental Cup", "Friendly"
]

const COMPETITION_SHORT: Array[String] = ["LGE", "CUP", "CON", "FRN"]

@export var competition: Competition = Competition.LEAGUE
## League matchday, or cup round number.
@export var round_number: int = 1
## Human-readable round for cups ("Quarter-Final"), empty for league.
@export var round_label: String = ""
@export var date: CareerDate = null
@export var home_team_index: int = 0
@export var away_team_index: int = 1
@export var played: bool = false
@export var home_score: int = 0
@export var away_score: int = 0
@export var attendance: int = 0
## Two-legged ties: 1 or 2, else 0 for single matches.
@export var leg: int = 0
## Set on leg 2 so aggregate can be resolved without searching.
@export var tie_id: String = ""
## True when the human manager's team plays in this fixture — cached so the
## calendar does not re-derive it every redraw.
@export var involves_user: bool = false
## Winner index after extra time/penalties for cup ties, -1 if not applicable.
@export var decided_winner_index: int = -1


static func make(
	p_competition: Competition,
	p_round: int,
	p_date: CareerDate,
	p_home: int,
	p_away: int
) -> FixtureData:
	var f := FixtureData.new()
	f.competition = p_competition
	f.round_number = p_round
	f.date = p_date.copy() if p_date != null else null
	f.home_team_index = p_home
	f.away_team_index = p_away
	return f


func involves(team_index: int) -> bool:
	return home_team_index == team_index or away_team_index == team_index


func is_home_for(team_index: int) -> bool:
	return home_team_index == team_index


func opponent_of(team_index: int) -> int:
	if home_team_index == team_index:
		return away_team_index
	if away_team_index == team_index:
		return home_team_index
	return -1


func goals_for(team_index: int) -> int:
	if home_team_index == team_index:
		return home_score
	if away_team_index == team_index:
		return away_score
	return 0


func goals_against(team_index: int) -> int:
	if home_team_index == team_index:
		return away_score
	if away_team_index == team_index:
		return home_score
	return 0


## "W" / "D" / "L" from one team's perspective, or "" if not involved/unplayed.
func result_char_for(team_index: int) -> String:
	if not played or not involves(team_index):
		return ""
	var gf: int = goals_for(team_index)
	var ga: int = goals_against(team_index)
	if gf > ga:
		return "W"
	if gf < ga:
		return "L"
	return "D"


func score_line() -> String:
	if not played:
		return "v"
	return "%d - %d" % [home_score, away_score]


func competition_name() -> String:
	return COMPETITION_NAMES[clampi(int(competition), 0, COMPETITION_NAMES.size() - 1)]


func competition_short() -> String:
	return COMPETITION_SHORT[clampi(int(competition), 0, COMPETITION_SHORT.size() - 1)]


func round_display() -> String:
	if round_label != "":
		return round_label
	if competition == Competition.LEAGUE:
		return "Matchday %d" % round_number
	return "Round %d" % round_number
