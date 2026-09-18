##
## InboxPanel
##
## The inbox — the core FM interaction loop. Lists messages newest/most urgent
## first, opens one at a time, and renders decisions as buttons whose hint text
## is the real consequence the option will apply.
##
## Decisions route through CareerManager.resolve_inbox_item(), never through
## InboxEngine directly, so the world event and the autosave both happen.
##
## Depends on: CareerPanel, CareerTheme, InboxEngine, CareerManager.
##

class_name InboxPanel
extends CareerPanel

## Which item is expanded. Kept on the panel instance (panels outlive a single
## build) so answering one message does not collapse the reader.
var _selected_index: int = -1


func title() -> String:
	return "Inbox"


func build(host: VBoxContainer, career: CareerSaveData) -> void:
	var p: CareerThemePalette = CareerTheme.palette()
	var items: Array[InboxItem] = InboxEngine.sorted_inbox(career)

	if items.is_empty():
		empty_state(host, "Your inbox is empty.")
		return

	var summary: HBoxContainer = CareerTheme.row()
	host.add_child(summary)
	summary.add_child(CareerTheme.secondary("%d message%s" % [
		items.size(), "" if items.size() == 1 else "s"
	]))
	var pending: int = career.pending_decision_count()
	if pending > 0:
		summary.add_child(CareerTheme.label(
			"%d awaiting your decision" % pending, p.warning
		))

	for i: int in range(items.size()):
		var item: InboxItem = items[i]
		host.add_child(_build_item(item, i, career, p))


func _build_item(item: InboxItem, index: int, career: CareerSaveData, p: CareerThemePalette) -> Control:
	var is_open: bool = index == _selected_index

	var container := PanelContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg: Color = p.panel if is_open else (p.row_alt if index % 2 == 1 else Color(0, 0, 0, 0))
	container.add_theme_stylebox_override("panel", CareerTheme.style_box(bg, p.corner_radius))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	container.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	# --- Header row (always visible, click to open) ---
	var header: Button = CareerTheme.button("", false)
	header.add_theme_stylebox_override("normal", CareerTheme.style_box(Color(0, 0, 0, 0), 0))
	header.add_theme_stylebox_override("hover", CareerTheme.style_box(p.accent_dim, 2))
	header.add_theme_stylebox_override("pressed", CareerTheme.style_box(p.accent_dim, 2))
	header.add_theme_stylebox_override("focus", CareerTheme.style_box(Color(0, 0, 0, 0), 0))
	header.text = "%s  %s" % [item.category_icon(), item.subject]
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_color_override(
		"font_color", p.text_primary if item.is_read else p.accent
	)
	header.pressed.connect(func() -> void:
		_selected_index = -1 if is_open else index
		CareerManager.mark_inbox_read(item)
		refresh()
	)
	column.add_child(header)

	var meta: HBoxContainer = CareerTheme.row()
	meta.add_child(CareerTheme.muted(item.category_name()))
	meta.add_child(CareerTheme.muted(
		item.received.to_display() if item.received != null else ""
	))
	if item.requires_decision():
		var days: int = item.days_left(career.today)
		if days < 9999:
			meta.add_child(CareerTheme.label(
				"Reply within %d day%s" % [maxi(days, 0), "" if days == 1 else "s"],
				p.danger if days <= 2 else p.warning, p.font_size_small
			))
		else:
			meta.add_child(CareerTheme.label("Awaiting reply", p.warning, p.font_size_small))
	elif item.is_resolved and item.chosen_option >= 0:
		var chosen: InboxItem.Option = item.get_option(item.chosen_option)
		if chosen != null:
			meta.add_child(CareerTheme.label(
				"You chose: %s" % chosen.label, p.text_muted, p.font_size_small
			))
	column.add_child(meta)

	if not is_open:
		return container

	# --- Expanded body ---
	column.add_child(CareerTheme.divider())
	column.add_child(CareerTheme.paragraph(item.body))

	if item.requires_decision():
		column.add_child(CareerTheme.spacer(4))
		column.add_child(CareerTheme.muted("Your response"))
		for option_index: int in range(item.option_count()):
			var option: InboxItem.Option = item.get_option(option_index)
			if option == null:
				continue
			var choice := VBoxContainer.new()
			choice.add_theme_constant_override("separation", 1)
			var b: Button = CareerTheme.button(option.label, option_index == 0)
			b.pressed.connect(func() -> void:
				CareerManager.resolve_inbox_item(item, option_index)
				CareerManager.save_career()
				refresh()
			)
			choice.add_child(b)
			if option.hint != "":
				choice.add_child(CareerTheme.muted(option.hint))
			column.add_child(choice)

	return container
