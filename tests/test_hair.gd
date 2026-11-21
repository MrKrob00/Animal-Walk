extends SceneTree
## Her hair on bones (the player asked how to do it properly and cheaply): a short chain per
## strand made at load (HairRig), on springs (HairSprings). Standing, the hairdo keeps its shape;
## moving, the strands swing but stay near it, never flip, never go into her head or face; they
## settle after; and building it all is quick.

func _initialize() -> void:
	_run()


func _worst(a: Actor) -> float:
	var h: HairSprings = a.hair
	var tg := h._targets()
	var sk := a.skeleton
	var worst := 0.0
	for c in h.chains.size():
		var tip: Vector3 = sk.global_transform * sk.get_bone_global_pose(h.chains[c][2]).origin
		worst = maxf(worst, (tip - tg[c][2]).length())
	return worst


func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	a.set_process(false)
	var h: HairSprings = a.hair
	Check.ok(h != null and h.chains.size() >= 12, "her hair has a chain per strand (%d)" % (h.chains.size() if h != null else 0))
	for i in 60:
		a.animate(1.0 / 60.0, 0.0)
		await process_frame
	Check.ok(_worst(a) < 0.012, "standing, the hairdo keeps its shape (%.1f cm at most)" % (_worst(a) * 100))
	var top := 0.0
	var inside := 0.0
	var vel := 0.0
	var flip := 0.0
	for i in 300:
		var t := i / 60.0
		var target := 1.5 if t < 1.5 else (3.4 if t < 3.0 else 0.0)
		vel = move_toward(vel, target, 6.0 / 60.0)
		a.position.x += vel / 60.0
		if i == 200:
			a.gait.jump()
		a.animate(1.0 / 60.0, vel)
		top = maxf(top, _worst(a))
		var tg := h._targets()
		var balls := h._world_spheres(Vector3.ZERO)
		for c in h.chains.size():
			for j in range(1, 3):
				var p: Vector3 = h._pos[c][j]
				for b in balls.slice(0, 2):   # the skull and the face
					inside = maxf(inside, b[1] - (p - b[0]).length())
				flip = maxf(flip, (p - h._pos[c][j - 1]).angle_to(tg[c][j] - tg[c][j - 1]))
		await process_frame
	Check.ok(top > 0.01, "walking, running and jumping, the strands swing (%.1f cm at most)" % (top * 100))
	Check.ok(top < 0.10, "but stay near the hairdo (%.1f cm at most)" % (top * 100))
	Check.ok(flip <= HairSprings.MAX_ANGLE + 0.01, "never flip over (%.0f degrees at most)" % rad_to_deg(flip))
	Check.ok(inside < 0.002, "never go into her head or face (%.1f mm at most)" % (inside * 1000))
	for i in 150:
		a.animate(1.0 / 60.0, 0.0)
		await process_frame
	Check.ok(_worst(a) < 0.012, "stopped, they settle (%.1f cm)" % (_worst(a) * 100))
	Check.ok(load_ms < 900.0, "she and her hair load in %.0f ms" % load_ms)
	Check.finish(self)
