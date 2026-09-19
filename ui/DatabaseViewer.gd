##
## DatabaseViewer.gd
##
## Interactive encyclopedic browser for the PowerFootball master database.
## Displays all competitions (domestic leagues, continental cups, domestic cups),
## clubs, squad rosters, Wikipedia extracts, managers, backroom staff,
## referees, and venues. Accessible directly from the main menu.
##
## Depends on: DatabaseManager, DataLoader, ManagerLoader, StaffLoader,
##             RefereeLoader, TeamData, PlayerData, CareerTheme.
## Exposes: open(), close(), viewer_closed signal.
##

extends Control

signal viewer_closed

enum ActiveTab { COMPETITIONS = 0, CLUBS = 1, REFEREES = 2, PLAYERS = 3 }
enum ClubSubTab { OVERVIEW = 0, ROSTER = 1, STAFF = 2 }

const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)
const BG_DARK: Color = Color(0.045, 0.052, 0.045, 1.0)
const PANEL_BG: Color = Color(0.075, 0.088, 0.075, 0.95)
const CARD_BG: Color = Color(0.10, 0.12, 0.10, 0.9)
const BORDER_COLOR: Color = Color(0.18, 0.24, 0.19, 1.0)

var _active_tab: ActiveTab = ActiveTab.COMPETITIONS
var _active_club_subtab: ClubSubTab = ClubSubTab.OVERVIEW

var _search_input: LineEdit = null
var _filter_opt: OptionButton = null
var _gender_opt: OptionButton = null
var _count_label: Label = null
var _list_container: VBoxContainer = null
var _detail_container: VBoxContainer = null

var _tab_btn_competitions: Button = null
var _tab_btn_clubs: Button = null
var _tab_btn_referees: Button = null
var _tab_btn_players: Button = null

# Cached data models
var _all_competitions: Array[Dictionary] = []
var _filtered_competitions: Array[Dictionary] = []
var _selected_competition: Dictionary = {}

var _filtered_teams: Array[TeamData] = []
var _selected_team: TeamData = null
var _selected_team_id: int = 0
var _selected_player: PlayerData = null

var _filtered_referees: Array[Dictionary] = []
var _selected_referee: Dictionary = {}

var _filtered_players: Array[PlayerData] = []

var _built: bool = false

static var _active_instance: Control = null


static func get_or_create(parent: Node = null) -> Control:
	if _active_instance != null and is_instance_valid(_active_instance):
		return _active_instance
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var scene: PackedScene = preload("res://ui/DatabaseViewer.tscn")
	var viewer: Control = scene.instantiate() as Control
	viewer.top_level = true
	viewer.z_index = 200
	if parent != null and is_instance_valid(parent):
		parent.add_child(viewer)
	else:
		tree.root.add_child(viewer)
	_active_instance = viewer
	return viewer


static func inspect_team(team_val: Variant) -> void:
	var v: Control = get_or_create()
	if v != null and v.has_method(&"open_team"):
		v.call(&"open_team", team_val)


static func inspect_player(player_val: Variant) -> void:
	var v: Control = get_or_create()
	if v != null and v.has_method(&"open_player"):
		v.call(&"open_player", player_val)


static func inspect_referee(ref_val: Variant) -> void:
	var v: Control = get_or_create()
	if v != null and v.has_method(&"open_referee"):
		v.call(&"open_referee", ref_val)


static func inspect_staff(staff_val: Variant) -> void:
	var v: Control = get_or_create()
	if v != null and v.has_method(&"open_staff"):
		v.call(&"open_staff", staff_val)


static func inspect_competition(comp_val: Variant) -> void:
	var v: Control = get_or_create()
	if v != null and v.has_method(&"open_competition"):
		v.call(&"open_competition", comp_val)


func _ready() -> void:
	_active_instance = self
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_competitions()
	_select_tab(ActiveTab.COMPETITIONS)


## Opens and refreshes viewer state.
func open() -> void:
	show()
	if not _built:
		_build_ui()
	_refresh_active_tab()


## Opens the viewer focused directly on a club.
func open_team(team_val: Variant) -> void:
	var target_team: TeamData = null
	if team_val is TeamData:
		target_team = team_val as TeamData
	elif team_val is int:
		target_team = DataLoader.get_team(int(team_val))
	elif team_val is String or team_val is StringName:
		target_team = DataLoader.get_team_by_name(str(team_val))
	if target_team == null:
		open()
		return
	open()
	_jump_to_team(target_team)


## Opens the viewer focused directly on a player.
func open_player(player_val: Variant) -> void:
	var target_player: PlayerData = null
	if player_val is PlayerData:
		target_player = player_val as PlayerData
	elif player_val is String or player_val is StringName:
		var pname: String = str(player_val).to_lower().strip_edges()
		if DataLoader.league != null:
			for t: TeamData in DataLoader.league.teams:
				for p: PlayerData in t.squad:
					if p.player_name.to_lower() == pname:
						target_player = p
						break
				if target_player != null:
					break
	if target_player == null:
		open()
		_select_tab(ActiveTab.PLAYERS)
		return
	open()
	_select_tab(ActiveTab.PLAYERS)
	_render_player_detail(target_player)


## Opens the viewer focused directly on a referee.
func open_referee(ref_val: Variant) -> void:
	var ref_dict: Dictionary = {}
	if ref_val is Dictionary:
		ref_dict = ref_val as Dictionary
	elif ref_val is RefereeData:
		var r: RefereeData = ref_val as RefereeData
		ref_dict = {
			"name": r.referee_name,
			"nationality": r.nationality,
			"experience": r.experience,
			"strictness": r.strictness,
			"consistency": r.consistency,
			"composure": r.composure,
			"unprofessionalism": r.unprofessionalism,
			"incoherence": r.incoherence,
			"reputation": r.reputation,
			"respect_rating": r.respect_rating,
			"matches_officiated": r.matches_officiated,
			"fouls_awarded": r.fouls_awarded,
			"penalties_awarded": r.penalties_awarded,
			"red_cards_issued": r.red_cards_issued,
		}
	elif ref_val is String or ref_val is StringName:
		var rname: String = str(ref_val).to_lower().strip_edges()
		for ref: RefereeData in RefereeLoader.referee_pool:
			if ref.referee_name.to_lower() == rname:
				ref_dict = {
					"name": ref.referee_name,
					"nationality": ref.nationality,
					"experience": ref.experience,
					"strictness": ref.strictness,
					"consistency": ref.consistency,
					"composure": ref.composure,
					"unprofessionalism": ref.unprofessionalism,
					"incoherence": ref.incoherence,
					"reputation": ref.reputation,
					"respect_rating": ref.respect_rating,
					"matches_officiated": ref.matches_officiated,
					"fouls_awarded": ref.fouls_awarded,
					"penalties_awarded": ref.penalties_awarded,
					"red_cards_issued": ref.red_cards_issued,
				}
				break
	if ref_dict.is_empty():
		open()
		_select_tab(ActiveTab.REFEREES)
		return
	open()
	_select_tab(ActiveTab.REFEREES)
	_render_referee_detail(ref_dict)


## Opens the viewer focused on a staff member or manager.
func open_staff(staff_val: Variant) -> void:
	var team_found: TeamData = null
	if staff_val is ManagerData:
		var mgr: ManagerData = staff_val as ManagerData
		if DataLoader.league != null:
			for t: TeamData in DataLoader.league.teams:
				var m: ManagerData = ManagerLoader.get_manager_for_team(t.team_name)
				if m != null and m.manager_name == mgr.manager_name:
					team_found = t
					break
	elif staff_val is StaffData:
		var s: StaffData = staff_val as StaffData
		if DataLoader.league != null:
			for t: TeamData in DataLoader.league.teams:
				if t.staff.has(s):
					team_found = t
					break
	elif staff_val is String or staff_val is StringName:
		var sname: String = str(staff_val).to_lower().strip_edges()
		if DataLoader.league != null:
			for t: TeamData in DataLoader.league.teams:
				var tm: ManagerData = ManagerLoader.get_manager_for_team(t.team_name)
				if tm != null and tm.manager_name.to_lower() == sname:
					team_found = t
					break
				for st: StaffData in t.staff:
					if st.staff_name.to_lower() == sname:
						team_found = t
						break
				if team_found != null:
					break
	if team_found != null:
		open_team(team_found)
		_active_club_subtab = ClubSubTab.STAFF
		_render_club_detail(team_found)
		return
	open()
	_select_tab(ActiveTab.CLUBS)


## Opens the viewer focused on a competition.
func open_competition(comp_val: Variant) -> void:
	open()
	_select_tab(ActiveTab.COMPETITIONS)
	if comp_val is Dictionary:
		_render_competition_detail(comp_val as Dictionary)


## Closes the viewer and emits viewer_closed.
func close() -> void:
	hide()
	viewer_closed.emit()


func _build_ui() -> void:
	if _built:
		return
	_built = true

	var bg := ColorRect.new()
	bg.color = BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# --- Top Header Bar ---
	var header_panel := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.06, 0.075, 0.06, 1.0)
	header_style.border_color = BORDER_COLOR
	header_style.set_border_width_all(1)
	header_style.content_margin_left = 18.0
	header_style.content_margin_right = 18.0
	header_style.content_margin_top = 10.0
	header_style.content_margin_bottom = 10.0
	header_panel.add_theme_stylebox_override("panel", header_style)
	main_vbox.add_child(header_panel)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 14)
	header_panel.add_child(header_row)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 1)
	header_row.add_child(title_box)

	var title_lbl := Label.new()
	title_lbl.text = "🗄️ DATABASE & ROSTER VIEWER"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	title_box.add_child(title_lbl)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "Encyclopedic Football Simulation Master Archive"
	subtitle_lbl.add_theme_font_size_override("font_size", 11)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.65))
	title_box.add_child(subtitle_lbl)

	header_row.add_spacer(false)

	# Tab navigation buttons
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 6)
	header_row.add_child(tabs_row)

	_tab_btn_competitions = _create_tab_button("🏆 Competitions", ActiveTab.COMPETITIONS)
	tabs_row.add_child(_tab_btn_competitions)

	_tab_btn_clubs = _create_tab_button("🛡️ Clubs & Rosters", ActiveTab.CLUBS)
	tabs_row.add_child(_tab_btn_clubs)

	_tab_btn_referees = _create_tab_button("⚖️ Referees", ActiveTab.REFEREES)
	tabs_row.add_child(_tab_btn_referees)

	_tab_btn_players = _create_tab_button("🔍 Player Directory", ActiveTab.PLAYERS)
	tabs_row.add_child(_tab_btn_players)

	header_row.add_spacer(false)

	# Gender toggle
	_gender_opt = OptionButton.new()
	_gender_opt.add_item("⚽ Men's Database", 0)
	_gender_opt.add_item("⚽ Women's Database", 1)
	_gender_opt.selected = 0 if DatabaseManager.get_game_mode() == "men" else 1
	var host: Control = self
	_gender_opt.item_selected.connect(func(idx: int) -> void:
		var mode: String = "men" if idx == 0 else "women"
		DatabaseManager.set_game_mode(mode)
		host._on_gender_changed()
	)
	header_row.add_child(_gender_opt)

	# Back button
	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(110.0, 32.0)
	back_btn.pressed.connect(func() -> void:
		host.close()
	)
	_style_button(back_btn, false)
	header_row.add_child(back_btn)

	# --- Main Split Content Body ---
	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 14)
	body_margin.add_theme_constant_override("margin_right", 14)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(body_margin)

	var split_hbox := HBoxContainer.new()
	split_hbox.add_theme_constant_override("separation", 12)
	split_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_child(split_hbox)

	# Left Browser Pane
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(340.0, 0.0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = PANEL_BG
	left_style.border_color = BORDER_COLOR
	left_style.set_border_width_all(1)
	left_style.set_corner_radius_all(6)
	left_style.content_margin_left = 12.0
	left_style.content_margin_right = 12.0
	left_style.content_margin_top = 10.0
	left_style.content_margin_bottom = 10.0
	left_panel.add_theme_stylebox_override("panel", left_style)
	split_hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)

	# Search row
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 6)
	left_vbox.add_child(search_row)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search..."
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.clear_button_enabled = true
	_search_input.text_changed.connect(func(_new_text: String) -> void:
		host._on_search_changed()
	)
	search_row.add_child(_search_input)

	# Filter OptionButton
	_filter_opt = OptionButton.new()
	_filter_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_opt.item_selected.connect(func(_idx: int) -> void:
		host._on_filter_changed()
	)
	left_vbox.add_child(_filter_opt)

	# Count summary
	_count_label = Label.new()
	_count_label.text = "Loading..."
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6))
	left_vbox.add_child(_count_label)

	# Scrollable Item List
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(list_scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_list_container)

	# Right Detail Pane
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = PANEL_BG
	right_style.border_color = BORDER_COLOR
	right_style.set_border_width_all(1)
	right_style.set_corner_radius_all(6)
	right_style.content_margin_left = 16.0
	right_style.content_margin_right = 16.0
	right_style.content_margin_top = 14.0
	right_style.content_margin_bottom = 14.0
	right_panel.add_theme_stylebox_override("panel", right_style)
	split_hbox.add_child(right_panel)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(detail_scroll)

	_detail_container = VBoxContainer.new()
	_detail_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_container.add_theme_constant_override("separation", 12)
	detail_scroll.add_child(_detail_container)


func _create_tab_button(text: String, tab: ActiveTab) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(130.0, 32.0)
	var host: Control = self
	btn.pressed.connect(func() -> void:
		host._select_tab(tab)
	)
	_style_button(btn, false)
	return btn


func _select_tab(tab: ActiveTab) -> void:
	_active_tab = tab
	_update_tab_button_styles()
	_search_input.clear()
	_detail_container.clear_children() if _detail_container.has_method(&"clear_children") else _clear_node_children(_detail_container)

	match tab:
		ActiveTab.COMPETITIONS:
			_search_input.placeholder_text = "Search competitions / leagues..."
			_setup_competition_filters()
			_populate_competitions_list()
		ActiveTab.CLUBS:
			_search_input.placeholder_text = "Search clubs by name / code..."
			_setup_club_filters()
			_populate_clubs_list()
		ActiveTab.REFEREES:
			_search_input.placeholder_text = "Search referees by name / nation..."
			_setup_referee_filters()
			_populate_referees_list()
		ActiveTab.PLAYERS:
			_search_input.placeholder_text = "Search players by name..."
			_setup_player_filters()
			_populate_players_list()


func _update_tab_button_styles() -> void:
	_style_button(_tab_btn_competitions, _active_tab == ActiveTab.COMPETITIONS)
	_style_button(_tab_btn_clubs, _active_tab == ActiveTab.CLUBS)
	_style_button(_tab_btn_referees, _active_tab == ActiveTab.REFEREES)
	_style_button(_tab_btn_players, _active_tab == ActiveTab.PLAYERS)


func _on_gender_changed() -> void:
	_load_competitions()
	_refresh_active_tab()


func _refresh_active_tab() -> void:
	_select_tab(_active_tab)


func _on_search_changed() -> void:
	match _active_tab:
		ActiveTab.COMPETITIONS:
			_populate_competitions_list()
		ActiveTab.CLUBS:
			_populate_clubs_list()
		ActiveTab.REFEREES:
			_populate_referees_list()
		ActiveTab.PLAYERS:
			_populate_players_list()


func _on_filter_changed() -> void:
	match _active_tab:
		ActiveTab.COMPETITIONS:
			_populate_competitions_list()
		ActiveTab.CLUBS:
			_populate_clubs_list()
		ActiveTab.REFEREES:
			_populate_referees_list()
		ActiveTab.PLAYERS:
			_populate_players_list()


## --- 1. COMPETITIONS & LEAGUES VIEW -----------------------------------------

func _load_competitions() -> void:
	if DatabaseManager.is_connected_to_db:
		_all_competitions = DatabaseManager.fetch_leagues()
	else:
		# Fallback to DataLoader
		_all_competitions.clear()
		if DataLoader.league != null:
			_all_competitions.append({
				"league_id": 1,
				"name": DataLoader.league.league_name,
				"competition_type": "DOMESTIC_LEAGUE",
				"country_code": "CUSTOM",
				"gender": "men",
			})


func _setup_competition_filters() -> void:
	_filter_opt.clear()
	_filter_opt.add_item("All Competitions", 0)
	_filter_opt.add_item("Domestic Leagues", 1)
	_filter_opt.add_item("Continental Cups", 2)
	_filter_opt.add_item("Domestic Cups", 3)
	_filter_opt.selected = 0


func _populate_competitions_list() -> void:
	_clear_node_children(_list_container)
	var search_term: String = _search_input.text.strip_edges().to_lower()
	var filter_idx: int = _filter_opt.selected

	_filtered_competitions.clear()
	for comp: Dictionary in _all_competitions:
		var cname: String = str(comp.get("name", "")).to_lower()
		var ctype: String = str(comp.get("competition_type", ""))

		if not search_term.is_empty() and not cname.contains(search_term):
			continue

		match filter_idx:
			1:
				if ctype != "DOMESTIC_LEAGUE":
					continue
			2:
				if ctype != "CONTINENTAL_CUP":
					continue
			3:
				if ctype != "DOMESTIC_CUP":
					continue

		_filtered_competitions.append(comp)

	_count_label.text = "Showing %d competitions" % _filtered_competitions.size()

	var host: Control = self
	for comp: Dictionary in _filtered_competitions:
		var btn := Button.new()
		var comp_name: String = str(comp.get("name", "Unknown Competition"))
		var comp_type: String = str(comp.get("competition_type", "DOMESTIC_LEAGUE"))
		var badge: String = "🏆"
		if comp_type == "CONTINENTAL_CUP":
			badge = "⭐"
		elif comp_type == "DOMESTIC_CUP":
			badge = "🛡️"

		btn.text = "%s %s" % [badge, comp_name]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0.0, 32.0)
		btn.clip_text = true

		var current_comp: Dictionary = comp
		btn.pressed.connect(func() -> void:
			host._render_competition_detail(current_comp)
		)
		_style_list_item(btn)
		_list_container.add_child(btn)

	if not _filtered_competitions.is_empty():
		_render_competition_detail(_filtered_competitions[0])
	else:
		_clear_node_children(_detail_container)
		_detail_container.add_child(_make_empty_notice("No competitions match your search filter."))


func _render_competition_detail(comp: Dictionary) -> void:
	_selected_competition = comp
	_clear_node_children(_detail_container)

	var cid: int = int(comp.get("league_id", 0))
	var cname: String = str(comp.get("name", "Unknown Competition"))
	var ctype: String = str(comp.get("competition_type", "DOMESTIC_LEAGUE"))
	var ccountry: String = str(comp.get("country_code", "N/A"))
	var cgender: String = str(comp.get("gender", "men")).capitalize()

	# Header Card
	var card := _make_card()
	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 6)
	card.add_child(card_vbox)

	var title := Label.new()
	title.text = cname
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", ACCENT_COLOR)
	card_vbox.add_child(title)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 12)
	card_vbox.add_child(meta_row)

	var type_label: String = ctype.replace("_", " ").capitalize()
	meta_row.add_child(_make_tag("Type: %s" % type_label, Color(0.3, 0.6, 0.9)))
	meta_row.add_child(_make_tag("Gender: %s" % cgender, Color(0.8, 0.4, 0.8)))
	if not ccountry.is_empty() and ccountry != "N/A":
		meta_row.add_child(_make_tag("Country Code: %s" % ccountry, Color(0.6, 0.7, 0.6)))

	_detail_container.add_child(card)

	# Participating Clubs Section
	var teams: Array[TeamData] = []
	if DatabaseManager.is_connected_to_db:
		teams = DatabaseManager.fetch_teams_in_competition(cid, ctype)
	elif DataLoader.league != null:
		teams = DataLoader.league.teams

	var teams_title := Label.new()
	teams_title.text = "Participating Clubs (%d)" % teams.size()
	teams_title.add_theme_font_size_override("font_size", 16)
	teams_title.add_theme_color_override("font_color", Color(0.9, 0.94, 0.9))
	_detail_container.add_child(teams_title)

	if teams.is_empty():
		_detail_container.add_child(_make_empty_notice("No participating clubs recorded for this competition."))
		return

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_detail_container.add_child(grid)

	var host: Control = self
	for t: TeamData in teams:
		var team_btn := Button.new()
		var sc: String = t.short_code.strip_edges()
		if sc.is_empty():
			sc = t.team_name.left(3).to_upper()
		team_btn.text = "🛡️ %s (%s) · %s" % [t.team_name, sc, t.stature]
		team_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		team_btn.custom_minimum_size = Vector2(360.0, 32.0)
		team_btn.clip_text = true

		var curr_team: TeamData = t
		team_btn.pressed.connect(func() -> void:
			host._jump_to_team(curr_team)
		)
		_style_list_item(team_btn)
		grid.add_child(team_btn)


func _jump_to_team(team: TeamData) -> void:
	_select_tab(ActiveTab.CLUBS)
	_selected_team = team
	_selected_team_id = team.team_id
	_render_club_detail(team)


## --- 2. CLUBS & ROSTERS VIEW -----------------------------------------------

func _setup_club_filters() -> void:
	_filter_opt.clear()
	_filter_opt.add_item("All Leagues / Competitions", 0)

	var idx: int = 1
	for comp: Dictionary in _all_competitions:
		var ctype: String = str(comp.get("competition_type", ""))
		if ctype == "DOMESTIC_LEAGUE":
			var cname: String = str(comp.get("name", "League"))
			var cid: int = int(comp.get("league_id", 0))
			_filter_opt.add_item(cname, cid)
			idx += 1
	_filter_opt.selected = 0


func _populate_clubs_list() -> void:
	_clear_node_children(_list_container)
	var search_term: String = _search_input.text.strip_edges()
	var selected_league_id: int = _filter_opt.get_selected_id()

	if DatabaseManager.is_connected_to_db:
		if search_term.is_empty() and selected_league_id == 0:
			# Default: show Premier League (ID 8) teams or top league teams
			_filtered_teams = DatabaseManager.fetch_teams_in_league(8)
			if _filtered_teams.is_empty():
				_filtered_teams = DatabaseManager.search_teams("", -1, "", 50)
		elif selected_league_id > 0 and search_term.is_empty():
			_filtered_teams = DatabaseManager.fetch_teams_in_league(selected_league_id)
		else:
			_filtered_teams = DatabaseManager.search_teams(search_term, selected_league_id if selected_league_id > 0 else -1, "", 60)
	elif DataLoader.league != null:
		_filtered_teams.clear()
		for t: TeamData in DataLoader.league.teams:
			if search_term.is_empty() or t.team_name.to_lower().contains(search_term.to_lower()):
				_filtered_teams.append(t)

	_count_label.text = "Showing %d clubs" % _filtered_teams.size()

	var host: Control = self
	for t: TeamData in _filtered_teams:
		var btn := Button.new()
		var sc: String = t.short_code.strip_edges()
		if sc.is_empty():
			sc = t.team_name.left(3).to_upper()
		btn.text = "🛡️ %s [%s]" % [t.team_name, sc]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0.0, 30.0)
		btn.clip_text = true

		var curr_t: TeamData = t
		btn.pressed.connect(func() -> void:
			host._selected_team = curr_t
			host._selected_team_id = curr_t.team_id
			host._render_club_detail(curr_t)
		)
		_style_list_item(btn)
		_list_container.add_child(btn)

	if _selected_team != null:
		_render_club_detail(_selected_team)
	elif not _filtered_teams.is_empty():
		_selected_team = _filtered_teams[0]
		_selected_team_id = _selected_team.team_id
		_render_club_detail(_selected_team)
	else:
		_clear_node_children(_detail_container)
		_detail_container.add_child(_make_empty_notice("No clubs match your query."))


func _render_club_detail(team: TeamData) -> void:
	_selected_team = team
	_clear_node_children(_detail_container)

	# Top Club Identity Card
	var header_card := _make_card()
	var h_vbox := VBoxContainer.new()
	h_vbox.add_theme_constant_override("separation", 6)
	header_card.add_child(h_vbox)

	var club_row := HBoxContainer.new()
	club_row.add_theme_constant_override("separation", 14)
	h_vbox.add_child(club_row)

	# Club Badge / Color Box
	var badge_rect := ColorRect.new()
	badge_rect.custom_minimum_size = Vector2(48.0, 48.0)
	badge_rect.color = team.team_color
	club_row.add_child(badge_rect)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 2)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	club_row.add_child(name_box)

	var name_lbl := Label.new()
	name_lbl.text = team.team_name
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	name_box.add_child(name_lbl)

	var sc: String = team.short_code.strip_edges()
	if sc.is_empty():
		sc = team.team_name.left(3).to_upper()
	var meta_lbl := Label.new()
	meta_lbl.text = "%s · Founded %d · %s" % [sc, team.founded_year, team.stature]
	meta_lbl.add_theme_font_size_override("font_size", 12)
	meta_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.7))
	name_box.add_child(meta_lbl)

	# Reputation Bar
	var rep_box := VBoxContainer.new()
	rep_box.add_theme_constant_override("separation", 2)
	club_row.add_child(rep_box)
	var rep_title := Label.new()
	rep_title.text = "Reputation: %d%%" % int(round(team.reputation * 100.0))
	rep_title.add_theme_font_size_override("font_size", 11)
	rep_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	rep_box.add_child(rep_title)
	var rep_bar := ProgressBar.new()
	rep_bar.custom_minimum_size = Vector2(100.0, 10.0)
	rep_bar.value = team.reputation * 100.0
	rep_bar.show_percentage = false
	rep_box.add_child(rep_bar)

	_detail_container.add_child(header_card)

	# Subtab Selector Buttons: [Overview & History | Squad Roster | Management & Staff]
	var subtab_row := HBoxContainer.new()
	subtab_row.add_theme_constant_override("separation", 8)
	_detail_container.add_child(subtab_row)

	var host: Control = self
	var btn_overview := Button.new()
	btn_overview.text = "📜 Overview & History"
	btn_overview.custom_minimum_size = Vector2(160.0, 30.0)
	btn_overview.pressed.connect(func() -> void:
		host._active_club_subtab = ClubSubTab.OVERVIEW
		host._render_club_detail(team)
	)
	_style_button(btn_overview, _active_club_subtab == ClubSubTab.OVERVIEW)
	subtab_row.add_child(btn_overview)

	var btn_roster := Button.new()
	btn_roster.text = "👥 Squad Roster"
	btn_roster.custom_minimum_size = Vector2(160.0, 30.0)
	btn_roster.pressed.connect(func() -> void:
		host._active_club_subtab = ClubSubTab.ROSTER
		host._render_club_detail(team)
	)
	_style_button(btn_roster, _active_club_subtab == ClubSubTab.ROSTER)
	subtab_row.add_child(btn_roster)

	var btn_staff := Button.new()
	btn_staff.text = "👔 Management & Staff"
	btn_staff.custom_minimum_size = Vector2(160.0, 30.0)
	btn_staff.pressed.connect(func() -> void:
		host._active_club_subtab = ClubSubTab.STAFF
		host._render_club_detail(team)
	)
	_style_button(btn_staff, _active_club_subtab == ClubSubTab.STAFF)
	subtab_row.add_child(btn_staff)

	# Render active subtab
	match _active_club_subtab:
		ClubSubTab.OVERVIEW:
			_render_club_overview_tab(team)
		ClubSubTab.ROSTER:
			_render_club_roster_tab(team)
		ClubSubTab.STAFF:
			_render_club_staff_tab(team)


func _render_club_overview_tab(team: TeamData) -> void:
	# 1. Club Infrastructure & Venue
	var venue: Dictionary = {}
	if DatabaseManager.is_connected_to_db and team.venue_id > 0:
		venue = DatabaseManager.fetch_venue(team.venue_id)

	var info_grid := GridContainer.new()
	info_grid.columns = 2
	info_grid.add_theme_constant_override("h_separation", 16)
	info_grid.add_theme_constant_override("v_separation", 8)
	_detail_container.add_child(info_grid)

	# Venue Card
	var venue_card := _make_card()
	var v_box := VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 4)
	venue_card.add_child(v_box)
	v_box.add_child(_make_subheading("🏟️ Stadium & Venue"))

	var v_name: String = str(venue.get("name", "Local Ground"))
	var v_city: String = str(venue.get("city", "Home City"))
	var v_cap: int = int(venue.get("capacity", 25000))
	var v_surf: String = str(venue.get("surface_type", "grass")).capitalize()

	v_box.add_child(_make_kv_label("Stadium Name:", v_name))
	v_box.add_child(_make_kv_label("City:", v_city))
	v_box.add_child(_make_kv_label("Capacity:", "%s seats" % _format_number(v_cap)))
	v_box.add_child(_make_kv_label("Pitch Surface:", v_surf))
	info_grid.add_child(venue_card)

	# Finances & Facilities Card
	var fin_card := _make_card()
	var f_box := VBoxContainer.new()
	f_box.add_theme_constant_override("separation", 4)
	fin_card.add_child(f_box)
	f_box.add_child(_make_subheading("💼 Finances & Facilities"))

	f_box.add_child(_make_kv_label("Transfer Budget:", "£%s" % _format_number(team.transfer_budget)))
	f_box.add_child(_make_kv_label("Wage Budget / Wk:", "£%s" % _format_number(team.wage_budget_weekly)))
	f_box.add_child(_make_kv_label("Training Facilities:", "%d / 5 ★" % team.training_facilities))
	f_box.add_child(_make_kv_label("Youth Facilities:", "%d / 5 ★" % team.youth_facilities))
	f_box.add_child(_make_kv_label("Medical Facilities:", "%d / 5 ★" % team.medical_facilities))
	info_grid.add_child(fin_card)

	# 2. Club Rivals
	if DatabaseManager.is_connected_to_db and team.team_id > 0:
		var rivals: Array[Dictionary] = DatabaseManager.fetch_team_rivals_info(team.team_id)
		if not rivals.is_empty():
			var rival_card := _make_card()
			var r_box := VBoxContainer.new()
			r_box.add_theme_constant_override("separation", 4)
			rival_card.add_child(r_box)
			r_box.add_child(_make_subheading("⚔️ Known Club Rivals"))

			var rival_names: Array[String] = []
			for r: Dictionary in rivals:
				rival_names.append(str(r.get("name", "")))
			var r_lbl := Label.new()
			r_lbl.text = " · ".join(rival_names)
			r_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			r_lbl.add_theme_font_size_override("font_size", 12)
			r_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 0.6))
			r_box.add_child(r_lbl)
			_detail_container.add_child(rival_card)

	# 3. Wikipedia Extract History
	var wiki_card := _make_card()
	var w_box := VBoxContainer.new()
	w_box.add_theme_constant_override("separation", 6)
	wiki_card.add_child(w_box)
	w_box.add_child(_make_subheading("📖 Wikipedia Club History & Background"))

	var wiki_text: String = team.wikipedia_extract.strip_edges()
	var wiki_label := RichTextLabel.new()
	wiki_label.bbcode_enabled = true
	wiki_label.fit_content = true
	wiki_label.scroll_active = false
	wiki_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wiki_label.add_theme_font_size_override("normal_font_size", 13)
	wiki_label.add_theme_color_override("default_color", Color(0.85, 0.88, 0.85))

	if wiki_text.is_empty():
		wiki_label.text = "[color=#888888][i]No historical extract logged in database for this club.[/i][/color]"
	else:
		wiki_label.text = wiki_text

	w_box.add_child(wiki_label)
	_detail_container.add_child(wiki_card)


func _render_club_roster_tab(team: TeamData) -> void:
	var squad: Array[PlayerData] = []
	if DatabaseManager.is_connected_to_db and team.team_id > 0:
		squad = DatabaseManager.fetch_squad_roster(team.team_id)
	if squad.is_empty():
		squad = team.squad

	var count_lbl := Label.new()
	count_lbl.text = "First Team Squad (%d Players)" % squad.size()
	count_lbl.add_theme_font_size_override("font_size", 15)
	count_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	_detail_container.add_child(count_lbl)

	if squad.is_empty():
		_detail_container.add_child(_make_empty_notice("No squad members logged for this club."))
		return

	# Table Header Row
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 4)
	header_hbox.add_child(_make_cell("#", 30, true))
	header_hbox.add_child(_make_cell("Name", 180, true))
	header_hbox.add_child(_make_cell("Pos", 48, true))
	header_hbox.add_child(_make_cell("Nat", 90, true))
	header_hbox.add_child(_make_cell("Age", 45, true))
	header_hbox.add_child(_make_cell("Height", 55, true))
	header_hbox.add_child(_make_cell("Speed", 55, true))
	header_hbox.add_child(_make_cell("Stamina", 55, true))
	header_hbox.add_child(_make_cell("Vision", 55, true))
	header_hbox.add_child(_make_cell("Reflex", 55, true))
	_detail_container.add_child(header_hbox)

	var host: Control = self
	for p: PlayerData in squad:
		var row_btn := Button.new()
		row_btn.custom_minimum_size = Vector2(0.0, 26.0)
		row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_list_item(row_btn)

		var r_hbox := HBoxContainer.new()
		r_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		r_hbox.add_theme_constant_override("separation", 4)
		row_btn.add_child(r_hbox)

		r_hbox.add_child(_make_cell(str(p.shirt_number) if p.shirt_number > 0 else "-", 30))
		r_hbox.add_child(_make_cell(p.player_name, 180, false, Color(1, 1, 1)))
		r_hbox.add_child(_make_cell(p.position_role, 48, false, _pos_color(p.position_role)))
		r_hbox.add_child(_make_cell(p.nationality, 90))
		r_hbox.add_child(_make_cell(str(p.get_age()), 45))
		r_hbox.add_child(_make_cell("%d cm" % p.height_cm if p.height_cm > 0 else "-", 55))
		r_hbox.add_child(_make_cell("%d" % int(p.top_speed), 55))
		r_hbox.add_child(_make_cell("%d" % int(p.stamina_max), 55))
		r_hbox.add_child(_make_cell("%d%%" % int(p.vision * 100.0), 55))
		r_hbox.add_child(_make_cell("%d%%" % int(p.reflexes * 100.0), 55))

		var curr_p: PlayerData = p
		row_btn.pressed.connect(func() -> void:
			host._render_player_popup(curr_p)
		)
		_detail_container.add_child(row_btn)


func _render_club_staff_tab(team: TeamData) -> void:
	# 1. Head Coach / Manager
	var coach: Dictionary = {}
	if DatabaseManager.is_connected_to_db and team.team_id > 0:
		coach = DatabaseManager.fetch_coach(team.team_id)

	var mgr_data: ManagerData = ManagerLoader.get_manager_for_team(team.team_name)

	var coach_card := _make_card()
	var c_box := VBoxContainer.new()
	c_box.add_theme_constant_override("separation", 6)
	coach_card.add_child(c_box)
	c_box.add_child(_make_subheading("👔 Head Coach / Manager"))

	var coach_name: String = ""
	var coach_nat: String = ""
	var coach_formation: String = "4-3-3"
	var coach_exp: int = 30
	var coach_rep: float = 0.60
	var coach_press: float = 0.50
	var coach_line: float = 0.50

	if not coach.is_empty():
		coach_name = str(coach.get("common_name", coach.get("first_name", "") + " " + coach.get("last_name", "")))
		coach_nat = str(coach.get("nationality", "Unknown"))
		coach_formation = str(coach.get("preferred_formation", "4-3-3"))
		coach_exp = int(coach.get("experience", 30))
		coach_rep = float(coach.get("reputation", 0.60))
		coach_press = float(coach.get("pressing_intensity", 0.50))
		coach_line = float(coach.get("defensive_line", 0.50))
	elif mgr_data != null:
		coach_name = mgr_data.manager_name
		coach_nat = mgr_data.nationality
		coach_exp = mgr_data.experience
		coach_rep = mgr_data.reputation
		coach_press = mgr_data.pressing_intensity
		coach_line = mgr_data.defensive_line

	if coach_name.is_empty():
		coach_name = "Interim Coach"
		coach_nat = "Domestic"

	var c_grid := GridContainer.new()
	c_grid.columns = 2
	c_grid.add_theme_constant_override("h_separation", 24)
	c_grid.add_theme_constant_override("v_separation", 4)
	c_box.add_child(c_grid)

	c_grid.add_child(_make_kv_label("Manager Name:", coach_name, Color(1, 1, 1)))
	c_grid.add_child(_make_kv_label("Nationality:", coach_nat))
	c_grid.add_child(_make_kv_label("Preferred Formation:", coach_formation, ACCENT_COLOR))
	c_grid.add_child(_make_kv_label("Manager Experience:", "%d / 100" % coach_exp))
	c_grid.add_child(_make_kv_label("Tactical Reputation:", "%d%%" % int(coach_rep * 100.0)))
	c_grid.add_child(_make_kv_label("Pressing Intensity:", "%d%%" % int(coach_press * 100.0)))
	c_grid.add_child(_make_kv_label("Defensive Line Depth:", "%d%%" % int(coach_line * 100.0)))

	_detail_container.add_child(coach_card)

	# 2. Backroom Staff Directory
	var staff_rows: Array[Dictionary] = []
	if DatabaseManager.is_connected_to_db and team.team_id > 0:
		staff_rows = DatabaseManager.fetch_staff_for_team(team.team_id)

	var staff_card := _make_card()
	var s_box := VBoxContainer.new()
	s_box.add_theme_constant_override("separation", 6)
	staff_card.add_child(s_box)

	var staff_count: int = staff_rows.size() if not staff_rows.is_empty() else team.staff.size()
	s_box.add_child(_make_subheading("👥 Backroom Staff & Specialists (%d)" % staff_count))

	if staff_rows.is_empty() and team.staff.is_empty():
		s_box.add_child(_make_empty_notice("No backroom staff logged for this club."))
	elif not staff_rows.is_empty():
		for s_row: Dictionary in staff_rows:
			var s_line := HBoxContainer.new()
			s_line.add_theme_constant_override("separation", 10)
			s_box.add_child(s_line)

			var s_role: String = str(s_row.get("role", "Staff"))
			var s_name: String = str(s_row.get("staff_name", "Unknown"))
			var s_nat: String = str(s_row.get("nationality", "Unknown"))
			var s_coach_attr: float = float(s_row.get("coaching", 0.70))

			s_line.add_child(_make_cell(s_role, 170, true, ACCENT_COLOR))
			s_line.add_child(_make_cell(s_name, 160, false, Color(1, 1, 1)))
			s_line.add_child(_make_cell(s_nat, 90))
			s_line.add_child(_make_cell("Ability: %d%%" % int(s_coach_attr * 100.0), 90))
	else:
		for s_data: StaffData in team.staff:
			var fallback_line := HBoxContainer.new()
			fallback_line.add_theme_constant_override("separation", 10)
			s_box.add_child(fallback_line)

			fallback_line.add_child(_make_cell(s_data.role, 170, true, ACCENT_COLOR))
			fallback_line.add_child(_make_cell(s_data.staff_name, 160, false, Color(1, 1, 1)))
			fallback_line.add_child(_make_cell(s_data.nationality, 90))
			fallback_line.add_child(_make_cell("Ability: %d%%" % int(s_data.coaching * 100.0), 90))

	_detail_container.add_child(staff_card)


## --- 3. REFEREES VIEW -------------------------------------------------------

func _setup_referee_filters() -> void:
	_filter_opt.clear()
	_filter_opt.add_item("All Nationalities", 0)
	_filter_opt.add_item("English", 1)
	_filter_opt.add_item("Spanish", 2)
	_filter_opt.add_item("Italian", 3)
	_filter_opt.add_item("German", 4)
	_filter_opt.add_item("French", 5)
	_filter_opt.add_item("Norwegian", 6)
	_filter_opt.selected = 0


func _populate_referees_list() -> void:
	_clear_node_children(_list_container)
	var search_term: String = _search_input.text.strip_edges()
	var filter_text: String = _filter_opt.get_item_text(_filter_opt.selected)

	if DatabaseManager.is_connected_to_db:
		_filtered_referees = DatabaseManager.fetch_referees(search_term, 150)
	else:
		_filtered_referees.clear()
		for ref: RefereeData in RefereeLoader.referee_pool:
			if search_term.is_empty() or ref.referee_name.to_lower().contains(search_term.to_lower()):
				_filtered_referees.append({
					"name": ref.referee_name,
					"nationality": ref.nationality,
					"experience": ref.experience,
					"strictness": ref.strictness,
					"consistency": ref.consistency,
					"composure": ref.composure,
					"unprofessionalism": ref.unprofessionalism,
					"incoherence": ref.incoherence,
					"reputation": ref.reputation,
					"respect_rating": ref.respect_rating,
					"matches_officiated": ref.matches_officiated,
					"fouls_awarded": ref.fouls_awarded,
					"penalties_awarded": ref.penalties_awarded,
					"red_cards_issued": ref.red_cards_issued,
				})

	if _filter_opt.selected > 0:
		var filtered: Array[Dictionary] = []
		for r: Dictionary in _filtered_referees:
			var nat: String = str(r.get("nationality", ""))
			if nat.nocasecmp_to(filter_text) == 0:
				filtered.append(r)
		_filtered_referees = filtered

	_count_label.text = "Showing %d match officials" % _filtered_referees.size()

	var host: Control = self
	for r: Dictionary in _filtered_referees:
		var btn := Button.new()
		var r_name: String = str(r.get("name", "Official"))
		var r_nat: String = str(r.get("nationality", "Unknown"))
		var r_exp: int = int(r.get("experience", 20))
		btn.text = "⚖️ %s (%s) · Exp %d" % [r_name, r_nat, r_exp]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0.0, 30.0)
		btn.clip_text = true

		var curr_ref: Dictionary = r
		btn.pressed.connect(func() -> void:
			host._render_referee_detail(curr_ref)
		)
		_style_list_item(btn)
		_list_container.add_child(btn)

	if not _filtered_referees.is_empty():
		_render_referee_detail(_filtered_referees[0])
	else:
		_clear_node_children(_detail_container)
		_detail_container.add_child(_make_empty_notice("No referees match your query."))


func _render_referee_detail(ref: Dictionary) -> void:
	_selected_referee = ref
	_clear_node_children(_detail_container)

	var r_name: String = str(ref.get("name", "Match Official"))
	var r_nat: String = str(ref.get("nationality", "Unknown"))
	var r_sec_nat: String = str(ref.get("secondary_nationality", ""))
	var r_dob: String = str(ref.get("date_of_birth", ""))
	var r_exp: int = int(ref.get("experience", 20))
	var r_rep: float = float(ref.get("reputation", 0.50))
	var r_strict: float = float(ref.get("strictness", 0.50))
	var r_cons: float = float(ref.get("consistency", 0.50))
	var r_comp: float = float(ref.get("composure", 0.50))
	var r_unprof: float = float(ref.get("unprofessionalism", 0.05))
	var r_incoh: float = float(ref.get("incoherence", 0.05))
	var r_respect: float = float(ref.get("respect_rating", 0.50))

	var matches: int = int(ref.get("matches_officiated", 0))
	var fouls: int = int(ref.get("fouls_awarded", 0))
	var pens: int = int(ref.get("penalties_awarded", 0))
	var reds: int = int(ref.get("red_cards_issued", 0))

	# 1. Official Identity Card
	var id_card := _make_card()
	var id_box := VBoxContainer.new()
	id_box.add_theme_constant_override("separation", 6)
	id_card.add_child(id_box)

	var name_lbl := Label.new()
	name_lbl.text = "⚖️ %s" % r_name
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	id_box.add_child(name_lbl)

	var nat_str: String = r_nat
	if not r_sec_nat.is_empty():
		nat_str += " / " + r_sec_nat
	if not r_dob.is_empty():
		nat_str += " · Born: " + r_dob
	var sub_lbl := Label.new()
	sub_lbl.text = nat_str
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
	id_box.add_child(sub_lbl)
	_detail_container.add_child(id_card)

	# 2. Career Officiating Record Card
	var record_card := _make_card()
	var rec_box := VBoxContainer.new()
	rec_box.add_theme_constant_override("separation", 6)
	record_card.add_child(rec_box)
	rec_box.add_child(_make_subheading("📊 Career Match Record & Discipline"))

	var rec_grid := GridContainer.new()
	rec_grid.columns = 4
	rec_grid.add_theme_constant_override("h_separation", 20)
	rec_grid.add_theme_constant_override("v_separation", 6)
	rec_box.add_child(rec_grid)

	rec_grid.add_child(_make_stat_badge("Matches", str(matches)))
	rec_grid.add_child(_make_stat_badge("Fouls Awarded", str(fouls)))
	rec_grid.add_child(_make_stat_badge("Penalties", str(pens)))
	rec_grid.add_child(_make_stat_badge("Red Cards", str(reds)))
	_detail_container.add_child(record_card)

	# 3. Attributes & Psychological Profile Card
	var attr_card := _make_card()
	var a_box := VBoxContainer.new()
	a_box.add_theme_constant_override("separation", 6)
	attr_card.add_child(a_box)
	a_box.add_child(_make_subheading("🧠 Psychological & Competence Profile"))

	var a_grid := GridContainer.new()
	a_grid.columns = 2
	a_grid.add_theme_constant_override("h_separation", 24)
	a_grid.add_theme_constant_override("v_separation", 6)
	a_box.add_child(a_grid)

	a_grid.add_child(_make_attr_row("Experience Level:", float(r_exp) / 50.0, "%d / 50" % r_exp))
	a_grid.add_child(_make_attr_row("Strictness Rating:", r_strict, "%d%%" % int(r_strict * 100.0)))
	a_grid.add_child(_make_attr_row("Consistency:", r_cons, "%d%%" % int(r_cons * 100.0)))
	a_grid.add_child(_make_attr_row("Match Composure:", r_comp, "%d%%" % int(r_comp * 100.0)))
	a_grid.add_child(_make_attr_row("Reputation & Stature:", r_rep, "%d%%" % int(r_rep * 100.0)))
	a_grid.add_child(_make_attr_row("Respect from Players:", r_respect, "%d%%" % int(r_respect * 100.0)))
	a_grid.add_child(_make_attr_row("Unprofessionalism Risk:", r_unprof, "%d%%" % int(r_unprof * 100.0), Color(0.9, 0.4, 0.4)))
	a_grid.add_child(_make_attr_row("Incoherence Variance:", r_incoh, "%d%%" % int(r_incoh * 100.0), Color(0.9, 0.4, 0.4)))

	_detail_container.add_child(attr_card)


## --- 4. PLAYER DIRECTORY VIEW -----------------------------------------------

func _setup_player_filters() -> void:
	_filter_opt.clear()
	_filter_opt.add_item("All Positions", 0)
	_filter_opt.add_item("Goalkeepers (GK)", 1)
	_filter_opt.add_item("Defenders (CB/LB/RB)", 2)
	_filter_opt.add_item("Midfielders (CM/DM/AM)", 3)
	_filter_opt.add_item("Forwards (ST/LW/RW)", 4)
	_filter_opt.selected = 0


func _populate_players_list() -> void:
	_clear_node_children(_list_container)
	var search_term: String = _search_input.text.strip_edges()
	var pos_filter: String = ""
	match _filter_opt.selected:
		1:
			pos_filter = "GK"
		2:
			pos_filter = "CB"
		3:
			pos_filter = "CM"
		4:
			pos_filter = "ST"

	if DatabaseManager.is_connected_to_db:
		if search_term.is_empty():
			search_term = "A" # Seed search
		_filtered_players = DatabaseManager.search_players(search_term, pos_filter, "", 40)
	elif DataLoader.league != null:
		_filtered_players.clear()
		for t: TeamData in DataLoader.league.teams:
			for p: PlayerData in t.squad:
				if search_term.is_empty() or p.player_name.to_lower().contains(search_term.to_lower()):
					_filtered_players.append(p)
					if _filtered_players.size() >= 40:
						break
			if _filtered_players.size() >= 40:
				break

	_count_label.text = "Showing %d players" % _filtered_players.size()

	var host: Control = self
	for p: PlayerData in _filtered_players:
		var btn := Button.new()
		btn.text = "🏃 %s (%s) · %s" % [p.player_name, p.position_role, p.nationality]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0.0, 30.0)
		btn.clip_text = true

		var curr_p: PlayerData = p
		btn.pressed.connect(func() -> void:
			host._render_player_detail(curr_p)
		)
		_style_list_item(btn)
		_list_container.add_child(btn)

	if not _filtered_players.is_empty():
		_render_player_detail(_filtered_players[0])
	else:
		_clear_node_children(_detail_container)
		_detail_container.add_child(_make_empty_notice("No players found matching your query."))


func _render_player_detail(p: PlayerData) -> void:
	_selected_player = p
	_clear_node_children(_detail_container)

	# 1. Player Header Card
	var card := _make_card()
	var c_box := VBoxContainer.new()
	c_box.add_theme_constant_override("separation", 6)
	card.add_child(c_box)

	var p_row := HBoxContainer.new()
	p_row.add_theme_constant_override("separation", 14)
	c_box.add_child(p_row)

	var pos_badge := _make_tag(p.position_role, _pos_color(p.position_role))
	pos_badge.custom_minimum_size = Vector2(40.0, 40.0)
	p_row.add_child(pos_badge)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 2)
	p_row.add_child(name_box)

	var name_lbl := Label.new()
	name_lbl.text = p.player_name
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	name_box.add_child(name_lbl)

	var sub_str: String = "%s · %s" % [p.nationality, p.get_age_detail_string()]
	if p.shirt_number > 0:
		sub_str = "#%d · %s" % [p.shirt_number, sub_str]
	var sub_lbl := Label.new()
	sub_lbl.text = sub_str
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
	name_box.add_child(sub_lbl)

	# Clickable club link if player belongs to a club
	var player_team: TeamData = null
	if DataLoader.league != null:
		for t: TeamData in DataLoader.league.teams:
			if t.squad.has(p):
				player_team = t
				break
	if player_team != null:
		var club_btn := Button.new()
		club_btn.text = "🛡️ %s" % player_team.team_name
		club_btn.flat = true
		club_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		club_btn.add_theme_font_size_override("font_size", 12)
		club_btn.add_theme_color_override("font_color", ACCENT_COLOR)
		var host: Control = self
		var pt: TeamData = player_team
		club_btn.pressed.connect(func() -> void:
			host._jump_to_team(pt)
		)
		name_box.add_child(club_btn)

	_detail_container.add_child(card)

	# 2. Physical & Bio Metrics
	var phys_card := _make_card()
	var pb_box := VBoxContainer.new()
	pb_box.add_theme_constant_override("separation", 6)
	phys_card.add_child(pb_box)
	pb_box.add_child(_make_subheading("📏 Physical Profile & Measurements"))

	var pb_grid := GridContainer.new()
	pb_grid.columns = 3
	pb_grid.add_theme_constant_override("h_separation", 20)
	pb_grid.add_theme_constant_override("v_separation", 6)
	pb_box.add_child(pb_grid)

	pb_grid.add_child(_make_stat_badge("Height", "%d cm" % p.height_cm if p.height_cm > 0 else "182 cm"))
	pb_grid.add_child(_make_stat_badge("Weight", "%d kg" % p.weight_kg if p.weight_kg > 0 else "76 kg"))
	pb_grid.add_child(_make_stat_badge("Mass (Phys)", "%.1f kg" % p.mass))
	_detail_container.add_child(phys_card)

	# 3. Technical & Mental Attributes Card
	var attr_card := _make_card()
	var a_box := VBoxContainer.new()
	a_box.add_theme_constant_override("separation", 6)
	attr_card.add_child(a_box)
	a_box.add_child(_make_subheading("⚡ Technical & Mental Attributes"))

	var a_grid := GridContainer.new()
	a_grid.columns = 2
	a_grid.add_theme_constant_override("h_separation", 24)
	a_grid.add_theme_constant_override("v_separation", 6)
	a_box.add_child(a_grid)

	a_grid.add_child(_make_attr_row("Top Sprint Speed:", p.top_speed / 200.0, "%.0f px/s" % p.top_speed))
	a_grid.add_child(_make_attr_row("Stamina Max:", p.stamina_max / 120.0, "%.0f" % p.stamina_max))
	a_grid.add_child(_make_attr_row("Reflexes:", p.reflexes, "%d%%" % int(p.reflexes * 100.0)))
	a_grid.add_child(_make_attr_row("Vision:", p.vision, "%d%%" % int(p.vision * 100.0)))
	a_grid.add_child(_make_attr_row("Composure:", p.composure, "%d%%" % int(p.composure * 100.0)))
	a_grid.add_child(_make_attr_row("Close Ball Control:", p.close_control, "%d%%" % int(p.close_control * 100.0)))
	a_grid.add_child(_make_attr_row("Aggression:", p.aggression, "%d%%" % int(p.aggression * 100.0)))
	a_grid.add_child(_make_attr_row("Determination:", p.determination, "%d%%" % int(p.determination * 100.0)))
	a_grid.add_child(_make_attr_row("Work Rate:", p.work_rate, "%d%%" % int(p.work_rate * 100.0)))

	_detail_container.add_child(attr_card)


func _render_player_popup(p: PlayerData) -> void:
	_select_tab(ActiveTab.PLAYERS)
	_render_player_detail(p)


## --- UI HELPER & FACTORY METHODS -------------------------------------------

func _make_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_subheading(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	return lbl


func _make_kv_label(key: String, value: String, val_color: Color = Color(0.9, 0.9, 0.9)) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var k_lbl := Label.new()
	k_lbl.text = key
	k_lbl.custom_minimum_size = Vector2(140.0, 0.0)
	k_lbl.add_theme_font_size_override("font_size", 12)
	k_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.65))
	hbox.add_child(k_lbl)

	var v_lbl := Label.new()
	v_lbl.text = value
	v_lbl.add_theme_font_size_override("font_size", 12)
	v_lbl.add_theme_color_override("font_color", val_color)
	hbox.add_child(v_lbl)
	return hbox


func _make_cell(text: String, width: int, is_header: bool = false, col: Color = Color.TRANSPARENT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(float(width), 0.0)
	lbl.clip_text = true
	lbl.add_theme_font_size_override("font_size", 11)
	if is_header:
		lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	elif col != Color.TRANSPARENT:
		lbl.add_theme_color_override("font_color", col)
	else:
		lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.78))
	return lbl


func _make_tag(text: String, tag_color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = " %s " % text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", tag_color)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tag_color.r, tag_color.g, tag_color.b, 0.15)
	style.border_color = tag_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	lbl.add_theme_stylebox_override("normal", style)
	return lbl


func _make_stat_badge(title: String, val: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.06, 0.8)
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	t_lbl.add_theme_font_size_override("font_size", 10)
	t_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.65))
	vbox.add_child(t_lbl)

	var v_lbl := Label.new()
	v_lbl.text = val
	v_lbl.add_theme_font_size_override("font_size", 14)
	v_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	vbox.add_child(v_lbl)
	return panel


func _make_attr_row(title: String, ratio: float, val_text: String, bar_color: Color = Color.TRANSPARENT) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var t_lbl := Label.new()
	t_lbl.text = title
	t_lbl.custom_minimum_size = Vector2(140.0, 0.0)
	t_lbl.add_theme_font_size_override("font_size", 11)
	t_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
	hbox.add_child(t_lbl)

	var pbar := ProgressBar.new()
	pbar.custom_minimum_size = Vector2(90.0, 10.0)
	pbar.value = clampf(ratio * 100.0, 0.0, 100.0)
	pbar.show_percentage = false
	if bar_color != Color.TRANSPARENT:
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = bar_color
		pbar.add_theme_stylebox_override("fill", fill_style)
	hbox.add_child(pbar)

	var v_lbl := Label.new()
	v_lbl.text = val_text
	v_lbl.custom_minimum_size = Vector2(50.0, 0.0)
	v_lbl.add_theme_font_size_override("font_size", 11)
	v_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hbox.add_child(v_lbl)
	return hbox


func _make_empty_notice(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	return lbl


func _pos_color(pos: String) -> Color:
	match pos:
		"GK":
			return Color(0.9, 0.7, 0.2)
		"CB", "LB", "RB", "RWB", "LWB":
			return Color(0.3, 0.6, 0.9)
		"CM", "DM", "AM", "LM", "RM":
			return Color(0.24, 0.86, 0.41)
		"ST", "CF", "LW", "RW":
			return Color(0.9, 0.35, 0.35)
		_:
			return Color(0.8, 0.8, 0.8)


func _style_button(btn: Button, is_active: bool) -> void:
	var style := StyleBoxFlat.new()
	if is_active:
		style.bg_color = Color(0.24, 0.86, 0.41, 0.25)
		style.border_color = ACCENT_COLOR
		style.set_border_width_all(1)
	else:
		style.bg_color = Color(0.12, 0.14, 0.12, 0.8)
		style.border_color = BORDER_COLOR
		style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	btn.add_theme_stylebox_override("normal", style)


func _style_list_item(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.10, 0.08, 0.6)
	normal.border_color = Color(0.14, 0.18, 0.14, 0.6)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 6.0
	normal.content_margin_right = 6.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.24, 0.86, 0.41, 0.15)
	hover.border_color = ACCENT_COLOR
	btn.add_theme_stylebox_override("hover", hover)


func _format_number(n: int) -> String:
	var s: String = str(n)
	var res: String = ""
	var cnt: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = "," + res
	return res


func _clear_node_children(parent: Node) -> void:
	if parent == null:
		return
	for c: Node in parent.get_children():
		c.queue_free()
