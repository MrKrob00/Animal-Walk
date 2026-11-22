class_name Water
extends MeshInstance3D
## The sea: one grid at y = 0 out to the horizon, only where the ground is below or near it
## (no hidden water under the island: the phone pays per pixel). The signed depth in metres
## (negative under the land) is baked into UV.x, so the foam line falls exactly on the waterline
## even though the grid is coarse.

const STEP := 4.0           ## metres per cell over the island's grid (the foam line follows it)
const FAR := 1500.0        ## the open sea reaches this far from the island, as a frame of big quads
const DEPTH_FULL := 2.4    ## metres of water that count as "deep" (the shader: foam under 3 cm)


func _ready() -> void:
	mesh = build_mesh()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func depth_at(x: float, z: float) -> float:
	return clampf(-Terrain.height(x, z) / DEPTH_FULL, 0.0, 1.0)


## A STEP grid over the island's grid (only cells with water in them; UV.y = 1 lets the swell move
## it, 0 on its outer edge) and round it a frame of four big flat quads out to FAR (deep, still):
## the edge vertices do not move, so no crack opens between the two.
static func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var r := Terrain.bounds()
	var nx := ceili(r.size.x / STEP)
	var nz := ceili(r.size.y / STEP)
	var w := nx + 1
	var heights := PackedFloat32Array()
	for j in range(nz + 1):
		for i in range(nx + 1):
			var x := r.position.x + i * STEP
			var z := r.position.y + j * STEP
			var h := Terrain.height(x, z)
			var edge := i == 0 or j == 0 or i == nx or j == nz
			heights.append(h)
			verts.append(Vector3(x, 0, z))
			norms.append(Vector3.UP)
			uvs.append(Vector2(-h, 0.0 if edge else 1.0))
	for j in range(nz):
		for i in range(nx):
			var p00 := j * w + i
			var p10 := p00 + 1
			var p01 := p00 + w
			var p11 := p01 + 1
			var lowest := minf(minf(heights[p00], heights[p10]), minf(heights[p01], heights[p11]))
			if lowest > 0.15:
				continue   # all ground here: no water to draw
			idx.append_array([p00, p10, p01, p10, p11, p01])
	# The frame: four quads from the grid's edge out to FAR.
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.position.x + nx * STEP
	var z1 := r.position.y + nz * STEP
	var ox := r.get_center().x
	var oz := r.get_center().y
	var rects := [
		[ox - FAR, oz - FAR, ox + FAR, z0], [ox - FAR, z1, ox + FAR, oz + FAR],
		[ox - FAR, z0, x0, z1], [x1, z0, ox + FAR, z1]]
	for q in rects:
		var b := verts.size()
		for c in [[q[0], q[1]], [q[2], q[1]], [q[0], q[3]], [q[2], q[3]]]:
			verts.append(Vector3(c[0], 0, c[1]))
			norms.append(Vector3.UP)
			uvs.append(Vector2(-Terrain.DEEP, 0.0))
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
