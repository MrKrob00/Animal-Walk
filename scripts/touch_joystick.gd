class_name TouchJoystick
extends Control
## Floating stick: appears where the thumb lands on the left part of the screen.

const RADIUS := 90.0
const ZONE := 0.6   ## left share of the screen that starts the stick

var vector := Vector2.ZERO
var _finger := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0 and event.position.x < size.x * ZONE:
			_finger = event.index
			_origin = event.position
			_knob = event.position
			vector = Vector2.ZERO
			queue_redraw()
		elif not event.pressed and event.index == _finger:
			release()
	elif event is InputEventScreenDrag and event.index == _finger:
		var d: Vector2 = event.position - _origin
		_knob = _origin + d.limit_length(RADIUS)
		vector = d.limit_length(RADIUS) / RADIUS
		queue_redraw()


## Lets go of the stick (also call this when a pausing window closes).
func release() -> void:
	_finger = -1
	vector = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if _finger < 0:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.18))
	draw_arc(_origin, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
	draw_circle(_knob, RADIUS * 0.42, Color(1, 1, 1, 0.6))
