class_name Terrain
extends RefCounted
## The island: Herm (Channel Islands) at 1:4 (the player chose it from a real map, so the paths
## and places to find come from it): about 480 x 575 m of it with its islets, heights from the
## Copernicus DEM (17.8 m at most), the coast, paths and places from OpenStreetMap (HermData,
## tools/herm/). Water level is y = 0; a sand beach rises from the sea at a steady slope and the
## sea floor drops away past the shore; walkers may wade in up to their ankles (WADE_DEPTH), and
## the sea all round is the island's wall. Height is sampled from a 2 m grid, so walkers stand on
## it without physics.

const DATA := "res://assets/herm/herm.res"
const WADE_DEPTH := 0.12    ## how deep walkers may go into the sea (ankle deep), metres
const SHELF_SLOPE := 0.045  ## the sea floor drops this many metres per metre near the shore (build_herm.py)
const BEACH_SLOPE := 0.035  ## the beach rises this many metres per metre from the waterline (build_herm.py)
const DEEP := -3.0          ## past the grid: open sea this deep
const CHUNK := 192.0        ## ground mesh pieces, metres (drawn only when seen; bigger: fewer draw calls)

const GRASS := "#8cbf6a"
const GRASS_DEEP := "#6fa457"
const SAND := "#f3e4bf"
const WET_SAND := "#d9c197"
const SEABED := "#c9b48a"
const ROCK := "#a99c8a"
const WOOD_FLOOR := "#5f9a4e"
const SCRUB := "#9bb25f"
const VILLAGE := "#b9c48a"

static var _d: HermData


static func data() -> HermData:
	if _d == null:
		_d = load(DATA)
	return _d


## The grid's corner and size, metres.
static func bounds() -> Rect2:
	var m: Dictionary = data().meta
	return Rect2(float(m.x0), float(m.z0), (int(m.nx) - 1) * float(m.cell), (int(m.nz) - 1) * float(m.cell))


static func _sample(arr: PackedFloat32Array, x: float, z: float, outside: float) -> float:
	var m: Dictionary = data().meta
	var nx: int = int(m.nx)
	var nz: int = int(m.nz)
	var fx := (x - float(m.x0)) / float(m.cell)
	var fz := (z - float(m.z0)) / float(m.cell)
	if fx < 0.0 or fz < 0.0 or fx > nx - 1 or fz > nz - 1:
		return outside
	var ix := mini(int(fx), nx - 2)
	var iz := mini(int(fz), nz - 2)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * nx + ix
	return lerpf(lerpf(arr[i], arr[i + 1], tx), lerpf(arr[i + nx], arr[i + nx + 1], tx), tz)


static func height(x: float, z: float) -> float:
	return _sample(data().height, x, z, DEEP)


## Metres to the coast: + inland, - out at sea.
static func shore_distance(x: float, z: float) -> float:
	return _sample(data().shore, x, z, -100.0)


## What the ground is at (x, z): 0 sea, 1 grass, 2 sand, 3 wood, 4 scrub, 5 village.
static func kind(x: float, z: float) -> int:
	var m: Dictionary = data().meta
	var ix := roundi((x - float(m.x0)) / float(m.cell))
	var iz := roundi((z - float(m.z0)) / float(m.cell))
	if ix < 0 or iz < 0 or ix >= int(m.nx) or iz >= int(m.nz):
		return 0
	return data().kind[iz * int(m.nx) + ix]


static func normal(x: float, z: float) -> Vector3:
	var e := 0.5
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


## How far past the waterline the sea is WADE_DEPTH deep, metres (the floor drops the same
## way all round, at SHELF_SLOPE, for the first few metres).
static func wade_distance() -> float:
	return WADE_DEPTH / SHELF_SLOPE


## Keeps a walker on the island or in ankle-deep water: pushes `p` back toward the shore, along
## the way the distance to the coast grows.
static func keep_on_island(p: Vector2) -> Vector2:
	var limit := -wade_distance()
	for i in 4:
		var d := shore_distance(p.x, p.y)
		if d >= limit:
			return p
		var e := 0.5
		var grad := Vector2(shore_distance(p.x + e, p.y) - shore_distance(p.x - e, p.y), shore_distance(p.x, p.y + e) - shore_distance(p.x, p.y - e))
		if grad.length() < 1e-4:
			return p.lerp(Vector2(bounds().get_center()), 0.02)   # past the grid: back toward the island
		p += grad.normalized() * (limit - d + 0.01)
	return p


## The ground colour: by what it is (grass, sand, wood floor, scrub, the village green), wet sand
## at the sea, the seabed under it, rock where it is steep.
static func ground_color(y: float, n: Vector3, k: int) -> Color:
	var c := PaperMesh.col(SAND)
	match k:
		1:
			c = PaperMesh.col(GRASS).lerp(PaperMesh.col(GRASS_DEEP), smoothstep(4.0, 12.0, y))
		3:
			c = PaperMesh.col(WOOD_FLOOR)
		4:
			c = PaperMesh.col(SCRUB)
		5:
			c = PaperMesh.col(VILLAGE)
	c = c.lerp(PaperMesh.col(WET_SAND), smoothstep(0.22, 0.04, y))
	c = c.lerp(PaperMesh.col(SEABED), smoothstep(-0.05, -0.6, y))
	return c.lerp(PaperMesh.col(ROCK), smoothstep(0.8, 0.62, n.y))


## The ground as pieces of CHUNK metres (smooth, colours baked into the vertices); cells that lie
## all under deep water are left out (the sea is opaque: the phone pays nothing for them).
static func build_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var m: Dictionary = data().meta
	var nx: int = int(m.nx)
	var nz: int = int(m.nz)
	var step: float = float(m.cell)
	var per := int(CHUNK / step)
	var hs := data().height
	var ks := data().kind
	for cz in range(0, nz - 1, per):
		for cx in range(0, nx - 1, per):
			var mi := _chunk(cx, cz, mini(cx + per, nx - 1), mini(cz + per, nz - 1), nx, step, float(m.x0), float(m.z0), hs, ks)
			if mi != null:
				out.append(mi)
	return out


static func _chunk(i0: int, j0: int, i1: int, j1: int, nx: int, step: float, x0: float, z0: float, hs: PackedFloat32Array, ks: PackedByteArray) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var w := i1 - i0 + 1
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var y := hs[j * nx + i]
			var hl := hs[j * nx + maxi(i - 1, 0)]
			var hr := hs[j * nx + mini(i + 1, nx - 1)]
			var hd := hs[maxi(j - 1, 0) * nx + i]
			var hu := hs[mini(j + 1, hs.size() / nx - 1) * nx + i]
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			verts.append(Vector3(x0 + i * step, y, z0 + j * step))
			norms.append(n)
			# Blend the neighbours' kinds so the edges between them are soft.
			var c := Color(0, 0, 0)
			var cnt := 0
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ii := clampi(i + di, 0, nx - 1)
					var jj := clampi(j + dj, 0, hs.size() / nx - 1)
					c += ground_color(y, n, ks[jj * nx + ii])
					cnt += 1
			cols.append(c / cnt)
	for j in range(j1 - j0):
		for i in range(i1 - i0):
			var p00 := j * w + i
			var p10 := p00 + 1
			var p01 := p00 + w
			var p11 := p01 + 1
			if maxf(maxf(verts[p00].y, verts[p10].y), maxf(verts[p01].y, verts[p11].y)) < -2.0:
				continue   # all under deep water
			# Clockwise seen from above (Godot front faces).
			idx.append_array([p00, p10, p01, p10, p11, p01])
	if idx.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = PaperMesh.material()
	return mi


## Can a walker get to (x, z) from the start, over land or ankle-deep water? (The islets cannot be
## reached: the sea between is deep.) A flood over the grid from the start, made once.
static var _reach := PackedByteArray()

static func reachable(x: float, z: float) -> bool:
	var m: Dictionary = data().meta
	var nx: int = int(m.nx)
	var nz: int = int(m.nz)
	if _reach.is_empty():
		_reach.resize(nx * nz)
		var s := WorldBuilder.clearing_center()
		var start := roundi((s.y - float(m.z0)) / float(m.cell)) * nx + roundi((s.x - float(m.x0)) / float(m.cell))
		var limit := -wade_distance()
		var sh := data().shore
		var todo := PackedInt32Array([start])
		_reach[start] = 1
		while not todo.is_empty():
			var i := todo[todo.size() - 1]
			todo.resize(todo.size() - 1)
			var ix := i % nx
			for j in [i - 1, i + 1, i - nx, i + nx]:
				if j < 0 or j >= nx * nz or (j == i - 1 and ix == 0) or (j == i + 1 and ix == nx - 1):
					continue
				if _reach[j] == 0 and sh[j] >= limit:
					_reach[j] = 1
					todo.append(j)
	var ix := roundi((x - float(m.x0)) / float(m.cell))
	var iz := roundi((z - float(m.z0)) / float(m.cell))
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return false
	return _reach[iz * nx + ix] == 1


## The nearest point to `p` a walker can stand on dry (at least `inland` metres from the water),
## within `reach` metres; INF when there is none (an islet's).
static func nearest_reachable(p: Vector2, inland := 2.0, reach := 40.0) -> Vector2:
	for r in range(0, int(reach), 2):
		var n := maxi(1, r * 2)
		for a in n:
			var q := p + Vector2.from_angle(a * TAU / n) * r
			if reachable(q.x, q.y) and shore_distance(q.x, q.y) >= inland:
				return q
	return Vector2.INF


## Where the paths run (for keeping trees, rocks and trunks off them): segments in a 8 m grid.
static var _path_grid := {}

static func near_path(x: float, z: float, r: float) -> bool:
	if _path_grid.is_empty():
		for p in data().meta.paths:
			var pts: Array = p.pts
			for i in pts.size() - 1:
				var a := Vector2(pts[i][0], pts[i][1])
				var b := Vector2(pts[i + 1][0], pts[i + 1][1])
				var n := maxi(1, ceili(a.distance_to(b) / 4.0))
				for k in n + 1:
					var q := a.lerp(b, float(k) / n)
					var key := Vector2i(floori(q.x / 8.0), floori(q.y / 8.0))
					if not _path_grid.has(key):
						_path_grid[key] = []
					_path_grid[key].append([a, b])
	var p := Vector2(x, z)
	var key := Vector2i(floori(x / 8.0), floori(z / 8.0))
	for dj in [-1, 0, 1]:
		for di in [-1, 0, 1]:
			for s in _path_grid.get(key + Vector2i(di, dj), []):
				if Geometry2D.get_closest_point_to_segment(p, s[0], s[1]).distance_to(p) < r:
					return true
	return false
