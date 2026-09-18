class_name ScheduleRow
extends HBoxContainer

@export var color_info: Color = Color(0.55, 0.55, 0.55)
@export var color_notable: Color = Color(1.0, 1.0, 1.0)
@export var color_urgent: Color = Color(1.0, 0.53, 0.0)
@export var color_blocking: Color = Color(1.0, 0.13, 0.13)

var indicator: ColorRect
var label: Label
var event_id: String = ""
var event_data: Dictionary = {}
var event_ref: SimEvent = null
var _flashing: bool = false

func _init(data_or_event: Variant = null) -> void:
	custom_minimum_size.y = 28.0
	if data_or_event is SimEvent:
		event_ref = data_or_event
		event_id = event_ref.id
		event_data = {
			"id": event_ref.id,
			"date": event_ref.date,
			"title": event_ref.title,
			"priority": event_ref.priority
		}
	elif data_or_event is Dictionary:
		event_data = data_or_event
		event_id = str(event_data.get("id", event_data.get("title", "")))

func _ready() -> void:
	indicator = ColorRect.new()
	indicator.custom_minimum_size = Vector2(16, 16)
	var base_col: Color = get_priority_color()
	indicator.color = base_col
	add_child(indicator)

	label = Label.new()
	var d: Dictionary = event_ref.date if event_ref else event_data.get("date", {})
	var title_text: String = event_ref.title if event_ref else event_data.get("title", "")
	var prio_val: int = int(event_ref.priority) if event_ref else int(event_data.get("priority", Priority.Type.INFO))
	var prio_name: String = Priority.Type.keys()[prio_val]

	label.text = " %02d/%02d/%04d - [%s] %s" % [
		d.get("day", 1), d.get("month", 1), d.get("year", 2024),
		prio_name,
		title_text
	]
	add_child(label)

func get_priority_color() -> Color:
	var prio: int = int(event_ref.priority) if event_ref else int(event_data.get("priority", Priority.Type.INFO))
	match prio:
		Priority.Type.INFO: return color_info
		Priority.Type.NOTABLE: return color_notable
		Priority.Type.URGENT: return color_urgent
		Priority.Type.BLOCKING: return color_blocking
	return color_info

func flash() -> void:
	if _flashing:
		return
	_flashing = true

	if size == Vector2.ZERO:
		await get_tree().process_frame

	pivot_offset = size * 0.5
	var base_col: Color = get_priority_color()
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(indicator, ^"color", Color.WHITE, 0.15).from(base_col)
	tween.tween_property(self, ^"scale", Vector2(1.08, 1.08), 0.15).from(Vector2.ONE)
	tween.chain().tween_property(indicator, ^"color", base_col, 0.2)
	tween.parallel().tween_property(self, ^"scale", Vector2.ONE, 0.2)
	await tween.finished
	_flashing = false
