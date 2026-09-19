##
## CareerTheme
##
## The Manager Mode widget factory. Every control in the career UI is built
## through here, which is what keeps literal Colors and hand-placed geometry
## out of the panel scripts entirely.
##
## Two rules this exists to enforce:
##   1. Colours come from manager_mode_theme.tres (a CareerThemePalette), never
##      from a literal in a panel.
##   2. Layout is anchors and containers only — nothing here calls
##      set_position() or set_size(), and neither should any caller.
##
## Depends on: CareerThemePalette.
## Exposes: palette(), label(), heading(), title(), panel(), card(), row(),
##          data_row(), button(), nav_button(), bar(), form_strip(), spacer(),
##          divider(), money(), tint_for_rating(), result_color().
##

class_name CareerTheme
extends RefCounted

const PALETTE_PATH: String = "res://ui/manager_mode/manager_mode_theme.tres"

## Loaded once and shared. A panel rebuilding a 40-row squad list must not
## re-read the resource per row.
static var _palette: CareerThemePalette = null


static func palette() -> CareerThemePalette:
	if _palette == null:
		var loaded: Resource = load(PALETTE_PATH)
		_palette = loaded as CareerThemePalette
		if _palette == null:
			# Falling back to defaults keeps the UI renderable if the .tres is
			# missing, rather than crashing every career screen.
			push_warning("CareerTheme: %s missing or wrong type; using defaults." % PALETTE_PATH)
			_palette = CareerThemePalette.new()
	return _palette


## --- Text ---------------------------------------------------------------------

static func label(
	text: String,
	color: Color = Color.TRANSPARENT,
	size: int = -1,
	align: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var p: CareerThemePalette = palette()
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", p.text_primary if color == Color.TRANSPARENT else color)
	l.add_theme_font_size_override("font_size", p.font_size_body if size < 0 else size)
	return l


## A fixed-width column cell. min_width is a minimum, not a position — the
## container still owns placement.
static func cell(
	text: String,
	min_width: int,
	color: Color = Color.TRANSPARENT,
	align: int = HORIZONTAL_ALIGNMENT_LEFT,
	size: int = -1
) -> Label:
	var l: Label = label(text, color, size, align)
	l.custom_minimum_size = Vector2(float(min_width), 0.0)
	l.clip_text = true
	return l


static func heading(text: String) -> Label:
	var p: CareerThemePalette = palette()
	return label(text, p.text_primary, p.font_size_heading)


static func title(text: String) -> Label:
	var p: CareerThemePalette = palette()
	return label(text, p.text_primary, p.font_size_title)


static func muted(text: String) -> Label:
	var p: CareerThemePalette = palette()
	return label(text, p.text_muted, p.font_size_small)


static func secondary(text: String) -> Label:
	var p: CareerThemePalette = palette()
	return label(text, p.text_secondary, p.font_size_body)


## Wraps long prose. Used for inbox bodies and scout verdicts.
static func paragraph(text: String) -> Label:
	var p: CareerThemePalette = palette()
	var l: Label = label(text, p.text_secondary, p.font_size_body)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## --- Surfaces -------------------------------------------------------------------

static func style_box(bg: Color, radius: int, border_color: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	if border_width > 0:
		box.border_width_left = border_width
		box.border_width_right = border_width
		box.border_width_top = border_width
		box.border_width_bottom = border_width
		box.border_color = border_color
	return box


## A titled card: PanelContainer > Margin > VBox, with the VBox returned for
## the caller to fill. The card itself is reachable via the returned node's
## owner chain when needed.
static func card(title_text: String) -> VBoxContainer:
	var p: CareerThemePalette = palette()
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", style_box(p.panel, p.corner_radius))
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", p.content_margin)
	margin.add_theme_constant_override("margin_right", p.content_margin)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	container.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	if title_text != "":
		box.add_child(heading(title_text))
		box.add_child(divider())
	return box


## Returns the outermost node of a card built by card(), for adding to a parent.
static func card_root(card_body: VBoxContainer) -> Control:
	# card() nests PanelContainer > MarginContainer > VBoxContainer.
	var margin: Node = card_body.get_parent()
	if margin == null:
		return card_body
	var panel_node: Node = margin.get_parent()
	return (panel_node if panel_node != null else margin) as Control


static func divider() -> HSeparator:
	var p: CareerThemePalette = palette()
	var sep := HSeparator.new()
	var box := StyleBoxFlat.new()
	box.bg_color = p.divider
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", box)
	return sep


static func spacer(height: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, float(height))
	return c


## A horizontal row container with consistent spacing.
static func row(separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


## A data-table row, optionally tinted for banding or highlight. Returns the
## HBox to fill; the tinted PanelContainer wrapper is its parent.
static func data_row(index: int, highlight: bool = false) -> HBoxContainer:
	var p: CareerThemePalette = palette()
	var wrapper := PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg: Color = Color(0, 0, 0, 0)
	if highlight:
		bg = p.row_hover
	elif index % 2 == 1:
		bg = p.row_alt
	wrapper.add_theme_stylebox_override("panel", style_box(bg, 2))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	wrapper.add_child(margin)

	var h: HBoxContainer = row()
	margin.add_child(h)
	return h


static func data_row_root(row_body: HBoxContainer) -> Control:
	var margin: Node = row_body.get_parent()
	if margin == null:
		return row_body
	var wrapper: Node = margin.get_parent()
	return (wrapper if wrapper != null else margin) as Control


## A column-header strip, styled distinctly from the rows beneath it.
static func header_row() -> HBoxContainer:
	var p: CareerThemePalette = palette()
	var wrapper := PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_stylebox_override("panel", style_box(p.header, 2))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	wrapper.add_child(margin)
	var h: HBoxContainer = row()
	margin.add_child(h)
	return h


## --- Interactive -----------------------------------------------------------------

static func button(text: String, primary: bool = false) -> Button:
	var p: CareerThemePalette = palette()
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", p.font_size_body)
	if primary:
		b.add_theme_color_override("font_color", p.text_on_accent)
		b.add_theme_color_override("font_hover_color", p.text_on_accent)
		b.add_theme_color_override("font_pressed_color", p.text_on_accent)
		b.add_theme_color_override("font_focus_color", p.text_on_accent)
		b.add_theme_stylebox_override("normal", _button_box(p.accent, p))
		b.add_theme_stylebox_override("hover", _button_box(p.positive, p))
		b.add_theme_stylebox_override("pressed", _button_box(p.accent_dim, p))
		b.add_theme_stylebox_override("focus", _button_box(p.positive, p))
	else:
		b.add_theme_color_override("font_color", p.text_primary)
		b.add_theme_color_override("font_hover_color", p.accent)
		b.add_theme_color_override("font_pressed_color", p.accent)
		b.add_theme_color_override("font_focus_color", p.accent)
		b.add_theme_stylebox_override("normal", _button_box(p.header, p))
		b.add_theme_stylebox_override("hover", _button_box(p.accent_dim, p))
		b.add_theme_stylebox_override("pressed", _button_box(p.accent_dim, p))
		b.add_theme_stylebox_override("focus", _button_box(p.accent_dim, p))
	b.add_theme_stylebox_override("disabled", _button_box(p.surface, p))
	b.add_theme_color_override("font_disabled_color", p.text_muted)
	return b


static func _button_box(bg: Color, p: CareerThemePalette) -> StyleBoxFlat:
	var box: StyleBoxFlat = style_box(bg, p.corner_radius)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	return box


## Left-hand sidebar entry. `selected` gives it the accent bar FM uses to show
## which section is open.
static func nav_button(text: String, selected: bool, badge: int = 0) -> Button:
	var p: CareerThemePalette = palette()
	var b := Button.new()
	b.text = "%s  (%d)" % [text, badge] if badge > 0 else text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", p.font_size_body)
	b.add_theme_color_override("font_color", p.accent if selected else p.text_secondary)
	b.add_theme_color_override("font_hover_color", p.accent)
	b.add_theme_color_override("font_pressed_color", p.accent)
	b.add_theme_color_override("font_focus_color", p.accent)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var normal := StyleBoxFlat.new()
	normal.bg_color = p.accent_dim if selected else Color(0, 0, 0, 0)
	normal.border_width_left = 3 if selected else 0
	normal.border_color = p.accent
	normal.content_margin_left = 14.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 7.0
	normal.content_margin_bottom = 7.0
	b.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = p.accent_dim
	hover.border_width_left = 3
	hover.border_color = p.accent
	hover.content_margin_left = 14.0
	hover.content_margin_right = 10.0
	hover.content_margin_top = 7.0
	hover.content_margin_bottom = 7.0
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	return b


## --- Data visuals -------------------------------------------------------------------

## A 0..1 attribute/stat bar, coloured by value rather than by category, so a
## squad list reads at a glance.
static func bar(value: float, width: int = 90, show_text: bool = false) -> Control:
	var p: CareerThemePalette = palette()
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = clampf(value, 0.0, 1.0)
	pb.show_percentage = show_text
	pb.custom_minimum_size = Vector2(float(width), 10.0)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("background", style_box(p.header, 2))
	pb.add_theme_stylebox_override("fill", style_box(tint_for_rating(value), 2))
	return pb


## Red -> amber -> green across 0..1. One ramp for every quality reading in the
## mode, so a bar always means the same thing.
static func tint_for_rating(value: float) -> Color:
	var p: CareerThemePalette = palette()
	var v: float = clampf(value, 0.0, 1.0)
	if v < 0.5:
		return p.attr_low.lerp(p.attr_mid, v / 0.5)
	return p.attr_mid.lerp(p.attr_high, (v - 0.5) / 0.5)


static func result_color(result_char: String) -> Color:
	var p: CareerThemePalette = palette()
	match result_char:
		"W":
			return p.result_win
		"L":
			return p.result_loss
		"D":
			return p.result_draw
		_:
			return p.text_muted


## The W/D/L strip shown beside a league row or on the hub.
static func form_strip(form: String) -> HBoxContainer:
	var p: CareerThemePalette = palette()
	var h: HBoxContainer = row(3)
	h.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for i: int in range(form.length()):
		var ch: String = form[i]
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", style_box(result_color(ch), 2))
		var inner := MarginContainer.new()
		inner.add_theme_constant_override("margin_left", 4)
		inner.add_theme_constant_override("margin_right", 4)
		inner.add_theme_constant_override("margin_top", 1)
		inner.add_theme_constant_override("margin_bottom", 1)
		pill.add_child(inner)
		inner.add_child(label(ch, p.text_on_accent, p.font_size_small, HORIZONTAL_ALIGNMENT_CENTER))
		h.add_child(pill)
	return h


## Compact currency, shared with TransferMarket so every screen agrees.
static func money(amount: int) -> String:
	return TransferMarket.format_fee(amount)


## A scrollable vertical list that fills its parent — the shape almost every
## panel body wants.
static func scroll_list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


static func scroll_root(list_body: VBoxContainer) -> Control:
	var scroll: Node = list_body.get_parent()
	return (scroll if scroll != null else list_body) as Control


## Clears a container's children. Career panels rebuild rather than diff, which
## is fine at these list sizes and keeps refresh logic honest.
static func clear(node: Node) -> void:
	for child: Node in node.get_children():
		child.queue_free()


## --- Entity Links (FM-Style Universal Forwarding) ----------------------------

const DatabaseViewerScript: Resource = preload("res://ui/DatabaseViewer.gd")


## Interactive link button styled as a clean clickable label with hover/press glow.
static func link_button(
	text: String,
	width: int = 0,
	color: Color = Color(0, 0, 0, 0),
	align: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Button:
	var p: CareerThemePalette = palette()
	var b := Button.new()
	b.text = text
	b.alignment = align
	b.clip_text = true
	b.flat = true
	var font_color: Color = color if color.a > 0.0 else p.accent
	b.add_theme_color_override("font_color", font_color)
	b.add_theme_color_override("font_hover_color", p.positive)
	b.add_theme_color_override("font_pressed_color", p.accent_dim)
	b.add_theme_color_override("font_focus_color", p.positive)
	b.add_theme_font_size_override("font_size", p.font_size_body)
	var flat_box: StyleBoxFlat = style_box(Color(0, 0, 0, 0), 0)
	flat_box.content_margin_left = 0.0
	flat_box.content_margin_right = 0.0
	flat_box.content_margin_top = 0.0
	flat_box.content_margin_bottom = 0.0
	b.add_theme_stylebox_override("normal", flat_box)
	b.add_theme_stylebox_override("hover", flat_box)
	b.add_theme_stylebox_override("pressed", flat_box)
	b.add_theme_stylebox_override("focus", flat_box)
	if width > 0:
		b.custom_minimum_size = Vector2(float(width), 0.0)
	return b


static func team_link(team_val: Variant, width: int = 0, color: Color = Color(0, 0, 0, 0)) -> Button:
	var label_text: String = ""
	if team_val is TeamData:
		label_text = (team_val as TeamData).team_name
	elif team_val is String or team_val is StringName:
		label_text = str(team_val)
	elif team_val is int:
		var t: TeamData = DataLoader.get_team(int(team_val))
		label_text = t.team_name if t != null else "Club"
	var btn: Button = link_button(label_text, width, color)
	btn.pressed.connect(func() -> void:
		DatabaseViewerScript.call(&"inspect_team", team_val)
	)
	return btn


static func player_link(player_val: Variant, width: int = 0, color: Color = Color(0, 0, 0, 0)) -> Button:
	var label_text: String = ""
	if player_val is PlayerData:
		label_text = (player_val as PlayerData).player_name
	elif player_val is String or player_val is StringName:
		label_text = str(player_val)
	var btn: Button = link_button(label_text, width, color)
	btn.pressed.connect(func() -> void:
		DatabaseViewerScript.call(&"inspect_player", player_val)
	)
	return btn


static func referee_link(ref_val: Variant, width: int = 0, color: Color = Color(0, 0, 0, 0)) -> Button:
	var label_text: String = ""
	if ref_val is RefereeData:
		label_text = (ref_val as RefereeData).referee_name
	elif ref_val is Dictionary:
		label_text = str((ref_val as Dictionary).get("name", "Match Official"))
	elif ref_val is String or ref_val is StringName:
		label_text = str(ref_val)
	var btn: Button = link_button(label_text, width, color)
	btn.pressed.connect(func() -> void:
		DatabaseViewerScript.call(&"inspect_referee", ref_val)
	)
	return btn


static func staff_link(staff_val: Variant, width: int = 0, color: Color = Color(0, 0, 0, 0)) -> Button:
	var label_text: String = ""
	if staff_val is StaffData:
		label_text = (staff_val as StaffData).staff_name
	elif staff_val is ManagerData:
		label_text = (staff_val as ManagerData).manager_name
	elif staff_val is String or staff_val is StringName:
		label_text = str(staff_val)
	var btn: Button = link_button(label_text, width, color)
	btn.pressed.connect(func() -> void:
		DatabaseViewerScript.call(&"inspect_staff", staff_val)
	)
	return btn

