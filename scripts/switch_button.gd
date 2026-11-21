class_name SwitchButton
extends Control
## Small round on-screen button (top right, under the eye) that gives the player the other
## character (the player asked for it, to test each one; Tab on a PC). Two little heads drawn in
## code: the one you steer in front. Emits `pressed`.

signal pressed

const RADIUS := 36.0
const MARGIN := 40.0
const GAP := 18.0           ## below the view button
const BUNNY := Color("#f6d3dc")
const TOFU := Color("#c8643a")
const INK := Color("#3b4a5e")

var bunny_steered := false  ## drawn: whose head is in front
var _finger := -1
var _down := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func center() -> Vector2:
	return Vector2(get_viewport_rect().size.x - MARGIN - RADIUS, MARGIN + RADIUS * 3.0 + GAP)   # the screen's size: this control's stays 0


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


func set_bunny(on: bool) -> void:
	bunny_steered = on
	queue_redraw()


func _draw() -> void:
	var c := center()
	draw_circle(c, RADIUS * (0.92 if _down else 1.0), Color(1, 1, 1, 0.25))
	draw_arc(c, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.55), 3.0, true)
	var back := c + Vector2(RADIUS * 0.28, -RADIUS * 0.2)
	var front := c + Vector2(-RADIUS * 0.18, RADIUS * 0.14)
	if bunny_steered:
		_tofu(back, 0.7, 0.6)
		_bunny(front, 1.0, 0.95)
	else:
		_bunny(back, 0.7, 0.6)
		_tofu(front, 1.0, 0.95)


func _bunny(p: Vector2, k: float, a: float) -> void:
	var r := RADIUS * 0.34 * k
	for s in [-1.0, 1.0]:   # long ears
		var ear := PackedVector2Array()
		for i in 13:
			var t := float(i) / 12.0 * TAU
			ear.append(p + Vector2(s * r * 0.45 + cos(t) * r * 0.22, -r * 1.25 + sin(t) * r * 0.7))
		draw_colored_polygon(ear, Color(BUNNY, a))
	draw_circle(p, r, Color(BUNNY, a))
	_eyes(p, r, a)


func _tofu(p: Vector2, k: float, a: float) -> void:
	var r := RADIUS * 0.36 * k
	for s in [-1.0, 1.0]:   # pointed ears
		draw_colored_polygon(PackedVector2Array([p + Vector2(s * r * 0.95, -r * 0.2), p + Vector2(s * r * 0.75, -r * 1.15), p + Vector2(s * r * 0.15, -r * 0.75)]), Color(TOFU, a))
	draw_circle(p, r, Color(TOFU, a))
	draw_circle(p + Vector2(0, r * 0.35), r * 0.45, Color(1, 1, 1, a * 0.9))   # the white muzzle
	_eyes(p, r, a)


func _eyes(p: Vector2, r: float, a: float) -> void:
	for s in [-1.0, 1.0]:
		draw_circle(p + Vector2(s * r * 0.38, -r * 0.05), r * 0.11, Color(INK, a))
