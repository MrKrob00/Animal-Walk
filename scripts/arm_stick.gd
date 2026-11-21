class_name ArmStick
extends Control
## Fixed stick in the bottom-right corner for TOFU's right paw (the player asked): left / right
## and up / down point the arm, the paw reaches out until it meets something; let go and the arm
## comes back down. Shown while the player steers TOFU. I J K L on a PC.

const RADIUS := 70.0
const MARGIN := 40.0

var vector := Vector2.ZERO
var held := false
var _finger := -1
var _knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func center() -> Vector2:
	return get_viewport_rect().size - Vector2(MARGIN + RADIUS, MARGIN + RADIUS)   # the screen's size: this control's stays 0


func _input(event: InputEvent) -> void:
	if not visible:
		if _finger >= 0:
			release()
		return
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0 and event.position.distance_to(center()) <= RADIUS * 1.2:
			_finger = event.index
			held = true
			_move_knob(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _finger:
			release()
	elif event is InputEventScreenDrag and event.index == _finger:
		_move_knob(event.position)
		get_viewport().set_input_as_handled()


func _move_knob(p: Vector2) -> void:
	var d := (p - center()).limit_length(RADIUS)
	_knob = center() + d
	vector = d / RADIUS
	queue_redraw()


## Lets go of the stick (also when a pausing window closes, or TOFU is no longer steered).
func release() -> void:
	_finger = -1
	held = false
	vector = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var c := center()
	draw_circle(c, RADIUS, Color(1, 1, 1, 0.16))
	draw_arc(c, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
	var k := _knob if held else c
	draw_circle(k, RADIUS * 0.4, Color(1, 1, 1, 0.55 if held else 0.35))
	# A paw on the knob: a pad and three toes.
	var ink := Color("#c8643a", 0.85)
	draw_circle(k + Vector2(0, RADIUS * 0.07), RADIUS * 0.13, ink)
	for i in 3:
		var a := -PI * 0.5 + (float(i) - 1.0) * 0.6
		draw_circle(k + Vector2(cos(a), sin(a)) * RADIUS * 0.2 + Vector2(0, RADIUS * 0.05), RADIUS * 0.055, ink)
