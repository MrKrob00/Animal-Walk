class_name WorldBuilder
extends RefCounted
## Dresses the island: palm groves on the beaches, flowering bushes on the hill meadows,
## rocks on the sand and slopes, dune grass, and shells and starfish by the water.
## Each kind is cut into CHUNK-sized MultiMeshes that fade out with distance, so a big island
## costs only what is near the camera.

const TRUNK := "#9a7452"
const TRUNK_RING := "#7d5c40"
const FROND := "#4f9a52"
const FROND_DARK := "#3f8443"
const COCONUT := "#6b4a2f"
const BUSH := "#4f9a52"
const BUSH_DARK := "#3c7f45"
const FLOWER := "#ee7a96"
const STONE := "#a89a88"
const DUNE_GRASS := "#b9b46a"
const SHELL := "#f6e8d8"
const STARFISH := "#ea8a5c"

const CHUNK := 32.0         ## metres per MultiMesh piece
const SEEN_TO := 60.0       ## pieces fade out beyond this distance from the camera

## The start: Herm Harbour, where the boat comes in, a few metres up from the water.
static func clearing_center() -> Vector2:
	if _start == Vector2.INF:
		var h := Vector2.ZERO
		for p in Terrain.data().meta.places:
			if p.name == "Herm Harbour":
				h = Vector2(p.x, p.z)
		# Up the slope from the harbour's mark until there are a few metres of dry land.
		var best := h
		for r in range(0, 40, 2):
			for a in 16:
				var q := h + Vector2.from_angle(a * TAU / 16.0) * r
				if Terrain.shore_distance(q.x, q.y) > 6.0 and Terrain.normal(q.x, q.y).y > 0.97 and not Terrain.near_path(q.x, q.y, 1.0):
					_start = q
					return _start
		_start = best
	return _start

static var _start := Vector2.INF

const CLEARING_RADIUS := 7.0


## A random point on the island's grid.
static func _anywhere(rng: RandomNumberGenerator) -> Vector2:
	var r := Terrain.bounds()
	return Vector2(r.position.x + rng.randf() * r.size.x, r.position.y + rng.randf() * r.size.y)


## Fills `root`; obstacles go into `obs`. Plants by what the ground is (OpenStreetMap's woods,
## scrub, meadows and beaches): woods are bushes and trees, scrub bushes, the meadows grass tufts
## with a bush here and there, the beaches shells and starfish at the water, rocks on the rocky
## shore and the steep slopes; nothing on the paths.
## `reserved`: places to leave free, [Vector3(x, z, radius)] (the low passages).
## Where the trees stand (x, z), for the tests (a MultiMesh keeps no transforms without a screen).
static var trees_at := PackedVector2Array()

static func populate(root: Node3D, obs: Obstacles, seed_value := 20261120, reserved: Array = []) -> void:
	trees_at.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kinds := {"palm": [], "bush": [], "rock": [], "tree_a": [], "tree_b": [], "trees": []}
	var spacing := {"palm": 4.0, "bush": 2.4, "rock": 2.6, "tree_a": 3.0, "tree_b": 3.0, "trees": 6.0}
	var block := {"palm": 0.32, "bush": 0.75, "rock": 0.8, "tree_a": 0.4, "tree_b": 0.45, "trees": 1.6}
	var taken := Obstacles.new()   # placement spacing, a separate grid
	var clear := clearing_center()
	# The woods first, cell by cell, so they are thick (Herm's are small: a random scatter over
	# the whole island left them a few trees each).
	var d := Terrain.data()
	var m: Dictionary = d.meta
	var wood_spots: Array[Vector2] = []
	for j in int(m.nz):
		for i in int(m.nx):
			if d.kind[j * int(m.nx) + i] == 3:
				for t in 2:
					wood_spots.append(Vector2(float(m.x0) + (i + rng.randf() - 0.5) * float(m.cell), float(m.z0) + (j + rng.randf() - 0.5) * float(m.cell)))
	for i in range(60000 + wood_spots.size()):
		var q := wood_spots[i] if i < wood_spots.size() else _anywhere(rng)
		var x := q.x
		var z := q.y
		var sd := Terrain.shore_distance(x, z)
		if sd < -2.5 or q.distance_to(clear) < CLEARING_RADIUS:
			continue
		var kept_free := false
		for r in reserved:
			if q.distance_to(Vector2(r.x, r.y)) < r.z:
				kept_free = true
		if kept_free:
			continue
		var y := Terrain.height(x, z)
		var k := Terrain.kind(x, z)
		var steep := Terrain.normal(x, z).y < 0.8
		var kind := ""
		var roll := rng.randf()
		if sd < 2.5 and k != 2 and y > -0.4:
			kind = "rock" if roll < 0.5 else ""          # the rocky shore
		elif steep and sd >= 0.0:
			kind = "rock" if roll < 0.25 else ""         # outcrops on the slopes
		elif k == 3:
			# Herm's woods are broadleaf: KayKit's trees, now and then a clump of them, bushes under.
			kind = "tree_a" if roll < 0.3 else ("tree_b" if roll < 0.55 else ("trees" if roll < 0.62 else ("bush" if roll < 0.9 else "")))
		elif k == 4:
			kind = "bush" if roll < 0.7 else ""          # scrub
		elif k == 1:
			kind = "bush" if roll < 0.035 else ("palm" if roll < 0.042 else ("tree_b" if roll < 0.047 else ""))   # a bush, a palm or a tree here and there on the meadows
		if kind == "" or Terrain.near_path(x, z, 1.6):
			continue
		var sp: float = spacing[kind]
		var crowded := false
		var crowd := 0.45 if kind.begins_with("tree") else 0.6   # crowns may touch in a wood
		for o in taken.near(x, z, sp):
			if Vector2(o.x, o.y).distance_to(Vector2(x, z)) < (sp + o.z) * crowd:
				crowded = true
				break
		if crowded:
			continue
		var s := rng.randf_range(0.85, 1.25)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if kind == "rock":
			s = rng.randf_range(0.45, 1.1) * (1.6 if steep else 1.0)   # bigger outcrops on the slopes
			basis = basis.scaled(Vector3(s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.7, 1.1), s * rng.randf_range(0.8, 1.2)))
		else:
			basis = basis.scaled(Vector3.ONE * s)
		kinds[kind].append(Transform3D(basis, Vector3(x, y - 0.08, z)))
		taken.add(x, z, sp)
		if y > -0.3:
			obs.add(x, z, block[kind] * s)
	var tufts: Array = []
	var shells: Array = []
	var stars: Array = []
	for i in range(40000):
		var q := _anywhere(rng)
		var x := q.x
		var z := q.y
		var sd := Terrain.shore_distance(x, z)
		if sd < 0.0 or Terrain.near_path(x, z, 0.8):
			continue
		var y := Terrain.height(x, z)
		var k := Terrain.kind(x, z)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if (k == 1 or k == 4) and i % 3 == 0:
			tufts.append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)), Vector3(x, y - 0.04, z)))
		elif k == 2 and sd > 6.0 and i % 4 == 0:
			tufts.append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.6, 1.0)), Vector3(x, y - 0.04, z)))   # dune grass
		elif k == 2 and sd < 4.0 and y > 0.02 and i % 3 == 1:
			var t := Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.2)), Vector3(x, y + 0.01, z))
			if rng.randf() < 0.7:
				shells.append(t)
			else:
				stars.append(t)
	_add_chunked(root, "Palms", palm_mesh(rng), kinds["palm"], true, Foliage.material("palm"))
	_add_chunked(root, "Bushes", bush_mesh(rng), kinds["bush"], true, Foliage.material("bush"))
	# Broadleaf trees in paper, three shapes; a "clump" is three of them close together.
	var shapes := [Foliage.tree_mesh(rng), Foliage.tree_mesh(rng), Foliage.tree_mesh(rng)]
	var by_shape := [[], [], []]
	for x in kinds["tree_a"]:
		by_shape[0].append(x)
	for x in kinds["tree_b"]:
		by_shape[1].append(x)
	for x in kinds["trees"]:
		for i in 3:
			var o := Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 2.6
			var t2 := Transform3D(x.basis, x.origin + o)
			t2.origin.y = Terrain.height(t2.origin.x, t2.origin.z) - 0.08
			by_shape[2].append(t2)
	for i in 3:
		_add_chunked(root, "Trees", shapes[i], by_shape[i], true, Foliage.material("tree_paper"))
		for t in by_shape[i]:
			trees_at.append(Vector2(t.origin.x, t.origin.z))
	_add_chunked(root, "Rocks", rock_mesh(rng), kinds["rock"])
	_add_chunked(root, "DuneGrass", tuft_mesh(rng), tufts, false)
	_add_chunked(root, "Shells", shell_mesh(), shells, false)
	_add_chunked(root, "Starfish", starfish_mesh(), stars, false)


## One MultiMesh per CHUNK cell, faded out with distance.
static func _add_chunked(root: Node3D, node_name: String, mesh: Mesh, xforms: Array, shadows := true, mat: Material = null) -> void:
	var cells := {}
	for t in xforms:
		var k := Vector2i(floori(t.origin.x / CHUNK), floori(t.origin.z / CHUNK))
		if not cells.has(k):
			cells[k] = []
		cells[k].append(t)
	var group := Node3D.new()
	group.name = node_name
	root.add_child(group)
	for k in cells:
		var list: Array = cells[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in range(list.size()):
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat if mat != null else PaperMesh.material()
		mmi.visibility_range_end = SEEN_TO
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(mmi)


## A leaning, ringed trunk and a crown of drooping paper fronds with three coconuts.
static func palm_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	var h := 0.0
	var lean := Vector3.ZERO
	var r := 0.2
	var top := Vector3.ZERO
	for i in range(8):
		var seg := 0.62
		var tilt := Basis(Vector3.FORWARD, -0.06 * i)   # the trunk curves as it rises
		var base := Vector3(lean.x, h, 0)
		PaperMesh.frustum(st, Transform3D(tilt, base), r, r * 0.93, seg, 7, PaperMesh.col(TRUNK if i % 2 == 0 else TRUNK_RING), false)
		var up := tilt * Vector3(0, seg, 0)
		lean.x += up.x
		h += up.y
		r *= 0.93
		top = Vector3(lean.x, h, 0)
	for i in range(8):
		var ang := TAU * i / 8.0 + rng.randf_range(-0.15, 0.15)
		_frond(st, top, ang, rng.randf_range(2.0, 2.6), PaperMesh.col(FROND if i % 2 == 0 else FROND_DARK))
	for i in range(3):
		var a := TAU * i / 3.0
		PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, top + Vector3(cos(a) * 0.18, -0.16, sin(a) * 0.18)), Vector3.ONE * 0.13, 6, 4, PaperMesh.col(COCONUT))
	return PaperMesh.commit(st)


## One frond: a spine arching out and down, with zig-zag paper leaflets on both sides.
static func _frond(st: SurfaceTool, base: Vector3, ang: float, length: float, color: Color) -> void:
	var dir := Vector3(cos(ang), 0, sin(ang))
	var side := dir.cross(Vector3.UP).normalized()
	var n := 7
	var spine := PackedVector3Array()
	for k in range(n + 1):
		var t := float(k) / n
		spine.append(base + dir * length * t + Vector3.UP * (0.45 * t - 1.25 * t * t))
	for k in range(n):
		var t := float(k) / n
		var wide := 0.42 * sin(PI * (t * 0.85 + 0.1))
		var a := spine[k]
		var b := spine[k + 1]
		var mid := (a + b) * 0.5
		for sgn in [-1.0, 1.0]:
			var tip: Vector3 = mid + side * wide * sgn + Vector3.DOWN * 0.08
			PaperMesh.tri(st, a, b, tip, color, mid + Vector3.DOWN)


static func bush_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)), Vector3(0.85, 0.55, 0.8), 9, 5, PaperMesh.col(BUSH_DARK), 0.14, rng)
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0.35, 0.55, 0.2)), Vector3(0.5, 0.42, 0.5), 8, 4, PaperMesh.col(BUSH), 0.12, rng)
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(-0.3, 0.5, -0.25)), Vector3(0.5, 0.4, 0.48), 8, 4, PaperMesh.col(BUSH), 0.12, rng)
	for i in range(6):
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 0.62, rng.randf_range(0.55, 0.85), sin(a) * 0.6)
		PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, p), Vector3.ONE * 0.09, 5, 3, PaperMesh.col(FLOWER))
	return PaperMesh.commit(st)


static func rock_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), Vector3(0.9, 0.65, 0.8), 7, 4, PaperMesh.col(STONE), 0.2, rng)
	return PaperMesh.commit(st)


static func tuft_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	var c := PaperMesh.col(DUNE_GRASS)
	for i in range(7):
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.15, 0.5))
		var off := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		PaperMesh.frustum(st, Transform3D(b, off), 0.025, 0.0, rng.randf_range(0.4, 0.7), 3, c, false)
	return PaperMesh.commit(st)


## A small fan shell lying on the sand.
static func shell_mesh() -> ArrayMesh:
	var st := PaperMesh.begin()
	var c := PaperMesh.col(SHELL)
	var n := 6
	for i in range(n):
		var a0 := PI * (0.15 + 0.7 * float(i) / n)
		var a1 := PI * (0.15 + 0.7 * float(i + 1) / n)
		PaperMesh.tri(st, Vector3(0, 0.02, -0.05), Vector3(cos(a0) * 0.12, 0.03, sin(a0) * 0.12 - 0.05), Vector3(cos(a1) * 0.12, 0.03 + (0.015 if i % 2 == 0 else 0.0), sin(a1) * 0.12 - 0.05), c, Vector3(0, -1, 0))
	return PaperMesh.commit(st)


## A five-armed starfish, flat on the sand.
static func starfish_mesh() -> ArrayMesh:
	var st := PaperMesh.begin()
	var c := PaperMesh.col(STARFISH)
	var center := Vector3(0, 0.035, 0)
	for i in range(10):
		var a0 := TAU * i / 10.0
		var a1 := TAU * (i + 1) / 10.0
		var r0 := 0.16 if i % 2 == 0 else 0.06
		var r1 := 0.06 if i % 2 == 0 else 0.16
		PaperMesh.tri(st, center, Vector3(cos(a0) * r0, 0.012, sin(a0) * r0), Vector3(cos(a1) * r1, 0.012, sin(a1) * r1), c, Vector3(0, -1, 0))
	return PaperMesh.commit(st)
