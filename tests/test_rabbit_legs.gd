extends SceneTree
## The bunny has a rabbit's legs (the player chose them): she stands on the front of her paws,
## heel up, knee forward of the hip-ankle line; both legs alike; walking keeps the knee forward.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	a.set_process(false)
	var sk := a.skeleton
	var at := func(n: String) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(Gait.find_bone(sk, n)).origin
	var fwd := a.body.global_basis.z
	var knee_fwd := func(s: String) -> float:
		var hip: Vector3 = at.call("DEF-thigh." + s)
		var ankle: Vector3 = at.call("DEF-foot." + s)
		var knee: Vector3 = at.call("DEF-shin." + s)
		var t := clampf((knee - hip).dot(ankle - hip) / (ankle - hip).length_squared(), 0.0, 1.0)
		return (knee - (hip + (ankle - hip) * t)).dot(fwd)
	var info := []
	var ok_rest := true
	for s in ["L", "R"]:
		var ankle: Vector3 = at.call("DEF-foot." + s)
		var ball: Vector3 = at.call("DEF-toe." + s)
		var heel_up := ankle.y - ball.y
		info.append("%s knee %.0f cm forward, ankle %.0f cm over the ball" % [s, knee_fwd.call(s) * 100, heel_up * 100])
		ok_rest = ok_rest and knee_fwd.call(s) > 0.04 and heel_up > 0.15
	Check.ok(ok_rest, "standing, knees forward and heels up (%s)" % ", ".join(info))
	# Both paws on the ground alike: the lowest skin of each.
	var body: MeshInstance3D = a.find_child(Actor.BUNNY.cloth.body, true, false)
	var low := {"L": INF, "R": INF}
	var mid: Vector3 = at.call("DEF-spine")
	for v in body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var w: Vector3 = body.global_transform * v
		if w.y < 0.3:
			var k := "L" if (w - mid).dot(a.body.global_basis.x) > 0.0 else "R"
			low[k] = minf(low[k], w.y)
	Check.ok(absf(low.L - low.R) < 0.005 and absf(low.L) < 0.01, "both paws stand on the ground (lowest skin %.1f / %.1f cm)" % [low.L * 100, low.R * 100])
	var back := 0
	for i in 180:
		a.position += a.global_basis.z * 1.3 / 60.0
		a.animate(1.0 / 60.0, 1.3)
		for s in ["L", "R"]:
			if knee_fwd.call(s) < -0.01:
				back += 1
	Check.ok(back == 0, "walking, a knee never bends backward (%d frames)" % back)
	Check.finish(self)
