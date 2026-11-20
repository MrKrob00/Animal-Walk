class_name Terrain
extends RefCounted
## The island, big enough to explore (about 220 m across): grassy hills and meadows inside,
## a sand beach all round with bays and headlands, wet sand at the waterline, and the sea
## floor dropping away past the shore. Water level is y = 0. Walkers may wade in up to
## their ankles (WADE_DEPTH). Height is a plain function, so walkers stand on it without physics.

const PLAY_RADIUS := 160.0  ## nothing walks beyond this, whatever the shore does
const SIZE := 330.0         ## ground mesh side, metres
const CELLS := 165          ## ground mesh cells per side (2 m)
const WADE_DEPTH := 0.12    ## how deep walkers may go into the sea (ankle deep), metres
const BEACH := 0.86         ## share of the shore radius where the beach begins
const SHELF_SLOPE := 0.045  ## the sea floor drops this many metres per metre near the shore
const BEACH_SLOPE := 0.035  ## the beach rises this many metres per metre from the waterline

const GRASS := "#8cbf6a"
const GRASS_DEEP := "#6fa457"
const SAND := "#f3e4bf"
const WET_SAND := "#d9c197"
const SEABED := "#c9b48a"
const ROCK := "#a99c8a"

static var _hills: FastNoiseLite


## Distance from the centre to the waterline in direction `ang` (radians): bays and headlands.
static func shore(ang: float) -> float:
	return 110.0 + 14.0 * sin(ang * 2.0 + 0.3) + 9.0 * sin(ang * 3.0 + 1.1) + 6.0 * sin(ang * 5.0 + 2.0) \
		+ 4.0 * sin(ang * 8.0 + 0.7) + 2.5 * sin(ang * 13.0 + 3.0)


## 0 at the centre, 1 at the waterline, more out at sea.
static func shore_share(x: float, z: float) -> float:
	return sqrt(x * x + z * z) / shore(atan2(z, x))


static func _noise() -> FastNoiseLite:
	if _hills == null:
		_hills = FastNoiseLite.new()
		_hills.seed = 1120
		_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_hills.frequency = 0.011
		_hills.fractal_octaves = 4
	return _hills


static func height(x: float, z: float) -> float:
	var d := shore_share(x, z)
	var land := 1.0 - smoothstep(BEACH, 1.0, d)
	var n := _noise().get_noise_2d(x, z)
	var hills := 0.9 + 7.0 * maxf(0.0, n + 0.1) + 0.6 * n
	var r := shore(atan2(z, x))
	var out := maxf(0.0, (d - 1.0) * r)    # metres out past the waterline
	var inland := maxf(0.0, (1.0 - d) * r) # metres in from the waterline
	# The beach rises from the sea at a steady slope (no flat strip the swell could wash over).
	var beach := BEACH_SLOPE * minf(inland, 14.0)
	return maxf(hills, 0.25) * pow(land, 1.3) + beach - SHELF_SLOPE * out - 2.6 * smoothstep(3.0, 25.0, out)


static func normal(x: float, z: float) -> Vector3:
	var e := 0.25
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


## How far past the waterline the sea is WADE_DEPTH deep, metres (the floor drops the same
## way all round, at SHELF_SLOPE, for the first few metres).
static func wade_distance() -> float:
	return WADE_DEPTH / SHELF_SLOPE


## Keeps a walker on the island or in ankle-deep water: pulls `p` back toward the shore.
static func keep_on_island(p: Vector2) -> Vector2:
	var ang := atan2(p.y, p.x)
	var limit := minf(shore(ang) + wade_distance(), PLAY_RADIUS)
	return p.normalized() * limit if p.length() > limit else p


## The ground colour: sand on the beach and low ground, wet at the sea, grass on the hills.
static func ground_color(y: float, n: Vector3, share := 0.0) -> Color:
	var c := PaperMesh.col(SAND)
	c = c.lerp(PaperMesh.col(WET_SAND), smoothstep(0.22, 0.04, y))
	c = c.lerp(PaperMesh.col(SEABED), smoothstep(-0.05, -0.6, y))
	var grass := PaperMesh.col(GRASS).lerp(PaperMesh.col(GRASS_DEEP), smoothstep(2.5, 4.5, y))
	var grassy := smoothstep(1.0, 1.4, y) * (1.0 - smoothstep(BEACH - 0.06, BEACH + 0.02, share))
	c = c.lerp(grass, grassy)
	return c.lerp(PaperMesh.col(ROCK), smoothstep(0.78, 0.6, n.y))


## Smooth (not faceted) ground mesh with colours baked into the vertices.
static func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var step := SIZE / CELLS
	var half := SIZE * 0.5
	var w := CELLS + 1
	var hs := PackedFloat32Array()
	hs.resize(w * w)
	for j in range(w):
		for i in range(w):
			hs[j * w + i] = height(-half + i * step, -half + j * step)
	for j in range(w):
		for i in range(w):
			var x := -half + i * step
			var z := -half + j * step
			var y := hs[j * w + i]
			# Normal from the neighbours already computed (cheap: no extra noise samples).
			var hl := hs[j * w + maxi(i - 1, 0)]
			var hr := hs[j * w + mini(i + 1, CELLS)]
			var hd := hs[maxi(j - 1, 0) * w + i]
			var hu := hs[mini(j + 1, CELLS) * w + i]
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			verts.append(Vector3(x, y, z))
			norms.append(n)
			cols.append(ground_color(y, n, shore_share(x, z)))
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
