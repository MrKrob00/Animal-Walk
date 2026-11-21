class_name JumpButton
extends Control
## Round on-screen button left of the paw stick, at the bottom: the one you steer jumps (Space on
## a PC). An up-chevron over a little ground line, drawn in code. Emits `pressed`.

signal pressed

const RADIUS := 52.0
const GAP := 26.0

var _finger := -1
var _down := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func center() -> Vector2:
	var corner := get_viewport_rect().size - Vector2(ArmStick.MARGIN + ArmStick.RADIUS, ArmStick.MARGIN + ArmStick.RADIUS)
	return corner - Vector2(ArmStick.RADIUS + GAP + RADIUS, -ArmStick.RADIUS * 0.25)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and event.position.distance_to(center()) <= RADIUS * 1.2:
			_finger = event.index
			_down = true
			queue_redraw()
			get_viewport().set_input_as_handled()
			pressed.emit()   # at once: a jump is felt on the press
		elif not event.pressed and event.index == _finger:
			_finger = -1
			_down = false
			queue_redraw()


func _draw() -> void:
	var c := center()
	draw_circle(c, RADIUS * (0.92 if _down else 1.0), Color(1, 1, 1, 0.25))
	draw_arc(c, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.55), 3.0, true)
	var ink := Color("#4a5e7a", 0.9)
	var r := RADIUS
	for k in 2:
		var y := -r * 0.3 + k * r * 0.26
		draw_polyline(PackedVector2Array([c + Vector2(-r * 0.32, y + r * 0.2), c + Vector2(0, y - r * 0.08), c + Vector2(r * 0.32, y + r * 0.2)]), ink, 5.0, true)
	draw_line(c + Vector2(-r * 0.42, r * 0.38), c + Vector2(r * 0.42, r * 0.38), Color("#c9a66b", 0.95), 4.0, true)
