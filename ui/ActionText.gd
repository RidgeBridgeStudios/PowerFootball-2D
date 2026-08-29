##
## ActionText
##
## Short-lived floating world-space label. Spawned by show_action_text() on
## HeavyPlayerController. Lives in world space so it scales with camera zoom.
## Rises upward, fades out over ~0.9 s, then frees itself.
##

class_name ActionText
extends Node2D

@export var rise_distance: float = 20.0
@export var lifetime: float = 0.9

@onready var label: Label = $Label


func show_text(message: String) -> void:
	label.text = message.to_upper()

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	position.x += rng.randf_range(-6.0, 6.0)

	var end_pos: Vector2 = position + Vector2(0.0, -rise_distance)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", end_pos, lifetime)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, lifetime)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(queue_free)
