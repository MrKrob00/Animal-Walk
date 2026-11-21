class_name ViewButton
extends Control
## Small round on-screen button (top right) that switches the camera between third person and
## the eyes (first person). An eye drawn in code; emits `pressed`.

signal pressed

const RADIUS := 36.0
const MARGIN := 40.0

var first_person := false   ## drawn: the eye open in first person
var _finger := -1
var _down := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func center() -> Vector2:
	return Vector2(get_viewport_rect().size.x - MARGIN - RADIUS, MARGIN + RADIUS)   # the screen's size: this control's stays 0


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


func set_first_person(on: bool) -> void:
	first_person = on
	queue_redraw()


func _draw() -> void:
	var c := center()
	draw_circle(c, RADIUS * (0.92 if _down else 1.0), Color(1, 1, 1, 0.25))
	draw_arc(c, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.55), 3.0, true)
	# An eye: two arcs for the lids, the iris inside (open in first person, a half-closed lid otherwise).
	var w := RADIUS * 0.62
	var lid := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		lid.append(c + Vector2(lerpf(-w, w, t), -sin(t * PI) * w * 0.55))
	for i in 17:
		var t := float(16 - i) / 16.0
		lid.append(c + Vector2(lerpf(-w, w, t), sin(t * PI) * w * (0.55 if first_person else 0.15)))
	draw_colored_polygon(lid, Color(1, 1, 1, 0.75))
	draw_circle(c + Vector2(0, -w * 0.05 if first_person else w * 0.0), w * (0.36 if first_person else 0.22), Color("#3b4a5e", 0.9))
	draw_polyline(lid, Color("#3b4a5e", 0.8), 2.0, true)
