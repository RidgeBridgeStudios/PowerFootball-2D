class_name InboxButton
extends Button

var badge: Label

func _ready() -> void:
	badge = get_node_or_null("BadgeLabel") as Label
	if not badge:
		badge = Label.new()
		badge.name = "BadgeLabel"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.anchors_preset = Control.PRESET_TOP_RIGHT
		badge.offset_left = -22.0
		badge.offset_top = -6.0
		badge.offset_right = 2.0
		badge.offset_bottom = 16.0
		add_child(badge)
	set_unread_count(0)

func set_unread_count(count: int) -> void:
	if not is_inside_tree():
		return
	if not badge:
		badge = get_node_or_null("BadgeLabel") as Label
	if not badge:
		return

	if count <= 0:
		badge.visible = false
	else:
		badge.visible = true
		badge.text = str(count)
		badge.modulate = Color(1.0, 0.25, 0.25)
