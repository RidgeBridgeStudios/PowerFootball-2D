##
## WorldEvent
##
## One entry in the club-world history log (Layer 4). Every off-pitch thing
## that happens to a player, a manager, or a club becomes one of these: a
## training injury, a dressing-room row, a contract rejection, a media
## firestorm. WorldEventLog stores them; PressOffice reads them to generate
## Layer 5 narrative; the inbox surfaces the ones that need a decision.
##
## The vision document's original sketch keyed players by a string id. This
## codebase has no PlayerData.player_id (see .claude/rules/ai-architect.md), so
## participants are identified by the synthesized team*1000+squad_index key
## that MatchStatsTracker already uses, plus a cached display name so a log
## entry stays readable after the player leaves the club.
##
## Depends on: CareerDate.
## Exposes: the fields below, make(), headline(), involves(), severity_label().
##

class_name WorldEvent
extends Resource

enum Category {
	MATCH = 0,
	TRAINING = 1,
	DRESSING_ROOM = 2,
	INJURY = 3,
	TRANSFER = 4,
	CONTRACT = 5,
	MEDIA = 6,
	BOARD = 7,
	YOUTH = 8,
	PERSONAL_LIFE = 9,
	STAFF = 10,
}

const CATEGORY_NAMES: Array[String] = [
	"Match", "Training", "Dressing Room", "Injury", "Transfer", "Contract",
	"Media", "Board", "Youth", "Personal Life", "Staff"
]

## Machine-readable tag, e.g. &"training_injury", &"bust_up", &"transfer_request".
## PressOffice keys quote selection off this, never off narrative_context.
@export var event_tag: StringName = &""
@export var category: Category = Category.MATCH
@export var date: CareerDate = null
## Season this happened in, so a career history can be grouped by year.
@export var season_year: int = 2026
## team*1000 + squad_index, or -1 when the event has no player subject.
@export var primary_player_key: int = -1
@export var secondary_player_key: int = -1
@export var primary_player_name: String = ""
@export var secondary_player_name: String = ""
@export var club_name: String = ""
## Human-readable sentence already resolved for display.
@export var narrative_context: String = ""
## Compatibility alias for narrative_context.
var narrative: String:
	get:
		return narrative_context
	set(val):
		narrative_context = val
## -1.0 = maximally damaging, 0.0 = neutral, 1.0 = maximally positive.
@export_range(-1.0, 1.0) var sentiment: float = 0.0
## 0.0 = trivia, 1.0 = career-defining. Drives inbox prominence and whether
## the press picks the story up at all.
@export_range(0.0, 1.0) var significance: float = 0.3
## Set true once an inbox item derived from this event has been answered.
@export var resolved: bool = false
## Index into the originating InboxItem's option list, or -1 if never asked.
@export var resolution_choice: int = -1


static func make(
	p_tag: StringName,
	p_category: Category,
	p_date: CareerDate,
	p_narrative: String,
	p_sentiment: float = 0.0,
	p_significance: float = 0.3
) -> WorldEvent:
	var e := WorldEvent.new()
	e.event_tag = p_tag
	e.category = p_category
	e.date = p_date.copy() if p_date != null else null
	e.season_year = p_date.year if p_date != null else 2026
	e.narrative_context = p_narrative
	e.sentiment = clampf(p_sentiment, -1.0, 1.0)
	e.significance = clampf(p_significance, 0.0, 1.0)
	return e


func with_player(key: int, display_name: String) -> WorldEvent:
	primary_player_key = key
	primary_player_name = display_name
	return self


func with_secondary(key: int, display_name: String) -> WorldEvent:
	secondary_player_key = key
	secondary_player_name = display_name
	return self


func with_club(name_str: String) -> WorldEvent:
	club_name = name_str
	return self


func category_name() -> String:
	return CATEGORY_NAMES[clampi(int(category), 0, CATEGORY_NAMES.size() - 1)]


func involves(player_key: int) -> bool:
	return primary_player_key == player_key or secondary_player_key == player_key


func severity_label() -> String:
	if significance >= 0.75:
		return "Major"
	if significance >= 0.45:
		return "Notable"
	return "Minor"


func headline() -> String:
	var stamp: String = date.to_display() if date != null else ""
	return "[%s] %s — %s" % [category_name(), stamp, narrative_context]
