class_name SimulationManager
extends Node

signal day_processed(date: Dictionary)
signal simulation_halted(reason: String, event: SimEvent)
signal state_changed(new_state: SimState.State)
signal inbox_updated(inbox: Array[SimEvent], unread_count: int)

@export var tick_interval: float = 0.12
@export var speed_multiplier: float = 1.0

var sim_state: SimState.State = SimState.State.IDLE
var target_advance_date: Dictionary = {}
var accumulator: float = 0.0
var _run_id: int = 0

var current_date: Dictionary = {
	"day": 12,
	"month": 8,
	"year": 2024
}

var event_queue: Array[SimEvent] = []
var inbox: Array[SimEvent] = []
var unread_inbox_count: int = 0

const DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

func _process(delta: float) -> void:
	if sim_state != SimState.State.RUNNING and sim_state != SimState.State.ADVANCING_TO_DATE:
		return

	accumulator += delta
	var current_step_duration: float = maxf(tick_interval / speed_multiplier, 0.01)

	var active_run: int = _run_id
	while accumulator >= current_step_duration and (sim_state == SimState.State.RUNNING or sim_state == SimState.State.ADVANCING_TO_DATE):
		if active_run != _run_id:
			break
		accumulator -= current_step_duration
		_step_day_pipeline()

# --- Core FM Day Pipeline ---
# advance_date() -> process_scheduled_events() -> process_inbox() -> check_stop_conditions()

func _step_day_pipeline() -> void:
	# 1. advance_date()
	_advance_date()

	# 2. process_scheduled_events()
	var halting_event: SimEvent = _process_scheduled_events()

	# 3. process_inbox()
	_process_inbox()

	# 4. Notify UI that date step completed
	day_processed.emit(current_date)

	# 5. check_stop_conditions()
	if halting_event != null:
		_set_state(SimState.State.PAUSED_FOR_EVENT)
		simulation_halted.emit("event", halting_event)
		return

	if sim_state == SimState.State.ADVANCING_TO_DATE and _dates_equal(current_date, target_advance_date):
		stop_simulation("reached_target_date")

func _advance_date() -> void:
	current_date["day"] += 1
	var max_days: int = DAYS_IN_MONTH[current_date["month"] - 1]
	if _is_leap_year(current_date["year"]) and current_date["month"] == 2:
		max_days = 29

	if current_date["day"] > max_days:
		current_date["day"] = 1
		current_date["month"] += 1
		if current_date["month"] > 12:
			current_date["month"] = 1
			current_date["year"] += 1

func _process_scheduled_events() -> SimEvent:
	var first_halting_event: SimEvent = null
	var remaining: Array[SimEvent] = []

	for ev in event_queue:
		if _dates_equal(ev.date, current_date):
			ev.resolve()
			inbox.append(ev)
			unread_inbox_count += 1
			if ev.should_block() and first_halting_event == null:
				first_halting_event = ev
		else:
			remaining.append(ev)

	event_queue = remaining
	return first_halting_event

func _process_inbox() -> void:
	inbox_updated.emit(inbox, unread_inbox_count)

func _is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

func _dates_equal(a: Dictionary, b: Dictionary) -> bool:
	return a.get("day") == b.get("day") and a.get("month") == b.get("month") and a.get("year") == b.get("year")

# --- Flow Controls ---

func start_simulation(speed: float = 1.0) -> void:
	_run_id += 1
	speed_multiplier = maxf(speed, 0.1)
	accumulator = 0.0
	_set_state(SimState.State.RUNNING)

func advance_to_date(target: Dictionary, speed: float = 2.0) -> void:
	_run_id += 1
	target_advance_date = target.duplicate()
	speed_multiplier = maxf(speed, 0.1)
	accumulator = 0.0
	_set_state(SimState.State.ADVANCING_TO_DATE)

func stop_simulation(reason: String = "manual") -> void:
	_run_id += 1
	accumulator = 0.0
	_set_state(SimState.State.IDLE)
	simulation_halted.emit(reason, null)

func mark_inbox_read() -> void:
	unread_inbox_count = 0
	inbox_updated.emit(inbox, unread_inbox_count)

func queue_event(event: SimEvent) -> void:
	event_queue.append(event)

func clear_queue() -> void:
	event_queue.clear()

func _set_state(new_state: SimState.State) -> void:
	if sim_state != new_state:
		sim_state = new_state
		state_changed.emit(sim_state)

# --- Persistence API ---

func serialize() -> Dictionary:
	var q_arr: Array[Dictionary] = []
	for ev in event_queue:
		q_arr.append(ev.serialize())

	var inb_arr: Array[Dictionary] = []
	for ev in inbox:
		inb_arr.append(ev.serialize())

	return {
		"sim_state": int(sim_state),
		"current_date": current_date.duplicate(),
		"speed_multiplier": speed_multiplier,
		"unread_inbox_count": unread_inbox_count,
		"event_queue": q_arr,
		"inbox": inb_arr
	}

func deserialize(data: Dictionary) -> void:
	stop_simulation("deserializing")
	current_date = data.get("current_date", current_date)
	speed_multiplier = data.get("speed_multiplier", 1.0)
	unread_inbox_count = data.get("unread_inbox_count", 0)

	event_queue.clear()
	var ev: SimEvent = null
	for item in data.get("event_queue", []):
		ev = _instantiate_event_from_dict(item)
		if ev:
			event_queue.append(ev)

	inbox.clear()
	for item in data.get("inbox", []):
		ev = _instantiate_event_from_dict(item)
		if ev:
			inbox.append(ev)

	inbox_updated.emit(inbox, unread_inbox_count)
	day_processed.emit(current_date)

func _instantiate_event_from_dict(dict: Dictionary) -> SimEvent:
	var script_path: String = dict.get("script", "")
	var ev: SimEvent = null
	if not script_path.is_empty() and ResourceLoader.exists(script_path):
		var script_res: Resource = load(script_path)
		if script_res:
			ev = script_res.new()
	if not ev:
		ev = SimEvent.new()
	ev.deserialize(dict)
	return ev
