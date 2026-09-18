class_name BoardMeetingEvent
extends SimEvent

var agenda: String = ""

func _init(p_date: Dictionary = {}, p_agenda: String = "Financial & Performance Review") -> void:
	var t: String = "Board Meeting: " + p_agenda
	var d: String = "The board has requested an overview regarding: " + p_agenda
	super(p_date, Priority.Type.NOTABLE, t, d)
	agenda = p_agenda

func serialize() -> Dictionary:
	var data: Dictionary = super.serialize()
	data["agenda"] = agenda
	return data

func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	agenda = data.get("agenda", "")
