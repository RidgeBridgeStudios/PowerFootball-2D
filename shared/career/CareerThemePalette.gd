##
## CareerThemePalette
##
## The Manager Mode colour and metric palette, as a saveable Resource.
##
## Exists so that no career-mode script ever writes a literal Color. Panels ask
## CareerTheme for a semantic role ("accent", "danger", "row_alt") and the
## values come from ui/manager_mode/manager_mode_theme.tres, which can be
## re-skinned without touching a line of GDScript.
##
## Depends on: nothing.
## Exposes: the exported fields below.
##

class_name CareerThemePalette
extends Resource

## --- Surfaces -------------------------------------------------------------------
## Darkest layer: the sidebar and the window behind everything.
@export var sidebar: Color = Color(0.055, 0.071, 0.094)
## The main content pane.
@export var surface: Color = Color(0.086, 0.106, 0.137)
## Cards and panels sitting on the content pane.
@export var panel: Color = Color(0.114, 0.141, 0.180)
## Header strips inside a panel.
@export var header: Color = Color(0.145, 0.180, 0.227)
## Alternating data row tint, laid over `panel`.
@export var row_alt: Color = Color(1.0, 1.0, 1.0, 0.028)
## Row under the pointer / selected.
@export var row_hover: Color = Color(0.24, 0.86, 0.41, 0.10)
@export var divider: Color = Color(1.0, 1.0, 1.0, 0.085)

## --- Text ------------------------------------------------------------------------
@export var text_primary: Color = Color(0.910, 0.941, 0.914)
@export var text_secondary: Color = Color(0.639, 0.678, 0.722)
@export var text_muted: Color = Color(0.427, 0.463, 0.510)
@export var text_on_accent: Color = Color(0.043, 0.059, 0.078)

## --- Semantic --------------------------------------------------------------------
## The green the rest of the game already uses for focus and emphasis.
@export var accent: Color = Color(0.24, 0.86, 0.41)
@export var accent_dim: Color = Color(0.24, 0.86, 0.41, 0.16)
@export var positive: Color = Color(0.30, 0.82, 0.42)
@export var warning: Color = Color(0.94, 0.76, 0.30)
@export var danger: Color = Color(0.90, 0.32, 0.32)
@export var info: Color = Color(0.36, 0.66, 0.95)

## Result colours for form strips and results tables.
@export var result_win: Color = Color(0.24, 0.78, 0.42)
@export var result_draw: Color = Color(0.62, 0.65, 0.68)
@export var result_loss: Color = Color(0.86, 0.34, 0.34)

## Attribute bar gradient endpoints (poor -> excellent).
@export var attr_low: Color = Color(0.86, 0.34, 0.34)
@export var attr_mid: Color = Color(0.94, 0.76, 0.30)
@export var attr_high: Color = Color(0.30, 0.82, 0.42)

## --- Metrics -----------------------------------------------------------------------
@export var font_size_title: int = 22
@export var font_size_heading: int = 16
@export var font_size_body: int = 13
@export var font_size_small: int = 11
@export var corner_radius: int = 4
@export var row_height: int = 26
@export var sidebar_width: int = 186
@export var content_margin: int = 14

## --- Compatibility Aliases ----------------------------------------------------
var background_card: Color:
	get:
		return panel
var background_panel: Color:
	get:
		return header
var border: Color:
	get:
		return divider

