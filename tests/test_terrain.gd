extends SceneTree
## The island: dry land in the middle, sea around, a smooth ground, walkers kept on dry land.

func _initialize() -> void:
	Check.ok(Terrain.height(0, 0) > 0.2, "the middle of the island is above the sea")
	Check.ok(Terrain.shore(0.0) > 80.0 and Terrain.shore(2.0) > 80.0, "the island is big enough to explore")
	Check.ok(Terrain.height(0, 190.0) < -1.0 and Terrain.height(-190.0, 0) < -1.0, "out past the shore it is sea")
	var ang := 1.0
	var on_shore := Vector2(cos(ang), sin(ang)) * Terrain.shore(ang)
	Check.ok(absf(Terrain.height(on_shore.x, on_shore.y)) < 0.05, "the shore line is at the water level")
	Check.ok(absf(Terrain.height(5.0, 5.0) - Terrain.height(5.01, 5.0)) < 0.05, "the ground has no steps")
	var kept := Terrain.keep_on_island(Vector2(400, 0))
	var wet := Terrain.height(kept.x, kept.y)
	Check.ok(wet < 0.0 and wet > -Terrain.WADE_DEPTH - 0.01, "a walker can wade in, but only ankle deep (%.2f m)" % wet)
	var p: Vector3 = load("res://scripts/main.gd").resolve_against(Vector3(0.1, 0, 0), 0.3, [Vector3(0, 0, 1.0)] as Array[Vector3])
	Check.ok(Vector2(p.x, p.z).length() >= 1.299, "a walker is pushed out of a palm")
	var sea := Water.build_mesh()
	var drawn: int = sea.surface_get_array_index_len(0) / 6
	Check.ok(drawn > 0 and drawn < Water.CELLS * Water.CELLS, "the sea is drawn only where there is water (%d of %d cells)" % [drawn, Water.CELLS * Water.CELLS])
	Check.finish(self)
