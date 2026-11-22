extends SceneTree
## The island's green (the player: grass, trees, leaves, wind for a pretty picture): grass over
## the meadows and none on the paths or the sand, thin enough for a phone where it is drawn and
## gone with distance (it sinks, no popping); trees in the woods; the wind moves them; leaves fall
## only near a wood.

func _initialize() -> void:
	var n := Node3D.new()
	root.add_child(n)
	var count := Foliage.grow(n, 77, true)
	var on_path := 0
	var on_sand := 0
	var near := 0
	# The thickest place: a meadow away from the water and the paths.
	var c := Vector2.INF
	var b0 := Terrain.bounds()
	for i in 20000:
		var q := b0.position + Vector2(randf() * b0.size.x, randf() * b0.size.y)
		if Terrain.kind(q.x, q.y) == 1 and Terrain.kind(q.x + 15, q.y) == 1 and Terrain.kind(q.x - 15, q.y) == 1 and Terrain.shore_distance(q.x, q.y) > 30.0:
			c = q
			break
	for o in Foliage.placed:
		if Terrain.on_path(o.x, o.y):
			on_path += 1
		if Terrain.kind(o.x, o.y) == 2:
			on_sand += 1
		if o.distance_to(c) < Foliage.GRASS_FAR:
			near += 1
	Check.ok(count > 20000, "grass over the meadows (%d clumps)" % count)
	Check.ok(on_path == 0 and on_sand == 0, "none on the paths or the sand (%d, %d)" % [on_path, on_sand])
	var tris := near * 27
	Check.ok(near > 300 and tris < 60000, "within reach of the camera in a meadow: %d clumps, about %d triangles" % [near, tris])
	var g := Foliage.material("grass")
	Check.ok(float(g.get_shader_parameter("fade_far")) == Foliage.GRASS_FAR and float(g.get_shader_parameter("wind_strength")) > 0.0, "grass sways and sinks away with distance")
	Check.ok(float(Foliage.material("tree_paper").get_shader_parameter("wind_strength")) > 0.0 and float(Foliage.material("palm").get_shader_parameter("wind_strength")) > 0.0, "trees and palms sway too")
	# Trees stand in the woods: build the plants and look.
	var w := Node3D.new()
	root.add_child(w)
	WorldBuilder.populate(w, Obstacles.new())
	var trees := WorldBuilder.trees_at.size()
	var in_wood := 0
	for o in WorldBuilder.trees_at:
		if Terrain.kind(o.x, o.y) == 3:
			in_wood += 1
	Check.ok(in_wood > 80 and in_wood > trees * 0.6, "broadleaf trees, mostly in Herm's woods, thick there (%d of %d)" % [in_wood, trees])
	var wood := Vector3.INF
	var harbour := WorldBuilder.clearing_center()
	var open_sea_side := Vector3(harbour.x, 0, harbour.y)
	var b := Terrain.bounds()
	for i in 20000:
		var p := b.position + Vector2(randf() * b.size.x, randf() * b.size.y)
		if Terrain.kind(p.x, p.y) == 3:
			wood = Vector3(p.x, 0, p.y)
			break
	Check.ok(Leaves._woods_near(wood) and not Leaves._woods_near(open_sea_side), "leaves fall near a wood, not at the harbour")
	Check.finish(self)
