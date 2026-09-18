class_name SimEvent
extends RefCounted

var date: Dictionary = {"day": 1, "month": 1, "year": 2024}
var priority: Priority.Type = Priority.Type.INFO
var title: String = ""
var description: String = ""
var id: String = ""

func _init(p_date: Dictionary = {}, p_priority: Priority.Type = Priority.Type.INFO, p_title: String = "", p_description: String = "", p_id: String = "") -> void:
	date = p_date
	priority = p_priority
	title = p_title
	description = p_description
	id = p_id if not p_id.is_empty() else str(ResourceUID.create_id())

func should_block() -> bool:
	return priority >= Priority.Type.URGENT

func get_screen() -> PackedScene:
	return null

func resolve() -> void:
	pass

func serialize() -> Dictionary:
	return {
		"script": get_script().resource_path,
		"id": id,
		"date": date.duplicate(),
		"priority": int(priority),
		"title": title,
		"description": description
	}

func deserialize(data: Dictionary) -> void:
	id = data.get("id", id)
	date = data.get("date", date)
	priority = data.get("priority", priority) as Priority.Type
	title = data.get("title", title)
	description = data.get("description", description)
