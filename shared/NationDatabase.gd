##
## NationDatabase
##
## Central registry and UI factory for real-world nationalities, spoken languages, and nation flags.
## Provides runtime Texture2D flag caching, unicode emoji fallbacks, language-to-nation
## resolvers, and standard Football Manager-styled nationality & language badges.
##
## Depends on: art/flags/*.png
## Exposes: get_flag_texture, get_flag_emoji, get_flag_key, create_flag_rect,
##          create_nationality_badge, create_language_badge
##

class_name NationDatabase
extends RefCounted

const FLAG_DIR: String = "res://art/flags/"

const NATION_KEYS: Dictionary = {
	"norway": "norway",
	"norwegian": "norway",
	"sweden": "sweden",
	"swedish": "sweden",
	"denmark": "denmark",
	"danish": "denmark",
	"spain": "spain",
	"spanish": "spain",
	"france": "france",
	"french": "france",
	"germany": "germany",
	"german": "germany",
	"italy": "italy",
	"italian": "italy",
	"scotland": "scotland",
	"scottish": "scotland",
	"england": "england",
	"english": "england",
	"britain": "england",
	"british": "england",
	"portugal": "portugal",
	"portuguese": "portugal",
	"croatia": "croatia",
	"croatian": "croatia",
	"switzerland": "switzerland",
	"swiss": "switzerland",
	"netherlands": "netherlands",
	"dutch": "netherlands",
	"belgium": "belgium",
	"belgian": "belgium",
	"poland": "poland",
	"polish": "poland",
	"argentina": "argentina",
	"argentine": "argentina",
	"brazil": "brazil",
	"brazilian": "brazil",
	"austria": "austria",
	"austrian": "austria",
	"ireland": "ireland",
	"irish": "ireland",
	"japan": "japan",
	"japanese": "japan",
	"usa": "usa",
	"american": "usa",
	"united states": "usa",
	"turkey": "turkey",
	"turkish": "turkey",
	"russia": "russia",
	"russian": "russia",
	"mexico": "mexico",
	"mexican": "mexico"
}

const FLAG_EMOJIS: Dictionary = {
	"norway": "🇳🇴",
	"sweden": "🇸🇪",
	"denmark": "🇩🇰",
	"spain": "🇪🇸",
	"france": "🇫🇷",
	"germany": "🇩🇪",
	"italy": "🇮🇹",
	"scotland": "🏴󠁧󠁢󠁳󠁣󠁴󠁿",
	"england": "🏴󠁧󠁢󠁥󠁮󠁧󠁿",
	"portugal": "🇵🇹",
	"croatia": "🇭🇷",
	"switzerland": "🇨🇭",
	"netherlands": "🇳🇱",
	"belgium": "🇧🇪",
	"poland": "🇵🇱",
	"argentina": "🇦🇷",
	"brazil": "🇧🇷",
	"austria": "🇦🇹",
	"ireland": "🇮🇪",
	"japan": "🇯🇵",
	"usa": "🇺🇸",
	"turkey": "🇹🇷",
	"russia": "🇷🇺",
	"mexico": "🇲🇽",
	"default": "🌐"
}

const PRIMARY_LANGUAGES: Dictionary = {
	"norway": "Norwegian",
	"sweden": "Swedish",
	"denmark": "Danish",
	"spain": "Spanish",
	"france": "French",
	"germany": "German",
	"italy": "Italian",
	"scotland": "English",
	"england": "English",
	"portugal": "Portuguese",
	"croatia": "Croatian",
	"switzerland": "German",
	"netherlands": "Dutch",
	"belgium": "Dutch",
	"poland": "Polish",
	"argentina": "Spanish",
	"brazil": "Portuguese",
	"austria": "German",
	"ireland": "English",
	"japan": "Japanese",
	"usa": "English",
	"turkey": "Turkish",
	"russia": "Russian",
	"mexico": "Spanish"
}

static var _texture_cache: Dictionary = {}


## Resolves any nationality or language string into a normalized flag key.
static func get_flag_key(identifier: String) -> String:
	var clean: String = identifier.strip_edges().to_lower()
	if NATION_KEYS.has(clean):
		return NATION_KEYS[clean]
	return "default"


## Returns a cached Texture2D for the nation or language.
static func get_flag_texture(identifier: String) -> Texture2D:
	var key: String = get_flag_key(identifier)
	if _texture_cache.has(key):
		return _texture_cache[key] as Texture2D

	var path: String = "%s%s.png" % [FLAG_DIR, key]
	var tex: Texture2D = null

	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			tex = res as Texture2D

	if tex == null:
		var global_path: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(global_path):
			var img := Image.new()
			var err: int = img.load(global_path)
			if err == OK:
				tex = ImageTexture.create_from_image(img)

	if tex == null and key != "default":
		return get_flag_texture("default")

	_texture_cache[key] = tex
	return tex


## Returns a unicode flag emoji as a fallback or inline text character.
static func get_flag_emoji(identifier: String) -> String:
	var key: String = get_flag_key(identifier)
	return FLAG_EMOJIS.get(key, "🌐")


## Alias for get_flag_emoji
static func get_emoji_for_nation(identifier: String) -> String:
	return get_flag_emoji(identifier)


## Returns the official or predominant national language for a nationality.
static func get_primary_language_for_nation(nationality: String) -> String:
	var key: String = get_flag_key(nationality)
	return PRIMARY_LANGUAGES.get(key, "English")


## Returns true if both nationalities are non-empty and map to the same normalized flag key.
static func share_nationality(nat_a: String, nat_b: String) -> bool:
	if nat_a == "" or nat_b == "":
		return false
	var k_a: String = get_flag_key(nat_a)
	var k_b: String = get_flag_key(nat_b)
	return k_a == k_b and k_a != "default"


## Returns true if both nationalities map to the same primary language.
static func share_language(nat_a: String, nat_b: String) -> bool:
	if nat_a == "" or nat_b == "":
		return false
	return get_primary_language_for_nation(nat_a) == get_primary_language_for_nation(nat_b)


## Creates a standalone flag TextureRect widget.
static func create_flag_rect(identifier: String, size: Vector2 = Vector2(24, 16)) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = get_flag_texture(identifier)
	tr.tooltip_text = identifier.capitalize()
	return tr


## Creates an HBoxContainer with flag icon + nationality label.
static func create_nationality_badge(nationality: String, show_text: bool = true, font_size: int = 13) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var flag_rect := create_flag_rect(nationality, Vector2(22, 15))
	box.add_child(flag_rect)

	if show_text and nationality != "":
		var lbl := Label.new()
		lbl.text = nationality
		lbl.add_theme_font_size_override("font_size", font_size)
		box.add_child(lbl)

	return box


## Creates a Football Manager-styled language badge pill with flag, language name,
## and proficiency tag with level-specific color styling.
static func create_language_badge(language: String, level: String, proficiency: float = 1.0, font_size: int = 11) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0

	var accent_color: Color = Color(0.3, 0.85, 1.0) # Native / Cyan
	match level.to_lower():
		"native":
			accent_color = Color(0.95, 0.78, 0.25) # Gold
			style.bg_color = Color(0.20, 0.17, 0.08, 0.9)
			style.border_color = Color(0.85, 0.70, 0.20, 0.6)
		"fluent":
			accent_color = Color(0.25, 0.85, 0.45) # Emerald Green
			style.bg_color = Color(0.08, 0.18, 0.12, 0.9)
			style.border_color = Color(0.25, 0.75, 0.40, 0.6)
		"basic":
			accent_color = Color(1.0, 0.65, 0.20) # Amber
			style.bg_color = Color(0.18, 0.12, 0.08, 0.9)
			style.border_color = Color(0.85, 0.55, 0.20, 0.6)
		_: # Rudimentary / Learning
			accent_color = Color(0.70, 0.75, 0.70) # Silver Gray
			style.bg_color = Color(0.12, 0.14, 0.12, 0.9)
			style.border_color = Color(0.50, 0.55, 0.50, 0.5)

	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	panel.add_child(hbox)

	var flag_rect := create_flag_rect(language, Vector2(18, 12))
	hbox.add_child(flag_rect)

	var text_lbl := Label.new()
	var prof_pct: int = int(round(proficiency * 100.0))
	text_lbl.text = "%s (%s)" % [language, level]
	text_lbl.add_theme_font_size_override("font_size", font_size)
	text_lbl.add_theme_color_override("font_color", accent_color)
	hbox.add_child(text_lbl)

	panel.tooltip_text = "%s: %s (%d%% proficiency)" % [language, level, prof_pct]
	return panel
