class_name WorldBuilder
extends RefCounted
## Scatters paper firs, birches, bushes, rocks and dry grass over the terrain.
## Each kind is one MultiMesh (one draw call), all with the shared paper material.

const NEEDLES := "#3f7472"
const NEEDLES_UNDER := "#2a4d52"
const SNOW := "#f3f6fb"
const TRUNK := "#5a3f33"
const BIRCH := "#eeeae2"
const BIRCH_MARK := "#3b3536"
const BUSH := "#3f6f6a"
const STONE := "#8c8a99"
const GRASS := "#c4a77d"

## Spawn clearing: nothing grows here so the start is open.
const CLEARING_CENTER := Vector2(0, 2)
const CLEARING_RADIUS := 6.5


## Fills `root` and returns obstacles as Vector3(x, z, radius).
static func populate(root: Node3D, seed_value := 20261115) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kinds := {"fir": [], "birch": [], "bush": [], "rock": []}
	var placed: Array[Vector3] = []
	var obstacles: Array[Vector3] = []
	var spacing := {"fir": 2.4, "birch": 1.5, "bush": 1.6, "rock": 1.8}
	var block := {"fir": 0.45, "birch": 0.22, "bush": 0.75, "rock": 0.85}
	for i in range(1400):
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * (Terrain.PLAY_RADIUS + 16.0)
		var x := cos(ang) * rad
		var z := sin(ang) * rad
		if Vector2(x, z).distance_to(CLEARING_CENTER) < CLEARING_RADIUS:
			continue
		var roll := rng.randf()
		var kind := "fir" if roll < 0.45 else ("birch" if roll < 0.56 else ("bush" if roll < 0.78 else "rock"))
		if kind != "rock" and Terrain.normal(x, z).y < 0.6:
			continue
		var sp: float = spacing[kind]
		var ok := true
		for p in placed:
			if Vector2(p.x, p.y).distance_to(Vector2(x, z)) < (sp + p.z) * 0.6:
				ok = false
				break
		if not ok:
			continue
		var s := rng.randf_range(0.8, 1.3)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if kind == "rock":
			s = rng.randf_range(0.7, 1.8)
			basis = basis.scaled(Vector3(s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.8, 1.3)))
		else:
			basis = basis.scaled(Vector3.ONE * s)
		kinds[kind].append(Transform3D(basis, Vector3(x, Terrain.height(x, z) - 0.1, z)))
		placed.append(Vector3(x, z, sp))
		if rad < Terrain.PLAY_RADIUS + 3.0:
			obstacles.append(Vector3(x, z, block[kind] * s))
	var tufts: Array = []
	for i in range(260):
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * (Terrain.PLAY_RADIUS + 4.0)
		var x := cos(ang) * rad
		var z := sin(ang) * rad
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
		tufts.append(Transform3D(basis, Vector3(x, Terrain.height(x, z) - 0.05, z)))
	_add_multimesh(root, "Firs", fir_mesh(rng), kinds["fir"])
	_add_multimesh(root, "Birches", birch_mesh(rng), kinds["birch"])
	_add_multimesh(root, "Bushes", bush_mesh(rng), kinds["bush"])
	_add_multimesh(root, "Rocks", rock_mesh(rng), kinds["rock"])
	_add_multimesh(root, "Grass", tuft_mesh(rng), tufts)
	return obstacles


static func _add_multimesh(root: Node3D, node_name: String, mesh: Mesh, xforms: Array) -> void:
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
	root.add_child(mmi)


static func fir_mesh(_rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	var needles := PaperMesh.col(NEEDLES)
	var under := PaperMesh.col(NEEDLES_UNDER)
	var snow := PaperMesh.col(SNOW)
	PaperMesh.frustum(st, Transform3D.IDENTITY, 0.2, 0.1, 1.2, 6, PaperMesh.col(TRUNK))
	for i in range(4):
		var y := 0.8 + i * 0.85
		var r := 1.5 - i * 0.32
		var h := 1.35 - i * 0.12
		var twist := Basis(Vector3.UP, i * 0.6)
		PaperMesh.jagged_cone(st, Transform3D(twist, Vector3(0, y, 0)), r, h, 9, needles, under, 0.12)
		PaperMesh.jagged_cone(st, Transform3D(twist.rotated(Vector3.UP, 0.17), Vector3(0, y + h * 0.38, 0)), r * 0.7, h * 0.64, 9, snow, under, 0.06)
	return PaperMesh.commit(st)


static func birch_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	var white := PaperMesh.col(BIRCH)
	var mark := PaperMesh.col(BIRCH_MARK)
	var y := 0.0
	var r := 0.16
	for i in range(12):
		var h := 0.42 if i % 3 != 2 else 0.1
		var r2 := r * 0.94
		PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), r, r2, h, 6, white if i % 3 != 2 else mark, false)
		y += h
		r = r2
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), r, 0.0, 0.8, 6, white)
	for i in range(6):
		var by := 2.2 + i * 0.45
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.7, 1.1))
		PaperMesh.frustum(st, Transform3D(b, Vector3(0, by, 0)), 0.04, 0.0, rng.randf_range(0.7, 1.2), 3, mark)
	return PaperMesh.commit(st)


static func bush_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), Vector3(0.9, 0.48, 0.9), 9, 5, PaperMesh.col(BUSH), 0.12, rng)
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(0.82, 0.34, 0.82), 9, 4, PaperMesh.col(SNOW), 0.1, rng)
	return PaperMesh.commit(st)


static func rock_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), Vector3(0.9, 0.65, 0.8), 7, 4, PaperMesh.col(STONE), 0.18, rng)
	PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0.05, 0.72, 0)), Vector3(0.7, 0.24, 0.62), 7, 3, PaperMesh.col(SNOW), 0.1, rng)
	return PaperMesh.commit(st)


static func tuft_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	var c := PaperMesh.col(GRASS)
	for i in range(6):
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.1, 0.45))
		var off := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		PaperMesh.frustum(st, Transform3D(b, off), 0.03, 0.0, rng.randf_range(0.35, 0.6), 3, c, false)
	return PaperMesh.commit(st)
