extends SceneTree
## Moving the rope's end to another anchor lays it out calmly: no whip, ends in place.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Marker3D.new()
	var b := Marker3D.new()
	var c := Marker3D.new()
	for m in [a, b, c]:
		root.add_child(m)
	a.position = Vector3(0, 1, 0)
	b.position = Vector3(2, 1, 0)
	c.position = Vector3(-2, 0.4, 1)
	var rope := Leash.new()
	rope.a = a
	rope.b = b
	rope.use_ground = false
	root.add_child(rope)
	await process_frame
	for i in 30:
		rope.simulate(1.0 / 60.0, a.global_position, b.global_position)
	rope.reattach_b(c)
	var still := true
	for i in Leash.POINTS:
		still = still and rope.pts[i].is_equal_approx(rope._prev[i])
	Check.ok(still, "after re-tying the rope does not move by itself")
	Check.ok(rope.pts[Leash.POINTS - 1].is_equal_approx(c.global_position), "its end is at the new anchor")
	# Drawn as a smooth curve: a sharp fold in the points becomes a round bend.
	var fold := PackedVector3Array([Vector3(0, 1, 0), Vector3(0.5, 0.5, 0), Vector3(1, 0, 0), Vector3(1.2, 0.6, 0), Vector3(1.4, 1.2, 0)])
	var line := Leash.smooth(fold)
	var sharpest := 0.0
	for i in range(1, line.size() - 1):
		sharpest = maxf(sharpest, (line[i] - line[i - 1]).angle_to(line[i + 1] - line[i]))
	var through := line[0].is_equal_approx(fold[0]) and line[line.size() - 1].is_equal_approx(fold[fold.size() - 1])
	Check.ok(sharpest < deg_to_rad(40.0) and through, "the rope is drawn round, its ends in place (sharpest turn %.0f deg, the fold is 90)" % rad_to_deg(sharpest))
	Check.ok(rope.pts[0].is_equal_approx(a.global_position), "its other end stays put")
	Check.finish(self)
