extends SceneTree
## Low places to crawl under (the player chose them): fallen trunks on two rocks, one near the
## start; under a trunk a walker crawls, a step aside it does not; the rocks are in the way; the
## trunk's underside is CLEAR above the ground; the leash gets a capsule per trunk.

func _initialize() -> void:
	var ps := LowPassages.place()
	Check.ok(ps.size() == LowPassages.COUNT, "%d low passages on the island" % ps.size())
	var start := WorldBuilder.clearing_center()
	var nearest := INF
	for p in ps:
		nearest = minf(nearest, (p.c as Vector2).distance_to(start))
	Check.ok(nearest < 16.0, "one is near the start (%.0f m)" % nearest)
	var p: Dictionary = ps[0]
	var c: Vector2 = p.c
	var across: Vector2 = (p.dir as Vector2).orthogonal()
	Check.ok(LowPassages.under(c, ps) and LowPassages.under(c + across * 0.5, ps), "under the trunk, a walker crawls")
	Check.ok(not LowPassages.under(c + across * 1.5, ps), "a step aside, it walks")
	var obs := Obstacles.new()
	var root_node := Node3D.new()
	LowPassages.build(root_node, obs, ps)
	var rock: Vector2 = c + (p.dir as Vector2) * LowPassages.SPAN * 0.5
	Check.ok(obs.push_out(rock, 0.3).distance_to(rock) > 0.5, "the rocks are in the way")
	Check.ok(obs.push_out(c, 0.3).distance_to(c) < 0.001, "the way under the trunk is free")
	var ends := LowPassages.trunk(p)
	var under_y: float = (ends[0] as Vector3).lerp(ends[1], 0.5).y - LowPassages.LOG_R
	Check.ok(absf(under_y - Terrain.height(c.x, c.y) - LowPassages.CLEAR) < 0.2, "the trunk lies %.2f m over the ground" % (under_y - Terrain.height(c.x, c.y)))
	Check.ok(LowPassages.capsules(ps).size() == ps.size(), "the leash lies over every trunk")
	root_node.free()
	Check.finish(self)
