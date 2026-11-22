class_name Trails
extends RefCounted
## Herm's paths, tracks, walls and fences from OpenStreetMap, on the ground (HermData): each path a
## strip laid along the ground, its colour by its surface (trodden earth, sand, a grassy track,
## gravel), wider for the tracks than the footpaths (at 1:4 the real widths would be a hand's
## breadth); the strips stop at the water (the causeway and the pier run into the sea). Walls are
## low dry-stone walls, fences wooden; both block the way except where a path goes through.

const PATH_W := 1.0      ## footpaths, metres
const TRACK_W := 1.8     ## tracks and the village lanes
const STEP := 1.0        ## a strip follows the ground every this many metres
const LIFT := 0.04       ## above the ground (its triangles are a little lower than the samples)
const EARTH := "#c9ad7f"
const SAND_PATH := "#ecdcb6"
const GRASS_PATH := "#a9c27c"
const GRAVEL := "#d8cdb0"
const STEPS := "#bdb3a3"
const WALL := "#a89a88"
const WALL_TOP := "#968876"
const FENCE := "#9a7452"
const WALL_H := 0.7
const WALL_T := 0.35
const FENCE_H := 0.85
const GAP := 1.1         ## a wall leaves this much free each side of a path through it


## Builds the path strips and the walls under `root`; the walls go into `obs`.
static func build(root: Node3D, obs: Obstacles) -> void:
	var st := PaperMesh.begin()
	var order := 0
	for p in Terrain.data().meta.paths:
		_strip(st, p, order)
		order += 1
	var mi := MeshInstance3D.new()
	mi.name = "Paths"
	mi.mesh = PaperMesh.commit(st)
	mi.material_override = PaperMesh.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var ws := PaperMesh.begin()
	for w in Terrain.data().meta.walls:
		_wall(ws, w, obs)
	var wm := MeshInstance3D.new()
	wm.name = "Walls"
	wm.mesh = PaperMesh.commit(ws)
	wm.material_override = PaperMesh.material()
	root.add_child(wm)


static func width(p: Dictionary) -> float:
	return TRACK_W if p.kind in ["track", "pedestrian", "service", "unclassified", "residential"] else PATH_W


static func colour(p: Dictionary) -> Color:
	if p.kind == "steps":
		return PaperMesh.col(STEPS)
	match String(p.surface):
		"sand", "shell":
			return PaperMesh.col(SAND_PATH)
		"grass":
			return PaperMesh.col(GRASS_PATH)
		"gravel", "fine_gravel", "pebblestone", "paved", "asphalt", "concrete", "stone":
			return PaperMesh.col(GRAVEL)
	return PaperMesh.col(EARTH)


## Points along a polyline every STEP metres (its corners kept).
static func resample(pts: Array, step := STEP) -> Array:
	var out := []
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	if not pts.is_empty():
		out.append(Vector2(pts[-1][0], pts[-1][1]))
	return out


static func _strip(st: SurfaceTool, p: Dictionary, order: int) -> void:
	var pts := resample(p.pts)
	if pts.size() < 2:
		return
	var half := width(p) * 0.5
	var base := colour(p)
	var lift := LIFT + 0.004 * (order % 4)   # crossing strips do not flicker into each other
	var prev_l := Vector3.INF
	var prev_r := Vector3.INF
	for i in pts.size():
		var c: Vector2 = pts[i]
		var t: Vector2 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := t.orthogonal() * half
		var l2 := c + side
		var r2 := c - side
		var wet := Terrain.height(c.x, c.y) < 0.02
		if wet:
			prev_l = Vector3.INF   # into the sea: the strip stops (and starts again on land)
			continue
		var y := maxf(maxf(Terrain.height(l2.x, l2.y), Terrain.height(r2.x, r2.y)), Terrain.height(c.x, c.y)) + lift
		var l := Vector3(l2.x, y, l2.y)
		var r := Vector3(r2.x, y, r2.y)
		if prev_l != Vector3.INF:
			var col := base.lightened(0.04 * sin(i * 1.7))   # a little uneven, like paper
			PaperMesh.quad(st, prev_l, l, r, prev_r, col)
		prev_l = l
		prev_r = r


static func _wall(st: SurfaceTool, w: Dictionary, obs: Obstacles) -> void:
	var pts := resample(w.pts, 0.5)
	var fence: bool = w.kind != "wall"
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var m := (a + b) * 0.5
		if Terrain.height(m.x, m.y) < 0.05 or Terrain.near_path(m.x, m.y, GAP):
			continue   # in the sea, or a path goes through here
		var ya := Terrain.height(a.x, a.y)
		var yb := Terrain.height(b.x, b.y)
		var dir := (b - a).normalized()
		var n := dir.orthogonal() * (0.06 if fence else WALL_T * 0.5)
		var h := FENCE_H if fence else WALL_H
		var col := PaperMesh.col(FENCE if fence else WALL)
		var A0 := Vector3(a.x + n.x, ya - 0.1, a.y + n.y)
		var A1 := Vector3(a.x - n.x, ya - 0.1, a.y - n.y)
		var B0 := Vector3(b.x + n.x, yb - 0.1, b.y + n.y)
		var B1 := Vector3(b.x - n.x, yb - 0.1, b.y - n.y)
		var up := Vector3(0, h + 0.1, 0)
		var core := Vector3(m.x, (ya + yb) * 0.5 + h * 0.4, m.y)   # the wall's middle: its faces look away from it
		if fence:
			# A post at each piece and two rails.
			PaperMesh.quad(st, A0, A0 + up, A1 + up, A1, col, core + Vector3(dir.x, 0, dir.y))
			for rail in [0.45, 0.8]:
				var ru := Vector3(0, rail * h, 0)
				var rd := Vector3(0, rail * h - 0.08, 0)
				PaperMesh.quad(st, A0 + rd, B0 + rd, B0 + ru, A0 + ru, col, core)
				PaperMesh.quad(st, B1 + rd, A1 + rd, A1 + ru, B1 + ru, col, core)
		else:
			var stone := col.lightened(0.05 * sin(i * 2.3))
			PaperMesh.quad(st, A0, B0, B0 + up, A0 + up, stone, core)
			PaperMesh.quad(st, B1, A1, A1 + up, B1 + up, stone, core)
			PaperMesh.quad(st, A0 + up, B0 + up, B1 + up, A1 + up, PaperMesh.col(WALL_TOP), core)
		obs.add(m.x, m.y, 0.22 if not fence else 0.12)
