class_name PauseButton
extends Control
## Small round button at the top right, left of the eye: pauses the game and opens the pause menu
## (the player asked; Esc or P on a PC). Two bars drawn in code. Emits `pressed`.

signal pressed

const RADIUS := 36.0
const MARGIN := 40.0
const GAP := 18.0

var _finger := -1
var _down := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func center() -> Vector2:
	return Vector2(get_viewport_rect().size.x - MARGIN - RADIUS * 3.0 - GAP, MARGIN + RADIUS)   # left of the eye


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and event.position.distance_to(center()) <= RADIUS * 1.2:
			_finger = event.index
			_down = true
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			_finger = -1
			_down = false
			queue_redraw()
			pressed.emit()


func _draw() -> void:
	var c := center()
	draw_circle(c, RADIUS * (0.92 if _down else 1.0), Color(1, 1, 1, 0.25))
	draw_arc(c, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.55), 3.0, true)
	var ink := Color("#3b4a5e", 0.85)
	for s in [-1.0, 1.0]:
		draw_rect(Rect2(c + Vector2(s * RADIUS * 0.22 - RADIUS * 0.09, -RADIUS * 0.32), Vector2(RADIUS * 0.18, RADIUS * 0.64)), ink)
