class_name SitButton
extends Control
## Round on-screen button left of the stake button: the character you steer sits down (the
## bunny in her "frog" W-sit, TOFU like a dog) or gets up again (C on a PC). A little stool
## drawn in code, lit while sitting. Emits `pressed`.

signal pressed

const RADIUS := 44.0
const GAP := 22.0

var sitting := false
var _finger := -1
var _down := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Left of the stake button (ActionButton), level with it.
func center() -> Vector2:
	var corner := get_viewport_rect().size - Vector2(ArmStick.MARGIN + ArmStick.RADIUS, ArmStick.MARGIN + ArmStick.RADIUS)
	var stake := corner - Vector2(ArmStick.RADIUS * 0.7, ArmStick.RADIUS + ActionButton.RADIUS + 28.0)
	return stake - Vector2(ActionButton.RADIUS + GAP + RADIUS, -ActionButton.RADIUS * 0.35)


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


func set_sitting(on: bool) -> void:
	if on != sitting:
		sitting = on
		queue_redraw()


func _draw() -> void:
	var c := center()
	draw_circle(c, RADIUS * (0.92 if _down else 1.0), Color(1, 1, 1, 0.38 if sitting else 0.25))
	draw_arc(c, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.55), 3.0, true)
	# A stool: a round seat and three legs.
	var ink := Color("#8a5a3b", 0.9)
	var r := RADIUS
	draw_line(c + Vector2(-r * 0.3, -r * 0.05), c + Vector2(-r * 0.4, r * 0.45), ink, 4.0, true)
	draw_line(c + Vector2(r * 0.3, -r * 0.05), c + Vector2(r * 0.4, r * 0.45), ink, 4.0, true)
	draw_line(c + Vector2(0, -r * 0.05), c + Vector2(0, r * 0.4), ink, 3.0, true)
	var seat := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20.0
		seat.append(c + Vector2(cos(a) * r * 0.45, -r * 0.12 + sin(a) * r * 0.13))
	draw_colored_polygon(seat, Color("#c98d5c", 0.95))
	draw_polyline(seat, ink, 2.0, true)
