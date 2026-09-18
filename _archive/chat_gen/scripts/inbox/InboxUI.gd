class_name InboxUI
extends Panel

signal item_selected(event: SimEvent)

var item_list: ItemList
var close_button: Button
var messages: Array[SimEvent] = []

func _ready() -> void:
	custom_minimum_size = Vector2(440, 320)
	hide()

	var vbox: VBoxContainer = get_node_or_null("VBoxContainer") as VBoxContainer
	if not vbox:
		vbox = VBoxContainer.new()
		vbox.name = "VBoxContainer"
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = 12.0
		vbox.offset_top = 12.0
		vbox.offset_right = -12.0
		vbox.offset_bottom = -12.0
		add_child(vbox)

	item_list = vbox.get_node_or_null("ItemList") as ItemList
	if not item_list:
		item_list = ItemList.new()
		item_list.name = "ItemList"
		item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(item_list)

	close_button = vbox.get_node_or_null("CloseButton") as Button
	if not close_button:
		close_button = Button.new()
		close_button.name = "CloseButton"
		close_button.text = "Close"
		vbox.add_child(close_button)

	close_button.pressed.connect(hide)
	item_list.item_selected.connect(_on_item_selected)

func refresh(inbox_events: Array[SimEvent]) -> void:
	messages = inbox_events
	if not item_list:
		return
	item_list.clear()

	for ev in messages:
		var d: Dictionary = ev.date
		var prio_name: String = Priority.Type.keys()[ev.priority]
		var item_text: String = "[%02d/%02d] [%s] %s" % [
			d.get("day", 1),
			d.get("month", 1),
			prio_name,
			ev.title
		]
		item_list.add_item(item_text)

func _on_item_selected(index: int) -> void:
	if index >= 0 and index < messages.size():
		item_selected.emit(messages[index])
