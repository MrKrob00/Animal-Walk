class_name WorldBuilder
extends RefCounted
## Dresses the island: paper palms, flowering bushes, rocks, dune grass, and shells and
## starfish on the sand. Each kind is one MultiMesh (one draw call) with the paper material.

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

## Spawn clearing: nothing grows here so the start is open.
const CLEARING_CENTER := Vector2(0, -20)   # the start, on the north beach
const CLEARING_RADIUS := 6.5


## Fills `root` and returns obstacles as Vector3(x, z, radius).
static func populate(root: Node3D, seed_value := 20261120) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kinds := {"palm": [], "bush": [], "rock": []}
	var placed: Array[Vector3] = []
	var obstacles: Array[Vector3] = []
	var spacing := {"palm": 4.2, "bush": 2.0, "rock": 2.0}
	var block := {"palm": 0.32, "bush": 0.75, "rock": 0.8}
	for i in range(1600):
		var ang := rng.randf() * TAU
		var x := 0.0
		var z := 0.0
		var d := sqrt(rng.randf()) * 1.08
		x = cos(ang) * d * Terrain.shore(ang)
		z = sin(ang) * d * Terrain.shore(ang)
		if Vector2(x, z).distance_to(CLEARING_CENTER) < CLEARING_RADIUS:
			continue
		var roll := rng.randf()
		var kind := "palm" if roll < 0.5 else ("bush" if roll < 0.86 else "rock")
		# Palms on the beach and lower hills, bushes inland, rocks anywhere up to the surf.
		if kind == "palm" and (d < 0.3 or d > 0.92):
			continue
		if kind == "bush" and (d > 0.78 or Terrain.height(x, z) < 1.1):
			continue   # bushes grow on the grassy hilltops
		if kind == "rock" and d < 0.4:
			continue
		var sp: float = spacing[kind]
		var ok := true
		for p in placed:
			if Vector2(p.x, p.y).distance_to(Vector2(x, z)) < (sp + p.z) * 0.6:
				ok = false
				break
		if not ok:
			continue
		var s := rng.randf_range(0.85, 1.25)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if kind == "rock":
			s = rng.randf_range(0.45, 1.0)
			basis = basis.scaled(Vector3(s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.7, 1.1), s * rng.randf_range(0.8, 1.2)))
		else:
			basis = basis.scaled(Vector3.ONE * s)
		var y := Terrain.height(x, z) - 0.08
		kinds[kind].append(Transform3D(basis, Vector3(x, y, z)))
		placed.append(Vector3(x, z, sp))
		if y > -0.3:
			obstacles.append(Vector3(x, z, block[kind] * s))
	var tufts: Array = []
	var shells: Array = []
	var stars: Array = []
	for i in range(700):
		var ang := rng.randf() * TAU
		var d := rng.randf_range(0.3, 0.99)
		var x := cos(ang) * d * Terrain.shore(ang)
		var z := sin(ang) * d * Terrain.shore(ang)
		var y := Terrain.height(x, z)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if d < 0.9 and i < 260:
			tufts.append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)), Vector3(x, y - 0.04, z)))
		elif d > 0.86 and y < 0.35 and y > 0.02:
			var t := Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.2)), Vector3(x, y + 0.01, z))
			if rng.randf() < 0.7:
				shells.append(t)
			else:
				stars.append(t)
	_add_multimesh(root, "Palms", palm_mesh(rng), kinds["palm"])
	_add_multimesh(root, "Bushes", bush_mesh(rng), kinds["bush"])
	_add_multimesh(root, "Rocks", rock_mesh(rng), kinds["rock"])
	_add_multimesh(root, "DuneGrass", tuft_mesh(rng), tufts)
	_add_multimesh(root, "Shells", shell_mesh(), shells, false)
	_add_multimesh(root, "Starfish", starfish_mesh(), stars, false)
	return obstacles


static func _add_multimesh(root: Node3D, node_name: String, mesh: Mesh, xforms: Array, shadows := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = PaperMesh.material()
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


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
	return


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
		var tip := Vector3(0, 0.05, 0.1)
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
