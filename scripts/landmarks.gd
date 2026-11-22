class_name Landmarks
extends RefCounted
## What stands at Herm's named places (the player: the map was empty, only paths), by what is
## really there (OpenStreetMap's kind for each place): the harbour village's tavern, inn, post
## office, chapel, school, hotel and cottages, the beach cafes with their tables, the camp site's
## tents, the copper mine's adit, the quarries' stone, the neolithic graves as dolmens, Robert's
## Cross, the obelisk on the north point, cairns on the two tops. Buildings and props are KayKit's
## (CC0, Kay Lousberg), at the bunny's size (the houses are not shrunk with the island: a doll's
## village by a full-size bunny would read as toys); the stones are paper-craft like the rocks.
## Each stands just off the paths, facing the nearest one.

const MED := "res://assets/kaykit/medieval/%s.gltf"
const RES := "res://assets/kaykit/restaurant/%s.gltf"
const HAL := "res://assets/kaykit/halloween/%s.gltf"
const MED_SCALE := 4.3    ## KayKit's hex-pack units to metres: a cottage about 4 m high
const RES_SCALE := 0.75   ## the restaurant bits: a table 0.75 m high
const HAL_SCALE := 0.8
const SEEN_TO := 140.0    ## drawn within this many metres of the camera
const STONE := "#a89a88"
const STONE_DARK := "#8f8170"

## Places that are only names on a map (nothing to find there) or duplicates.
const SKIP_KINDS := ["information", "coastline", "biergarten", "chalet", "boat_rental"]


## Builds them under `root`, their footprints into `obs`. Returns {"finds": the places to find,
## for the map: [{"name", "kind", "pos": Vector2, "has": what stands there or ""}], "reserved":
## [Vector3(x, z, radius)] where they stand (plants and trunks keep off)}.
static func build(root: Node3D, obs: Obstacles) -> Dictionary:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var st := PaperMesh.begin()   # the stones, one mesh
	var taken := [[WorldBuilder.clearing_center(), WorldBuilder.CLEARING_RADIUS]]   # [Vector2, radius]: kept clear of each other and of the start
	for p in Terrain.data().meta.places:
		var kind: String = p.kind
		if kind in SKIP_KINDS:
			continue
		var at := Vector2(p.x, p.z)
		# A bay's, beach's or the harbour's mark often lies on the water: the nearest dry land a
		# walker can get to stands for it. An islet's or a reef's cannot be reached: skipped.
		if not Terrain.reachable(at.x, at.y) and not (kind in ["bay", "beach"] or p.name == "Herm Harbour"):
			continue   # an islet's point or a reef: on the map, but nobody walks there
		at = Terrain.nearest_reachable(at, 1.0, 40.0)
		if at == Vector2.INF:
			continue
		var has := ""
		match kind:
			"pub":
				has = "tavern"
				_building(root, obs, taken, at, MED % ("building_tavern_blue" if p.name.begins_with("Mermaid") else "building_tavern_red"), 3.2)
				_terrace(root, obs, taken, at, rng)
			"post_office":
				has = "house"
				_building(root, obs, taken, at, MED % "building_home_B_blue", 2.6)
			"school":
				has = "house"
				_building(root, obs, taken, at, MED % "building_home_A_red", 2.2)
			"hotel":
				has = "house"
				_building(root, obs, taken, at, MED % "building_home_B_red", 2.6)
			"place_of_worship":
				has = "chapel"
				_building(root, obs, taken, at, MED % "building_church_blue", 3.0)
			"restaurant", "cafe":
				has = "cafe"
				_building(root, obs, taken, at, MED % ("building_market_red" if kind == "cafe" else "building_market_blue"), 3.2)
				_terrace(root, obs, taken, at, rng)
			"camp_site":
				has = "tents"
				for i in 3:
					_prop(root, obs, taken, at + Vector2.from_angle(i * TAU / 3.0 + 0.4) * 4.5, MED % "tent", MED_SCALE, 1.2)
				_prop(root, obs, taken, at, MED % "barrel", MED_SCALE, 0.5)
			"adit":
				has = "mine"
				_building(root, obs, taken, at, MED % "building_mine_blue", 3.6)
			"quarry":
				has = "quarry"
				for i in 3:
					_prop(root, obs, taken, at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 4.0), MED % "resource_stone", MED_SCALE, 1.0)
				_prop(root, obs, taken, at + Vector2(3.0, 1.0), MED % "wheelbarrow", MED_SCALE, 0.6)
			"hamlet":
				has = "village"
				for i in 3:
					_building(root, obs, taken, at + Vector2.from_angle(i * TAU / 3.0 + 0.9) * 9.0, MED % ["building_home_A_blue", "building_home_B_red", "building_home_A_red"][i], 2.4)
				_building(root, obs, taken, at, MED % "building_well_blue", 1.4)
			"archaeological_site":
				if String(p.name).contains("Cross"):
					has = "cross"
					_stone_cross(st, obs, taken, at, rng)
				else:
					has = "dolmen"
					_dolmen(st, obs, taken, at, rng)
			"monument":
				has = "obelisk"
				_obelisk(st, obs, taken, at)
			"peak":
				has = "cairn"
				_cairn(st, obs, taken, at, rng)
			"locality":
				if p.name == "Herm Harbour":
					has = "quay"
					for i in 4:
						_prop(root, obs, taken, at + Vector2(i * 1.1 - 1.5, rng.randf_range(-0.6, 0.6)), MED % ["barrel", "crate_A_big", "crate_B_small", "sack"][i], MED_SCALE, 0.45)
		out.append({"name": p.name, "kind": kind, "pos": at, "has": has})
	_cottages(root, obs, taken)
	var mi := MeshInstance3D.new()
	mi.name = "Stones"
	mi.mesh = PaperMesh.commit(st)
	mi.material_override = PaperMesh.material()
	root.add_child(mi)
	var reserved := []
	for t in taken:
		reserved.append(Vector3(t[0].x, t[0].y, float(t[1]) + 1.0))
	return {"finds": out, "reserved": reserved}


## A free spot for something of `radius` near `at`: on dry, fairly level land, off the paths
## and clear of what stands already (rings outward until one fits).
static func spot(at: Vector2, radius: float, taken: Array) -> Vector2:
	for r in range(0, 30):
		var n := maxi(1, r * 3)
		for a in n:
			var q := at + Vector2.from_angle(a * TAU / n + r) * r * 0.8
			if Terrain.shore_distance(q.x, q.y) < radius + 1.0 or Terrain.normal(q.x, q.y).y < 0.9:
				continue
			if Terrain.near_path(q.x, q.y, radius + 0.9):
				continue
			var free := true
			for t in taken:
				if q.distance_to(t[0]) < radius + float(t[1]) + 0.6:
					free = false
					break
			if free:
				return q
	return Vector2.INF


## The way to the nearest path from `q` (a building's front turns to it).
static func _to_path(q: Vector2) -> float:
	var best := INF
	var ang := 0.0
	for a in 24:
		var d := Vector2.from_angle(a * TAU / 24.0)
		for r in range(1, 20):
			var p := q + d * r
			if Terrain.near_path(p.x, p.y, 0.6):
				if r < best:
					best = r
					ang = a * TAU / 24.0
				break
	return ang


static func _place(root: Node3D, path: String, q: Vector2, scale: float, yaw: float, sink := 0.15) -> Node3D:
	var n: Node3D = load(path).instantiate()
	n.position = Vector3(q.x, Terrain.height(q.x, q.y) - sink, q.y)
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	for mi in n.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).visibility_range_end = SEEN_TO
	root.add_child(n)
	return n


## A building of footprint `radius` (metres) near `at`, its front to the nearest path; blocks.
static func _building(root: Node3D, obs: Obstacles, taken: Array, at: Vector2, path: String, radius: float) -> void:
	var q := spot(at, radius, taken)
	if q == Vector2.INF:
		return
	var face := _to_path(q)
	# KayKit's fronts face +Z: turn +Z toward the path.
	_place(root, path, q, MED_SCALE, PI * 0.5 - face, 0.3)
	taken.append([q, radius])
	for i in 7:
		var o := q + (Vector2.from_angle(i * TAU / 6.0) * radius * 0.55 if i < 6 else Vector2.ZERO)
		obs.add(o.x, o.y, radius * 0.5)


static func _prop(root: Node3D, obs: Obstacles, taken: Array, at: Vector2, path: String, scale: float, radius: float) -> void:
	var q := spot(at, radius, taken)
	if q == Vector2.INF:
		return
	_place(root, path, q, scale, randf() * TAU, 0.02)
	taken.append([q, radius])
	obs.add(q.x, q.y, radius * 0.8)


## Two round tables with stools and a lantern beside a tavern or a cafe.
static func _terrace(root: Node3D, obs: Obstacles, taken: Array, at: Vector2, rng: RandomNumberGenerator) -> void:
	for i in 2:
		var q := spot(at + Vector2.from_angle(rng.randf() * TAU) * 5.0, 1.3, taken)
		if q == Vector2.INF:
			continue
		_place(root, RES % "table_round_A_small", q, RES_SCALE, rng.randf() * TAU, 0.02)
		for s in 3:
			var c := q + Vector2.from_angle(s * TAU / 3.0 + rng.randf()) * 0.95
			_place(root, RES % "chair_stool", c, RES_SCALE, rng.randf() * TAU, 0.02)
		taken.append([q, 1.3])
		obs.add(q.x, q.y, 0.6)
	_prop(root, obs, taken, at + Vector2(2.5, 2.5), HAL % "lantern_standing", HAL_SCALE, 0.4)


## Cottages on Herm's own building footprints round the village, at least 10 m apart, at most 8.
static func _cottages(root: Node3D, obs: Obstacles, taken: Array) -> void:
	var homes := ["building_home_A_blue", "building_home_B_blue", "building_home_A_red", "building_home_B_red"]
	var n := 0
	for b in Terrain.data().meta.buildings:
		if n >= 8:
			break
		var c := Vector2.ZERO
		for pt in b.pts:
			c += Vector2(pt[0], pt[1])
		c /= b.pts.size()
		var near := false
		for t in taken:
			if c.distance_to(t[0]) < 10.0:
				near = true
		if near:
			continue
		var before: int = taken.size()
		_building(root, obs, taken, c, MED % homes[n % homes.size()], 2.3)
		if taken.size() > before:
			n += 1


## A dolmen: three standing slabs and a capstone across them (the neolithic graves).
static func _dolmen(st: SurfaceTool, obs: Obstacles, taken: Array, at: Vector2, rng: RandomNumberGenerator) -> void:
	var q := spot(at, 1.6, taken)
	if q == Vector2.INF:
		return
	var y := Terrain.height(q.x, q.y)
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	for s in [Vector3(-0.75, 0, 0), Vector3(0.75, 0, 0), Vector3(0, 0, -0.65)]:
		var o: Vector3 = b * s
		PaperMesh.ellipsoid(st, Transform3D(b, Vector3(q.x + o.x, y + 0.45, q.y + o.z)), Vector3(0.22, 0.6, 0.45), 6, 3, PaperMesh.col(STONE), 0.15, rng)
	PaperMesh.ellipsoid(st, Transform3D(b, Vector3(q.x, y + 1.15, q.y - 0.1)), Vector3(1.15, 0.16, 0.75), 7, 3, PaperMesh.col(STONE_DARK), 0.12, rng)
	taken.append([q, 1.6])
	for s in [-0.75, 0.75]:
		var o: Vector3 = b * Vector3(s, 0, 0)
		obs.add(q.x + o.x, q.y + o.z, 0.35)
	var back: Vector3 = b * Vector3(0, 0, -0.65)
	obs.add(q.x + back.x, q.y + back.z, 0.35)


## The obelisk on the north point (Pierre aux Rats): a tall tapering stone on a step.
static func _obelisk(st: SurfaceTool, obs: Obstacles, taken: Array, at: Vector2) -> void:
	var q := spot(at, 1.0, taken)
	if q == Vector2.INF:
		return
	var y := Terrain.height(q.x, q.y)
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(q.x, y - 0.1, q.y)), 0.75, 0.7, 0.35, 4, PaperMesh.col(STONE_DARK))
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(q.x, y + 0.25, q.y)), 0.42, 0.26, 3.4, 4, PaperMesh.col(STONE))
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(q.x, y + 3.65, q.y)), 0.26, 0.01, 0.5, 4, PaperMesh.col(STONE))
	taken.append([q, 1.0])
	obs.add(q.x, q.y, 0.7)


## Robert's Cross: a stone cross on a rough base.
static func _stone_cross(st: SurfaceTool, obs: Obstacles, taken: Array, at: Vector2, rng: RandomNumberGenerator) -> void:
	var q := spot(at, 0.8, taken)
	if q == Vector2.INF:
		return
	var y := Terrain.height(q.x, q.y)
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(q.x, y, q.y)), Vector3(0.6, 0.3, 0.6), 7, 3, PaperMesh.col(STONE_DARK), 0.15, rng)
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(q.x, y + 0.2, q.y)), 0.2, 0.17, 2.3, 4, PaperMesh.col(STONE))
	PaperMesh.frustum(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(q.x - 0.65, y + 1.85, q.y)), 0.15, 0.15, 1.3, 4, PaperMesh.col(STONE))   # the arm, along +X
	taken.append([q, 0.8])
	obs.add(q.x, q.y, 0.45)


## A cairn of stacked stones on a top.
static func _cairn(st: SurfaceTool, obs: Obstacles, taken: Array, at: Vector2, rng: RandomNumberGenerator) -> void:
	var q := spot(at, 1.4, taken)
	if q == Vector2.INF:
		return
	var y := Terrain.height(q.x, q.y)
	var h := 0.0
	for i in 5:
		var r := 1.0 - i * 0.16
		PaperMesh.ellipsoid(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x + rng.randf_range(-0.05, 0.05), y + h + r * 0.45, q.y)), Vector3(r, r * 0.55, r * 0.85), 6, 3, PaperMesh.col(STONE if i % 2 == 0 else STONE_DARK), 0.2, rng)
		h += r * 0.75
	taken.append([q, 1.0])
	obs.add(q.x, q.y, 0.6)
