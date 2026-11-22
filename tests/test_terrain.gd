extends SceneTree
## The island is Herm at 1:4 (the player chose it from a real map): its land where the map has it,
## sea round it, the harbour to start at, hills from the real heights, a smooth ground, walkers kept
## on dry land or ankle deep, its paths and places there, and light enough for a phone.

func _initialize() -> void:
	var b := Terrain.bounds()
	Check.ok(b.size.x > 450.0 and b.size.x < 700.0 and b.size.y > 550.0 and b.size.y < 800.0, "Herm at 1:4 with sea round it (%.0f x %.0f m)" % [b.size.x, b.size.y])
	var start := WorldBuilder.clearing_center()
	Check.ok(Terrain.shore_distance(start.x, start.y) > 5.0 and Terrain.height(start.x, start.y) > 0.1, "the start (Herm Harbour) is on dry land")
	var top := 0.0
	for i in 400:
		var p := b.position + Vector2(randf() * b.size.x, randf() * b.size.y)
		top = maxf(top, Terrain.height(p.x, p.y))
	Check.ok(top > 12.0 and top < 19.0, "hills from the real heights, a quarter of them (%.1f m)" % top)
	Check.ok(Terrain.height(b.position.x + 2.0, b.position.y + 2.0) < -1.0 and Terrain.height(b.end.x + 50.0, b.end.y + 50.0) < -2.0, "out past the shore it is sea")
	# The waterline: where the distance to the coast is 0, the ground is at the water's level.
	var on_shore := Vector2.INF
	for i in 2000:
		var p := b.position + Vector2(randf() * b.size.x, randf() * b.size.y)
		if absf(Terrain.shore_distance(p.x, p.y)) < 0.3:
			on_shore = p
			break
	Check.ok(on_shore != Vector2.INF and absf(Terrain.height(on_shore.x, on_shore.y)) < 0.1, "the shore line is at the water level")
	Check.ok(absf(Terrain.height(start.x, start.y) - Terrain.height(start.x + 0.01, start.y)) < 0.05, "the ground has no steps")
	var kept := Terrain.keep_on_island(Vector2(b.position.x + 5.0, start.y))
	var wet := Terrain.height(kept.x, kept.y)
	Check.ok(wet < 0.0 and wet > -Terrain.WADE_DEPTH - 0.02, "a walker can wade in, but only ankle deep (%.2f m)" % wet)
	var p: Vector3 = load("res://scripts/main.gd").resolve_against(Vector3(start.x + 0.1, 0, start.y), 0.3, [Vector3(start.x, start.y, 1.0)] as Array[Vector3])
	Check.ok(Vector2(p.x, p.z).distance_to(start) >= 1.299, "a walker is pushed out of a palm")
	var m: Dictionary = Terrain.data().meta
	Check.ok(m.paths.size() > 50 and m.places.size() > 40, "Herm's paths and places are there (%d paths, %d places)" % [m.paths.size(), m.places.size()])
	var named := []
	for pl in m.places:
		named.append(pl.name)
	Check.ok("Shell Beach" in named and "Pierre Aux Rats (Obelisk)" in named and "Herm Harbour" in named, "with Shell Beach, the obelisk and the harbour")
	var sea := Water.build_mesh()
	Check.ok(sea.surface_get_array_index_len(0) / 3 < 60000, "the sea is drawn only where there is water (%d triangles)" % (sea.surface_get_array_index_len(0) / 3))
	var tris := 0
	for g in Terrain.build_meshes():
		tris += g.mesh.surface_get_array_index_len(0) / 3
	Check.ok(tris < 80000, "the ground leaves out the deep sea (%d triangles)" % tris)
	Check.ok(FileAccess.get_file_as_bytes(Terrain.DATA).size() < 1024 * 1024, "the island's data is under 1 MB")
	Check.finish(self)
