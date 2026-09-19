##
## TeamProfileView.gd
##
## Reusable UI component and view controller for inspecting club profiles.
## Binds club identity (name, short code, badge/colors) and encyclopedic
## Wikipedia extract history with null-safe BBCode formatting.
##
## Depends on: TeamData, CareerTheme (optional palette/styling).
## Exposes: populate_team(team: TeamData), history_label, team_name_label, short_code_label.
##

class_name TeamProfileView
extends PanelContainer

@export var show_header: bool = true

var team_name_label: Label = null
var short_code_label: Label = null
var badge_rect: TextureRect = null
var section_title_label: RichTextLabel = null
var history_scroll: ScrollContainer = null
var history_label: RichTextLabel = null

var _built: bool = false


func _ready() -> void:
	_ensure_nodes()


## Ensures child controls are created and wired whether instantiated via scene (.tscn)
## or dynamically in code via TeamProfileView.new().
func _ensure_nodes() -> void:
	if _built:
		return
	_built = true

	# Check if nodes were already declared in .tscn hierarchy
	team_name_label = get_node_or_null("Margin/VBox/Header/InfoBox/TeamName") as Label
	short_code_label = get_node_or_null("Margin/VBox/Header/InfoBox/ShortCode") as Label
	badge_rect = get_node_or_null("Margin/VBox/Header/Badge") as TextureRect
	section_title_label = get_node_or_null("Margin/VBox/SectionTitle") as RichTextLabel
	history_scroll = get_node_or_null("Margin/VBox/HistoryScroll") as ScrollContainer
	history_label = get_node_or_null("Margin/VBox/HistoryScroll/HistoryLabel") as RichTextLabel

	if history_label != null and team_name_label != null:
		_apply_rich_text_config()
		return

	# Otherwise build programmatically
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var palette: CareerThemePalette = CareerTheme.palette()
	add_theme_stylebox_override("panel", CareerTheme.style_box(palette.panel, palette.corner_radius))

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", palette.content_margin)
	margin.add_theme_constant_override("margin_right", palette.content_margin)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# --- Header: Badge, Club Name, Short Code ---
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)

	badge_rect = TextureRect.new()
	badge_rect.name = "Badge"
	badge_rect.custom_minimum_size = Vector2(40.0, 40.0)
	badge_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(badge_rect)

	var info_box := VBoxContainer.new()
	info_box.name = "InfoBox"
	info_box.add_theme_constant_override("separation", 2)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(info_box)

	team_name_label = Label.new()
	team_name_label.name = "TeamName"
	team_name_label.text = "Club Profile"
	team_name_label.add_theme_font_size_override("font_size", palette.font_size_heading)
	team_name_label.add_theme_color_override("font_color", palette.text_primary)
	info_box.add_child(team_name_label)

	short_code_label = Label.new()
	short_code_label.name = "ShortCode"
	short_code_label.text = ""
	short_code_label.add_theme_font_size_override("font_size", palette.font_size_small)
	short_code_label.add_theme_color_override("font_color", palette.text_secondary)
	info_box.add_child(short_code_label)

	# Divider line
	vbox.add_child(CareerTheme.divider())

	# --- Section Title ---
	section_title_label = RichTextLabel.new()
	section_title_label.name = "SectionTitle"
	section_title_label.bbcode_enabled = true
	section_title_label.text = "[b]Club Overview & History[/b]"
	section_title_label.fit_content = true
	section_title_label.scroll_active = false
	section_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_title_label.add_theme_font_size_override("normal_font_size", palette.font_size_body)
	section_title_label.add_theme_color_override("default_color", palette.accent)
	vbox.add_child(section_title_label)

	# --- History Scroll Container & RichTextLabel ---
	history_scroll = ScrollContainer.new()
	history_scroll.name = "HistoryScroll"
	history_scroll.custom_minimum_size = Vector2(0.0, 140.0)
	history_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	history_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(history_scroll)

	history_label = RichTextLabel.new()
	history_label.name = "HistoryLabel"
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_label.fit_content = true
	history_scroll.add_child(history_label)

	_apply_rich_text_config()


func _apply_rich_text_config() -> void:
	if history_label == null:
		return
	history_label.bbcode_enabled = true
	history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history_label.scroll_following = false
	var palette: CareerThemePalette = CareerTheme.palette()
	history_label.add_theme_font_size_override("normal_font_size", palette.font_size_body)
	history_label.add_theme_color_override("default_color", palette.text_secondary)


## Populates club identity and encyclopedic Wikipedia extract into the UI.
func populate_team(team: TeamData) -> void:
	_ensure_nodes()

	if team == null:
		if team_name_label != null:
			team_name_label.text = "No Club Loaded"
		if short_code_label != null:
			short_code_label.text = ""
		if history_label != null:
			history_label.text = "[color=#888888][i]No historical extract available for this club.[/i][/color]"
		return

	if team_name_label != null:
		team_name_label.text = team.team_name
	if short_code_label != null:
		var sc: String = team.short_code.strip_edges()
		if sc.is_empty():
			sc = team.team_name.left(3).to_upper()
		short_code_label.text = "%s · Founded %d · %s" % [sc, team.founded_year, team.stature]

	_update_badge(team)

	if team.wikipedia_extract.strip_edges().is_empty():
		history_label.text = "[color=#888888][i]No historical extract available for this club.[/i][/color]"
	else:
		history_label.text = team.wikipedia_extract


func _update_badge(team: TeamData) -> void:
	if badge_rect == null:
		return

	if not team.logo_url.is_empty() and ResourceLoader.exists(team.logo_url):
		badge_rect.texture = load(team.logo_url) as Texture2D
		badge_rect.modulate = Color.WHITE
	else:
		# Fallback: create dynamic placeholder texture with team color
		var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(team.team_color)
		badge_rect.texture = ImageTexture.create_from_image(img)
		badge_rect.modulate = Color.WHITE
