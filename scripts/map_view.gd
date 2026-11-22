class_name MapView
extends Control
## The paper map of Herm (the player: paths, unknown ones dashed): the island and its islets in
## pencil on paper, the paths walked drawn solid and the rest dashed (Exploration), the places
## found named and the rest marked "?", and where the bunny and TOFU are. North is up.

const PAPER := Color("#f3e8cf")
const SEA := Color("#d6e4df")
const LAND := Color("#efe2c3")
const COAST := Color("#6f8fa0")
const INK := Color("#5a4632")
const INK_LIGHT := Color("#a08a6c")
const BUNNY := Color("#e98aa6")
const TOFU := Color("#c8643a")

var explore: Exploration
var walkers := []   ## [[Vector2 position, Vector2 facing, Color]]
var _rect := Rect2()
var _scale := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


## World (x, z) to the sheet.
func to_map(p: Vector2) -> Vector2:
	return _rect.position + (p - _land_box().position) * _scale


func _land_box() -> Rect2:
	var box := Rect2()
	var first := true
	for ring in Terrain.data().meta.coast:
		for q in ring:
			var v := Vector2(q[0], q[1])
			box = Rect2(v, Vector2.ZERO) if first else box.expand(v)
			first = false
	return box.grow(12.0)


func _fit() -> void:
	var box := _land_box()
	var area := Rect2(Vector2(40, 70), size - Vector2(80, 110))
	_scale = minf(area.size.x / box.size.x, area.size.y / box.size.y)
	var used := box.size * _scale
	_rect = Rect2(area.position + (area.size - used) * 0.5, used)


func _draw() -> void:
	_fit()
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_rect(_rect, SEA)
	for ring in Terrain.data().meta.coast:
		var pts := PackedVector2Array()
		for q in ring:
			pts.append(to_map(Vector2(q[0], q[1])))
		if pts.size() > 2:
			draw_colored_polygon(pts, LAND)
			draw_polyline(pts, COAST, 2.0, true)
	if explore != null:
		# Dashes run on along a path from piece to piece (restarted on each 3 m piece they ran
		# together into a pale line); walked pieces are solid.
		var run := 0.0
		var last_path := -1
		var last_end := Vector2.INF
		for i in explore.pieces.size():
			var a := to_map(explore.pieces[i][0])
			var b := to_map(explore.pieces[i][1])
			if explore.pieces[i][2] != last_path or a.distance_to(last_end) > 0.5:
				run = 0.0
			last_path = explore.pieces[i][2]
			last_end = b
			if explore.walked[i] == 1:
				draw_line(a, b, INK, 2.5, true)
			else:
				run = _dashed(a, b, INK_LIGHT, 1.5, run)
		var font := get_theme_default_font()
		var labels: Array[Rect2] = []
		for f in explore.finds:
			var p := to_map(f.pos)
			if explore.found_names.has(f.name):
				draw_circle(p, 4.0, INK)
				var r := Rect2(p + Vector2(6, -9), font.get_string_size(f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13))
				var free := true
				for o in labels:
					if o.intersects(r):
						free = false
				if free:   # a name that would cover another's is left out (its dot stays)
					labels.append(r)
					draw_string(font, p + Vector2(6, 4), f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
			else:
				draw_arc(p, 7.0, 0, TAU, 16, INK_LIGHT, 1.2, true)
				draw_string(font, p + Vector2(-3.5, 4.5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK_LIGHT)
		var n := explore.found_names.size()
		draw_string(font, Vector2(40, 44), "Херм", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)
		draw_string(font, Vector2(150, 42), "Найдено %d из %d · тропы %d%%" % [n, explore.finds.size(), roundi(explore.walked_share() * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	for w in walkers:
		var p := to_map(w[0])
		var dir: Vector2 = w[1]
		draw_circle(p, 6.0, Color.WHITE)
		draw_circle(p, 4.5, w[2])
		draw_line(p, p + dir * 11.0, w[2], 2.5, true)


## Dashes from a to b, `run` pixels into the pattern already (4 on, 3 off); returns where it ends.
func _dashed(a: Vector2, b: Vector2, c: Color, w: float, run: float) -> float:
	const ON := 4.0
	const PERIOD := 7.0
	var L := a.distance_to(b)
	if L < 1e-3:
		return run
	var t := 0.0
	while t < L:
		var ph := fmod(run + t, PERIOD)
		if ph < ON:
			var e := minf(t + ON - ph, L)
			draw_line(a.lerp(b, t / L), a.lerp(b, e / L), c, w, true)
			t = e
		else:
			t = minf(t + PERIOD - ph, L)
	return run + L
