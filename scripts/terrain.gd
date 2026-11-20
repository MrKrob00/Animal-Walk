class_name Terrain
extends RefCounted
## The island: grassy hills in the middle, a sand beach around, wet sand at the waterline,
## and the sea floor dropping away beyond an uneven shore. Water level is y = 0.
## Height is a plain function, so walkers stand on it without physics.

const PLAY_RADIUS := 34.0   ## nothing walks beyond this, whatever the shore does
const SIZE := 96.0          ## ground mesh side, metres
const CELLS := 80           ## ground mesh cells per side
const DRY := 0.95           ## walkers stay inside this share of the shore radius (dry feet)

const GRASS := "#8cbf6a"
const GRASS_DEEP := "#6fa457"
const SAND := "#f3e4bf"
const WET_SAND := "#d9c197"
const SEABED := "#c9b48a"
const ROCK := "#a99c8a"


## Distance from the centre to the waterline in direction `ang` (radians): a wobbly circle.
static func shore(ang: float) -> float:
	return 30.0 + 2.5 * sin(ang * 3.0 + 0.5) + 1.5 * sin(ang * 5.0 + 2.0) + 1.0 * sin(ang * 7.0 + 4.0)


## 0 at the centre, 1 at the waterline, more out at sea.
static func shore_share(x: float, z: float) -> float:
	return sqrt(x * x + z * z) / shore(atan2(z, x))


static func height(x: float, z: float) -> float:
	var d := shore_share(x, z)
	var land := 1.0 - smoothstep(0.45, 1.0, d)
	var hills := 1.25 + 0.55 * sin(x * 0.17 + 1.0) + 0.45 * cos(z * 0.15) + 0.3 * sin((x - z) * 0.23)
	return hills * pow(land, 1.25) - 2.6 * smoothstep(1.0, 1.45, d)


static func normal(x: float, z: float) -> Vector3:
	var e := 0.25
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


## Keeps a walker on dry land: pulls `p` back inside the shore.
static func keep_on_island(p: Vector2) -> Vector2:
	var ang := atan2(p.y, p.x)
	var limit := minf(shore(ang) * DRY, PLAY_RADIUS)
	return p.normalized() * limit if p.length() > limit else p


## The ground colour at a height and slope: grass up high, sand on the beach, wet at the sea.
static func ground_color(y: float, n: Vector3) -> Color:
	var c := PaperMesh.col(SAND)
	c = c.lerp(PaperMesh.col(WET_SAND), smoothstep(0.22, 0.04, y))
	c = c.lerp(PaperMesh.col(SEABED), smoothstep(-0.05, -0.6, y))
	var grass := PaperMesh.col(GRASS).lerp(PaperMesh.col(GRASS_DEEP), smoothstep(1.8, 2.4, y))
	c = c.lerp(grass, smoothstep(1.3, 1.6, y))   # grass only on the hilltops: mostly beach
	return c.lerp(PaperMesh.col(ROCK), smoothstep(0.8, 0.62, n.y))


## Smooth (not faceted) ground mesh with colours baked into the vertices.
static func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
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
			cols.append(ground_color(y, n))
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
