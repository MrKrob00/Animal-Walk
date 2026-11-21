class_name ActionButton
extends Control
## Round on-screen button (bottom right, above the paw stick) with a stake icon drawn in code.
## Emits `pressed`. Dim when the action would do nothing.

signal pressed

const RADIUS := 64.0
const MARGIN := 48.0

var active := true
var _finger := -1
var _down := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## (From the screen's size: this control's own size stays 0 under the CanvasLayer, which put the
## button off the screen.)
## Above the paw stick (the corner is the paw's: the player chose it).
func center() -> Vector2:
	var corner := get_viewport_rect().size - Vector2(ArmStick.MARGIN + ArmStick.RADIUS, ArmStick.MARGIN + ArmStick.RADIUS)
	return corner - Vector2(ArmStick.RADIUS * 0.7, ArmStick.RADIUS + RADIUS + 28.0)


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


func set_active(on: bool) -> void:
	if on != active:
		active = on
		queue_redraw()


func _draw() -> void:
	var c := center()
	var a := 0.55 if active else 0.25
	draw_circle(c, RADIUS * (0.92 if _down else 1.0), Color(1, 1, 1, a * 0.45))
	draw_arc(c, RADIUS, 0, TAU, 48, Color(1, 1, 1, a), 3.0, true)
	# Stake: a post with a pointed foot and a band of red rope.
	var wood := Color("#8a5a3c", a + 0.3)
	draw_rect(Rect2(c + Vector2(-7, -26), Vector2(14, 36)), wood)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 10), c + Vector2(7, 10), c + Vector2(0, 24)]), wood)
	draw_rect(Rect2(c + Vector2(-9, -14), Vector2(18, 6)), Color("#d8414a", a + 0.3))
	draw_rect(Rect2(c + Vector2(-9, -30), Vector2(18, 5)), Color("#b98a62", a + 0.3))
