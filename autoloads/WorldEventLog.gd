##
## WorldEventLog (Autoload singleton)
##
## The club world's history book (Layer 4 -> Layer 5). Every off-pitch thing
## that happens to a player, a manager, or a club is appended here, and the
## narrative layer reads it back to generate press quotes and story beats.
##
## Deliberately NOT the owner of the events: CareerSaveData.world_events is the
## persisted array, and this autoload is a live view over it plus the append
## API and the query helpers. That split matters because the log has to survive
## a save/load round trip, and an autoload's own state does not.
##
## Has no class_name — Godot 4.7 rejects a class_name that collides with an
## autoload's injected global (see .claude/rules/godot-47-core.md).
##
## Depends on: GameEvents, WorldEvent, CareerDate, PressOffice, ManagerData.
## Exposes: bind(), log_event(), record(), recent(), for_player(), by_category(),
##          since(), generate_press_reaction(), clear().
##

extends Node

## Events the press will actually pick up. Anything below this significance is
## club-internal and never becomes a headline.
const PRESS_SIGNIFICANCE_THRESHOLD: float = 0.55

## The live career this log is writing into. Null outside a career.
var _career: CareerSaveData = null
## Reusable quote generator — PressOffice is a plain RefCounted with no state
## between calls, so one instance serves the whole session.
var _press: PressOffice = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_press = PressOffice.new()


## Points the log at a career. Called by CareerManager on start/load, and with
## null on career teardown so a stale reference cannot outlive the save.
func bind(career: CareerSaveData) -> void:
	_career = career


func is_bound() -> bool:
	return _career != null


## Appends an event and announces it. The single write path — nothing else
## should touch CareerSaveData.world_events directly.
func log_event(event: WorldEvent) -> void:
	if event == null:
		return
	if _career == null:
		# Outside a career (a friendly, the practice arena) events are simply
		# discarded rather than queued, so nothing leaks into the next career.
		return
	_career.log_event(event)
	GameEvents.world_event_logged.emit(event)


## Convenience builder + append in one call, for the common case.
func record(
	tag: StringName,
	category: WorldEvent.Category,
	narrative: String,
	sentiment: float = 0.0,
	significance: float = 0.3
) -> WorldEvent:
	if _career == null:
		return null
	var event: WorldEvent = WorldEvent.make(
		tag, category, _career.today, narrative, sentiment, significance
	)
	log_event(event)
	return event


func record_for_player(
	tag: StringName,
	category: WorldEvent.Category,
	player_key: int,
	player_name: String,
	narrative: String,
	sentiment: float = 0.0,
	significance: float = 0.3
) -> WorldEvent:
	var event: WorldEvent = record(tag, category, narrative, sentiment, significance)
	if event != null:
		event.with_player(player_key, player_name)
	return event


## --- Queries -------------------------------------------------------------------

func all_events() -> Array[WorldEvent]:
	if _career == null:
		return []
	return _career.world_events


## Newest first — which is the opposite of storage order, so the club-world
## feed reads like a timeline without every caller reversing it themselves.
func recent(count: int) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	if _career == null:
		return out
	var events: Array[WorldEvent] = _career.world_events
	var start: int = maxi(events.size() - count, 0)
	for i: int in range(events.size() - 1, start - 1, -1):
		out.append(events[i])
	return out


func for_player(player_key: int, count: int = 20) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	if _career == null:
		return out
	var events: Array[WorldEvent] = _career.world_events
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].involves(player_key):
			out.append(events[i])
			if out.size() >= count:
				break
	return out


func by_category(category: WorldEvent.Category, count: int = 20) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	if _career == null:
		return out
	var events: Array[WorldEvent] = _career.world_events
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].category == category:
			out.append(events[i])
			if out.size() >= count:
				break
	return out


func since(date: CareerDate) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	if _career == null or date == null:
		return out
	for e: WorldEvent in _career.world_events:
		if e.date != null and not e.date.is_before(date):
			out.append(e)
	return out


## Events significant enough for the press to run with — the feed the media
## ticker on the hub screen draws from.
func newsworthy(count: int = 8) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	if _career == null:
		return out
	var events: Array[WorldEvent] = _career.world_events
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].significance >= PRESS_SIGNIFICANCE_THRESHOLD:
			out.append(events[i])
			if out.size() >= count:
				break
	return out


## --- Layer 5 bridge ---------------------------------------------------------------

## Turns one logged event into a manager quote, routed through the existing
## PressOffice generator so career-mode narrative speaks with exactly the same
## voice (and trait-driven variation) as the touchline and post-match lines
## the match layer already produces.
func generate_press_reaction(event: WorldEvent, manager: ManagerData) -> String:
	if event == null or manager == null or _press == null:
		return ""

	var ctx := PressOffice.PressContext.new()
	ctx.player_name = event.primary_player_name
	ctx.opponent_name = ""
	ctx.is_big_game = event.significance >= 0.75

	match event.category:
		WorldEvent.Category.INJURY:
			ctx.event = "injury_update"
		WorldEvent.Category.TRANSFER:
			ctx.event = "transfer_speculation"
		WorldEvent.Category.MATCH:
			ctx.event = "post_match"
			if event.sentiment > 0.15:
				ctx.match_result = "win"
			elif event.sentiment < -0.15:
				ctx.match_result = "loss"
			else:
				ctx.match_result = "draw"
		_:
			# Dressing-room, board and contract stories have no dedicated
			# PressOffice event; a pre-match framing is the closest existing
			# voice and keeps every quote trait-consistent.
			ctx.event = "pre_match"

	return _press.generate_quote(manager, ctx)


func clear() -> void:
	if _career != null:
		_career.world_events.clear()
