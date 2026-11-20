extends SceneTree
## The bunny's free arms follow the clips without breaking: the hand continues the forearm,
## the elbow bends only the natural way, and a hanging hand has its palm toward the thigh.

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
	var fwd := a.body.global_basis.z.normalized()
	var worst_wrist := 0.0
	var worst_elbow := 1.0
	for spd in [0.0, 1.2, 2.5, 4.0]:
		for i in 90:
			a.animate(1.0 / 30.0, spd)
			for s in ["L", "R"]:
				var sh: Vector3 = at.call("DEF-upper_arm." + s)
				var el: Vector3 = at.call("DEF-forearm." + s)
				var wr: Vector3 = at.call("DEF-hand." + s)
				var kn: Vector3 = at.call("DEF-f_middle.01." + s)
				worst_wrist = maxf(worst_wrist, (wr - el).angle_to(kn - wr))
				# A natural elbow: the forearm swings forward of the upper arm, never back.
				var bend := (wr - el).normalized() - (el - sh).normalized()
				worst_elbow = minf(worst_elbow, bend.dot(fwd))
	Check.ok(worst_wrist < deg_to_rad(35.0), "the hand continues the forearm (wrist bent at most %.0f deg)" % rad_to_deg(worst_wrist))
	Check.ok(worst_elbow > -0.1, "the elbows bend only the natural way (%.2f)" % worst_elbow)
	for i in 120:
		a.animate(1.0 / 30.0, 0.0)
	var palm_in := true
	for s in ["L", "R"]:
		var across: Vector3 = at.call("DEF-f_index.01." + s) - at.call("DEF-f_pinky.01." + s)
		palm_in = palm_in and across.normalized().dot(fwd) > 0.5
	Check.ok(palm_in, "standing, the palms face the thighs (index finger in front)")
	Check.finish(self)
