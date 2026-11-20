class_name Water
extends MeshInstance3D
## The sea: one grid at y = 0 out to the horizon, only where the ground is below or near it
## (no hidden water under the island: the phone pays per pixel). Depth is baked into the
## vertex alpha for shaders/water.gdshader.

const SIZE := 220.0
const CELLS := 90
const DEPTH_FULL := 2.4    ## metres of water that count as "deep"


func _ready() -> void:
	mesh = build_mesh()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func depth_at(x: float, z: float) -> float:
	return clampf(-Terrain.height(x, z) / DEPTH_FULL, 0.0, 1.0)


static func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var step := SIZE / CELLS
	var half := SIZE * 0.5
	var w := CELLS + 1
	var heights := PackedFloat32Array()
	for j in range(w):
		for i in range(w):
			var x := -half + i * step
			var z := -half + j * step
			var h := Terrain.height(x, z) if absf(x) < Terrain.SIZE * 0.5 and absf(z) < Terrain.SIZE * 0.5 else -3.0
			heights.append(h)
			verts.append(Vector3(x, 0, z))
			norms.append(Vector3.UP)
			cols.append(Color(1, 1, 1, clampf(-h / DEPTH_FULL, 0.0, 1.0)))
	for j in range(CELLS):
		for i in range(CELLS):
			var p00 := j * w + i
			var p10 := p00 + 1
			var p01 := p00 + w
			var p11 := p01 + 1
			var lowest := minf(minf(heights[p00], heights[p10]), minf(heights[p01], heights[p11]))
			if lowest > 0.15:
				continue   # all ground here: no water to draw
			idx.append_array([p00, p10, p01, p10, p11, p01])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
