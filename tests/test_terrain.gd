extends SceneTree
## The island: dry land in the middle, sea around, a smooth ground, walkers kept on dry land.

func _initialize() -> void:
	Check.ok(Terrain.height(0, 0) > 0.5, "the middle of the island is above the sea")
	Check.ok(Terrain.height(0, 45.0) < -1.0 and Terrain.height(-45.0, 0) < -1.0, "out past the shore it is sea")
	var ang := 1.0
	var on_shore := Vector2(cos(ang), sin(ang)) * Terrain.shore(ang)
	Check.ok(absf(Terrain.height(on_shore.x, on_shore.y)) < 0.05, "the shore line is at the water level")
	Check.ok(absf(Terrain.height(5.0, 5.0) - Terrain.height(5.01, 5.0)) < 0.05, "the ground has no steps")
	var kept := Terrain.keep_on_island(Vector2(60, 0))
	Check.ok(Terrain.height(kept.x, kept.y) > 0.0, "a walker heading out to sea stays on dry sand")
	var p: Vector3 = load("res://scripts/main.gd").resolve_against(Vector3(0.1, 0, 0), 0.3, [Vector3(0, 0, 1.0)] as Array[Vector3])
	Check.ok(Vector2(p.x, p.z).length() >= 1.299, "a walker is pushed out of a palm")
	var sea := Water.build_mesh()
	var drawn: int = sea.surface_get_array_index_len(0) / 6
	Check.ok(drawn > 0 and drawn < Water.CELLS * Water.CELLS, "the sea is drawn only where there is water (%d of %d cells)" % [drawn, Water.CELLS * Water.CELLS])
	Check.finish(self)
