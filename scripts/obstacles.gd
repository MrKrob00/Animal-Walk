class_name Obstacles
extends RefCounted
## Round obstacles (trunks, bushes, rocks) in a grid, so a walker only checks its neighbours.

const CELL := 4.0

var _grid := {}   ## Vector2i -> Array of Vector3(x, z, radius)
var count := 0


func add(x: float, z: float, r: float) -> void:
	var k := Vector2i(floori(x / CELL), floori(z / CELL))
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append(Vector3(x, z, r))
	count += 1


## Obstacles near (x, z) within `reach` metres.
func near(x: float, z: float, reach := 2.0) -> Array:
	var out := []
	var r := ceili(reach / CELL)
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	for i in range(cx - r, cx + r + 1):
		for j in range(cz - r, cz + r + 1):
			var k := Vector2i(i, j)
			if _grid.has(k):
				out.append_array(_grid[k])
	return out


## Pushes a walker of `radius` at `p` (x, z) out of the obstacles around it.
func push_out(p: Vector2, radius: float) -> Vector2:
	for o in near(p.x, p.y, radius + 2.0):
		var d := p - Vector2(o.x, o.y)
		var min_d: float = o.z + radius
		var l := d.length()
		if l < min_d:
			p = Vector2(o.x, o.y) + (d / l if l > 0.0001 else Vector2.RIGHT) * min_d
	return p
