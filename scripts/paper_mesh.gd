class_name PaperMesh
extends RefCounted
## Builds faceted "paper-craft" meshes: flat faces, one vertex colour per face.
## All shapes share one material (shaders/paper.gdshader), so colour lives in vertices.

static var _material: ShaderMaterial


## The one paper material shared by every mesh (one material = cheap on the phone).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/paper.gdshader")
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.06
		noise.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.generate_mipmaps = true
		tex.noise = noise
		_material.set_shader_parameter("grain", tex)
	return _material


## Colour from an sRGB hex string, converted for vertex colours (shader works in linear).
static func col(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func commit(st: SurfaceTool) -> ArrayMesh:
	return st.commit()


## One flat triangle facing away from `inside`. Godot draws clockwise faces as front.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - inside) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	n = n.normalized()
	for v in [a, c, b]:
		st.set_color(color)
		st.set_normal(n)
		st.add_vertex(v)


## Low-poly ellipsoid. `jitter` moves inner rings in and out for a hand-folded look.
static func ellipsoid(st: SurfaceTool, xf: Transform3D, radii: Vector3, segs: int, rings: int,
		color: Color, jitter := 0.0, rng: RandomNumberGenerator = null) -> void:
	var grid: Array[PackedVector3Array] = []
	for r in range(rings + 1):
		var phi := PI * float(r) / rings
		var row := PackedVector3Array()
		for s in range(segs):
			var th := TAU * float(s) / segs
			var p := Vector3(sin(phi) * cos(th) * radii.x, cos(phi) * radii.y, sin(phi) * sin(th) * radii.z)
			if jitter > 0.0 and rng != null and r > 0 and r < rings:
				p *= 1.0 + rng.randf_range(-jitter, jitter)
			row.append(xf * p)
		grid.append(row)
	var center := xf * Vector3.ZERO
	for r in range(rings):
		for s in range(segs):
			var s2 := (s + 1) % segs
			var a := grid[r][s]
			var b := grid[r][s2]
			var c := grid[r + 1][s]
			var d := grid[r + 1][s2]
			if r == 0:
				tri(st, a, c, d, color, center)
			elif r == rings - 1:
				tri(st, a, b, c, color, center)
			else:
				tri(st, a, b, c, color, center)
				tri(st, b, d, c, color, center)


## Tapered cylinder along local +Y from 0 to h. r1 = 0 makes a cone.
static func frustum(st: SurfaceTool, xf: Transform3D, r0: float, r1: float, h: float, segs: int,
		color: Color, caps := true) -> void:
	var inside := xf * Vector3(0, h * 0.5, 0)
	var ring0 := PackedVector3Array()
	var ring1 := PackedVector3Array()
	for s in range(segs):
		var th := TAU * float(s) / segs
		ring0.append(xf * Vector3(cos(th) * r0, 0, sin(th) * r0))
		ring1.append(xf * Vector3(cos(th) * r1, h, sin(th) * r1))
	var apex := xf * Vector3(0, h, 0)
	var base := xf * Vector3.ZERO
	for s in range(segs):
		var s2 := (s + 1) % segs
		if r1 <= 0.0:
			tri(st, ring0[s], ring0[s2], apex, color, inside)
		else:
			tri(st, ring0[s], ring0[s2], ring1[s], color, inside)
			tri(st, ring0[s2], ring1[s2], ring1[s], color, inside)
		if caps:
			tri(st, base, ring0[s], ring0[s2], color, inside)
			if r1 > 0.0:
				tri(st, apex, ring1[s], ring1[s2], color, inside)


## Cone with a zig-zag paper edge (a fir tier or a snow cap). Underside gets `under`.
static func jagged_cone(st: SurfaceTool, xf: Transform3D, r: float, h: float, teeth: int,
		color: Color, under: Color, droop := 0.08) -> void:
	var inside := xf * Vector3(0, h * 0.3, 0)
	var ring := PackedVector3Array()
	for i in range(teeth * 2):
		var th := TAU * float(i) / (teeth * 2)
		var rr := r if i % 2 == 0 else r * 0.72
		var y := -droop if i % 2 == 0 else 0.0
		ring.append(xf * Vector3(cos(th) * rr, y, sin(th) * rr))
	var apex := xf * Vector3(0, h, 0)
	var base := xf * Vector3.ZERO
	for i in range(ring.size()):
		var j := (i + 1) % ring.size()
		tri(st, ring[i], ring[j], apex, color, inside)
		tri(st, base, ring[i], ring[j], under, inside)


## Flat oval lying on the ground, facing up.
static func disc(st: SurfaceTool, xf: Transform3D, rx: float, rz: float, segs: int, color: Color) -> void:
	var inside := xf * Vector3(0, -1, 0)
	var center := xf * Vector3.ZERO
	for s in range(segs):
		var a := TAU * float(s) / segs
		var b := TAU * float(s + 1) / segs
		tri(st, center, xf * Vector3(cos(a) * rx, 0, sin(a) * rz), xf * Vector3(cos(b) * rx, 0, sin(b) * rz), color, inside)
