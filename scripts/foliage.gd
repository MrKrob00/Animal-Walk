class_name Foliage
extends RefCounted
## The island's green (the player: grass, trees, leaves, wind for a pretty picture): thick grass
## in clumps over the meadows (thinner in the woods and the scrub, none on the paths or the sand),
## flowers among it, broadleaf trees in paper in Herm's woods; all in the wind (foliage.gdshader).
## Grass is drawn only near the camera and sinks into the ground with distance (no popping, no
## transparency): the phone pays for what is close.

const SHADER := preload("res://shaders/foliage.gdshader")
const CHUNK := 20.0          ## grass pieces, metres
const GRASS_NEAR := 13.0     ## grass starts sinking this far from the camera
const GRASS_FAR := 20.0      ## ... and is gone here (about 1500 clumps, 30k triangles in view)
const PER_CELL := 2.6        ## clumps per 2 m cell of meadow (about one per 1.5 m^2)
const BLADE := "#5f9e45"
const BLADE_TIP := "#a9cf6a"
const BLADE_DRY := "#b6b763"

static var _mats := {}


## A wind material: "grass" (short, fades with distance), "bush", "palm", "tree_paper", "flower";
## `tex`: a texture to draw instead of the vertex colours (none use one now).
static func material(kind: String, tex: Texture2D = null) -> ShaderMaterial:
	var key := kind + (str(tex.get_rid()) if tex != null else "")
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("grain", PaperMesh.material().get_shader_parameter("grain"))
	match kind:
		"grass":
			m.set_shader_parameter("sway_height", 0.45)
			m.set_shader_parameter("wind_strength", 0.13)
			m.set_shader_parameter("flutter", 0.025)
			m.set_shader_parameter("fade_near", GRASS_NEAR)
			m.set_shader_parameter("fade_far", GRASS_FAR)
			m.set_shader_parameter("tip_light", 0.55)
		"flower":
			m.set_shader_parameter("sway_height", 0.4)
			m.set_shader_parameter("wind_strength", 0.1)
			m.set_shader_parameter("fade_near", GRASS_NEAR)
			m.set_shader_parameter("fade_far", GRASS_FAR)
		"bush":
			m.set_shader_parameter("sway_height", 1.0)
			m.set_shader_parameter("wind_strength", 0.05)
			m.set_shader_parameter("flutter", 0.012)
		"palm":
			m.set_shader_parameter("sway_height", 4.5)
			m.set_shader_parameter("wind_strength", 0.3)
			m.set_shader_parameter("flutter", 0.05)
		"tree_paper":
			m.set_shader_parameter("sway_height", 4.5)
			m.set_shader_parameter("wind_strength", 0.16)
			m.set_shader_parameter("flutter", 0.035)
	_mats[key] = m
	return m


## A clump of grass blades (each a tapering, slightly bent strip), roots dark, tips light.
static func grass_mesh(rng: RandomNumberGenerator, blades := 9, dry := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.35
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := rng.randf_range(0.28, 0.55)
		var w := rng.randf_range(0.035, 0.055)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.16)
		var side := Vector3(-sin(a + 1.4), 0, cos(a + 1.4)) * w
		var mid := base + lean * 0.4 + Vector3(0, h * 0.55, 0)
		var top := base + lean + Vector3(0, h, 0)
		var c0 := PaperMesh.col(BLADE).darkened(0.25)
		var c1 := PaperMesh.col(BLADE).lerp(PaperMesh.col(BLADE_DRY), 0.5 if dry else rng.randf() * 0.25)
		var c2 := PaperMesh.col(BLADE_TIP).lerp(PaperMesh.col(BLADE_DRY), 0.6 if dry else rng.randf() * 0.3)
		var n := side.cross(Vector3.UP).normalized()
		for v in [[base - side, c0], [base + side, c0], [mid + side * 0.6, c1], [base - side, c0], [mid + side * 0.6, c1], [mid - side * 0.6, c1], [mid - side * 0.6, c1], [mid + side * 0.6, c1], [top, c2]]:
			st.set_color(v[1])
			st.set_normal((n + Vector3.UP * 0.8).normalized())
			st.add_vertex(v[0])
	return st.commit()


## A few flowers on stems: five-petalled discs in one colour per flower.
static func flower_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colours := ["#f6f2ea", "#f3d64e", "#ee8fb0", "#b69ae6"]
	for f in 3:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.2
		var h := rng.randf_range(0.22, 0.4)
		var top := base + Vector3(rng.randf_range(-0.04, 0.04), h, rng.randf_range(-0.04, 0.04))
		var stem := PaperMesh.col(BLADE)
		for v in [[base + Vector3(-0.01, 0, 0), stem], [base + Vector3(0.01, 0, 0), stem], [top, stem]]:
			st.set_color(v[1])
			st.set_normal(Vector3.BACK)
			st.add_vertex(v[0])
		var col := PaperMesh.col(colours[rng.randi() % colours.size()])
		var r := rng.randf_range(0.04, 0.06)
		for p in 5:
			var t0 := p * TAU / 5.0
			var t1 := t0 + TAU / 5.0 * 0.8
			for v in [top, top + Vector3(cos(t0), 0.15, sin(t0)) * r, top + Vector3(cos(t1), 0.15, sin(t1)) * r]:
				st.set_color(col if v != top else PaperMesh.col("#f0c23a"))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	return st.commit()


## Grass and flowers over the island, in CHUNK pieces drawn within GRASS_FAR of the camera:
## clumps by what each 2 m cell of the island's grid is (meadows thickest, then the village green,
## scrub and the woods' floor; none on the sand, near the water or on the paths). Returns how many.
## `placed` (when `record`): where each clump stands (for the tests: a MultiMesh keeps no
## transforms without a screen).
static var placed := PackedVector2Array()

static func grow(root: Node3D, seed_value := 77, record := false) -> int:
	placed.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var meshes := [grass_mesh(rng), grass_mesh(rng, 9, true), flower_mesh(rng)]
	var d := Terrain.data()
	var m: Dictionary = d.meta
	var nx: int = int(m.nx)
	var nz: int = int(m.nz)
	var cell: float = float(m.cell)
	var x0: float = float(m.x0)
	var z0: float = float(m.z0)
	var density := {1: 1.0, 5: 0.7, 4: 0.6, 3: 0.35}
	var cells := {}   # Vector2i -> [grass, dry grass, flowers] transforms
	var count := 0
	for j in nz:
		for i in nx:
			var idx := j * nx + i
			var k: int = d.kind[idx]
			if not density.has(k) or d.shore[idx] < 2.5:
				continue
			var n := PER_CELL * float(density[k])
			var whole := int(n) + (1 if rng.randf() < n - int(n) else 0)
			for c in whole:
				var p := Vector2(x0 + (i + rng.randf() - 0.5) * cell, z0 + (j + rng.randf() - 0.5) * cell)
				if Terrain.on_path(p.x, p.y):
					continue
				var y := Terrain.height(p.x, p.y)
				var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
				if not cells.has(key):
					cells[key] = [[], [], []]
				var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), Vector3(p.x, y - 0.02, p.y))
				var which := 0
				if k == 1 and rng.randf() < 0.05:
					which = 2
				elif y > 9.0 and rng.randf() < 0.5:
					which = 1   # drier up on the tops
				cells[key][which].append(t)
				count += 1
				if record:
					placed.append(p)
	var group := Node3D.new()
	group.name = "Grass"
	root.add_child(group)
	for key in cells:
		for i in 3:
			var list: Array = cells[key][i]
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[i]
			mm.instance_count = list.size()
			for j in list.size():
				mm.set_instance_transform(j, list[j])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = material("flower" if i == 2 else "grass")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = GRASS_FAR + CHUNK * 0.71   # the piece's far corner within reach
			group.add_child(mi)
	return count


## A broadleaf tree in paper (Herm's woods are oak, ash and sycamore; KayKit's are pines): a
## tapering trunk with two or three branches and a crown of overlapping leafy lumps in a few greens.
static func tree_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := PaperMesh.begin()
	var bark := PaperMesh.col("#7a5a3e")
	var greens := ["#4f8f45", "#5fa04c", "#467f3e", "#6aa955"]
	var h := rng.randf_range(2.2, 3.0)
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0)), rng.randf_range(0.2, 0.26), 0.13, h + 0.2, 7, bark)
	var top := Vector3(0, h, 0)
	for b in rng.randi_range(2, 3):
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a) * 0.8, 1.0, sin(a) * 0.8).normalized()
		var at := Vector3(0, h * rng.randf_range(0.6, 0.85), 0)
		PaperMesh.frustum(st, Transform3D(Basis(Quaternion(Vector3.UP, dir)), at), 0.09, 0.05, 1.1, 5, bark)
	var crown := top + Vector3(0, 0.9, 0)
	for i in rng.randi_range(6, 8):
		var a := i * TAU / 7.0 + rng.randf() * 0.5
		var off := Vector3(cos(a), rng.randf_range(-0.3, 0.5), sin(a)) * rng.randf_range(0.7, 1.2)
		if i == 0:
			off = Vector3(0, 0.6, 0)
		var r := rng.randf_range(0.9, 1.35)
		PaperMesh.ellipsoid(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), crown + off), Vector3(r, r * 0.8, r), 6, 3, PaperMesh.col(greens[rng.randi() % greens.size()]), 0.18, rng)   # 6 x 3: about 30 triangles a lump
	return PaperMesh.commit(st)
