class_name Terrain
extends RefCounted
## The snowy ground: a gentle walkable bowl ringed by mountain slopes.
## Height is a plain function, so walkers stand on it without physics.

const PLAY_RADIUS := 30.0   # walkers stay inside this circle
const SIZE := 140.0         # mesh side, metres
const CELLS := 100          # mesh cells per side

const SNOW := "#f4f6fb"
const SNOW_HOLLOW := "#e6ebf6"
const ROCK := "#8a8798"


static func height(x: float, z: float) -> float:
	var h := 0.55 * sin(x * 0.13) + 0.45 * cos(z * 0.11 + 1.3) + 0.3 * sin((x + z) * 0.21 + 0.4)
	var r := sqrt(x * x + z * z)
	var rim := smoothstep(PLAY_RADIUS + 2.0, PLAY_RADIUS + 28.0, r)
	var ang := atan2(z, x)
	var ridge := 1.0 + 0.35 * sin(ang * 5.0 + 0.7) + 0.2 * sin(ang * 11.0 + 2.0)
	return h + rim * rim * 26.0 * ridge


static func normal(x: float, z: float) -> Vector3:
	var e := 0.25
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


## Smooth (not faceted) mesh: soft snow. Steep slopes turn to rock.
static func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var snow := PaperMesh.col(SNOW)
	var hollow := PaperMesh.col(SNOW_HOLLOW)
	var rock := PaperMesh.col(ROCK)
	var step := SIZE / CELLS
	var half := SIZE * 0.5
	for j in range(CELLS + 1):
		for i in range(CELLS + 1):
			var x := -half + i * step
			var z := -half + j * step
			var y := height(x, z)
			var n := normal(x, z)
			verts.append(Vector3(x, y, z))
			norms.append(n)
			var c := snow.lerp(hollow, clampf(-y * 0.6, 0.0, 1.0))
			c = c.lerp(rock, smoothstep(0.82, 0.62, n.y))
			cols.append(c)
	var w := CELLS + 1
	for j in range(CELLS):
		for i in range(CELLS):
			var p00 := j * w + i
			var p10 := p00 + 1
			var p01 := p00 + w
			var p11 := p01 + 1
			# Clockwise seen from above (Godot front faces).
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
