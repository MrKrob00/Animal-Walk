extends SceneTree
## Walking plays real clips on our skeletons: legs swing, feet land, the planted foot does not
## slide on the ground, and standing still settles into the idle clip.

func _initialize() -> void:
	_run()


func _run() -> void:
	for who in [Actor.TOFU, Actor.BUNNY]:
		var a := Actor.new()
		a.setup(who)
		root.add_child(a)
		await process_frame
		a.set_process(false)
		var label: String = "TOFU" if who == Actor.TOFU else "bunny"
		var sk := a.skeleton
		Check.ok(a.gait.rt != null, "%s plays real clips" % label)
		var thigh := Gait.find_bone(sk, who.bones.thigh_l)
		var dt := 1.0 / 60.0
		a.animate(dt, 0.0)
		var still := sk.get_bone_pose_rotation(thigh)
		var steps := 0
		var widest := 0.0
		var foot_low := INF
		var samples := []
		for i in 150:
			a.position.z += a.data.walk * dt
			steps += absi(a.gait.update(dt, a.data.walk))
			a.body.position = a.gait.body_offset(float(a.data.height))
			widest = maxf(widest, sk.get_bone_pose_rotation(thigh).angle_to(still))
			if i > 60:
				var f: Vector3 = a.gait.foot_position(true)
				samples.append(f)
				foot_low = minf(foot_low, f.y)
		Check.ok(widest > 0.3, "%s swings the legs walking (%.2f rad)" % [label, widest])
		Check.ok(steps >= 2, "%s lands feet (%d in 2.5 s)" % [label, steps])
		# While the left foot is down, it should stay put although the body moves on.
		var slide := 0.0
		var moved := 0.0
		for k in range(1, samples.size()):
			if samples[k].y < foot_low + 0.02 and samples[k - 1].y < foot_low + 0.02:
				slide += Vector2(samples[k].x - samples[k - 1].x, samples[k].z - samples[k - 1].z).length()
				moved += a.data.walk * dt
		Check.ok(moved > 0.0 and slide / moved < 0.35, "%s's planted foot hardly slides (%.0f%% of the way)" % [label, 100.0 * slide / maxf(moved, 0.001)])
		for i in 180:
			a.gait.update(dt, 0.0)
		var r0 := sk.get_bone_pose_rotation(thigh)
		a.gait.update(dt, 0.0)
		Check.ok(sk.get_bone_pose_rotation(thigh).angle_to(r0) < 0.02, "%s stands still in the idle clip" % label)
	Check.ok(Gait.find_bone(Skeleton3D.new(), "no_such_bone") == -1, "an unknown bone is reported as missing")
	Check.finish(self)
