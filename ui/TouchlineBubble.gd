##
## TouchlineBubble
##
## A brief speech-bubble popup showing a manager's touchline shout (goal,
## concession, tactical shift, half time). Anchors itself bottom-left for the
## home manager or bottom-right for the away manager, holds for a few seconds,
## then fades out.
##
## Depends on: nothing — driven entirely by show_shout() calls from PitchScene.
## Exposes: show_shout(manager_name, quote, is_home)
##

class_name TouchlineBubble
extends CanvasLayer

const DISPLAY_DURATION: float = 4.0
const FADE_DURATION: float = 0.5

@onready var bubble_panel: PanelContainer = $BubblePanel
@onready var manager_name_label: Label = $BubblePanel/VBoxContainer/ManagerNameLabel
@onready var quote_label: Label = $BubblePanel/VBoxContainer/QuoteLabel

var _hide_tween: Tween = null


func _ready() -> void:
	bubble_panel.visible = false


## Show a touchline shout. is_home: true = anchor bottom-left, false = anchor
## bottom-right.
func show_shout(manager_name: String, quote: String, is_home: bool) -> void:
	manager_name_label.text = manager_name + ":"
	quote_label.text = quote
	bubble_panel.visible = true
	bubble_panel.modulate.a = 1.0

	if is_home:
		bubble_panel.anchor_left = 0.0
		bubble_panel.anchor_right = 0.35
		bubble_panel.anchor_top = 0.78
		bubble_panel.anchor_bottom = 1.0
		bubble_panel.offset_left = 12
		bubble_panel.offset_right = 0
		bubble_panel.offset_top = 0
		bubble_panel.offset_bottom = -12
	else:
		bubble_panel.anchor_left = 0.65
		bubble_panel.anchor_right = 1.0
		bubble_panel.anchor_top = 0.78
		bubble_panel.anchor_bottom = 1.0
		bubble_panel.offset_left = 0
		bubble_panel.offset_right = -12
		bubble_panel.offset_top = 0
		bubble_panel.offset_bottom = -12
	bubble_panel.reset_size()

	if _hide_tween != null and _hide_tween.is_valid():
		_hide_tween.kill()

	_hide_tween = create_tween()
	_hide_tween.tween_interval(DISPLAY_DURATION)
	_hide_tween.tween_property(bubble_panel, &"modulate:a", 0.0, FADE_DURATION)
	_hide_tween.tween_callback(func() -> void: bubble_panel.visible = false)
