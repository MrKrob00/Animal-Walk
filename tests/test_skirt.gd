extends SceneTree
## Her sundress on her legs (the player saw a leg go through it in the dressing room): a ring of
## chains on springs from the hip line to the hem (SkirtRig), her thighs push them aside; and the
## cloth itself is pushed out of her thighs in its shader (SoftPress.out_of_leg is its twin).
## Standing, the skirt keeps the shape it was fitted with; walking, the front lifts over the
## stepping thigh; the cloth goes over a thigh, never stays inside it.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	a.set_outfit({"upper": "blouse", "lower": "sundress"})
	var s: HairSprings = a.skirt
	Check.ok(s != null and s.chains.size() >= 16, "the sundress has its chains (%d)" % (s.chains.size() if s != null else 0))
	# Standing: the hem where the dress has it.
	for i in 120:
		await process_frame
	var tg := s._targets()
	var off := 0.0
	for c in s.chains.size():
		off += (s._pos[c][2] as Vector3).distance_to(tg[c][2])
	off = off / s.chains.size() * 100.0
	Check.ok(off < 1.5, "standing, the hem stays in its shape (%.1f cm off on average)" % off)
	# Walking: the hem in front is lifted by the stepping thigh, and no joint stays inside a thigh.
	var fwd := a.global_basis.z
	var lift := 0.0
	var inside := 0.0
	for i in 150:
		a.speed = 1.4
		await process_frame
		if i < 40:
			continue
		tg = s._targets()
		var caps := s._world_capsules(Vector3.ZERO)
		for c in s.chains.size():
			var hz: Vector3 = tg[c][0] - a.global_position
			hz.y = 0.0
			if hz.normalized().dot(fwd) > 0.7:
				lift = maxf(lift, (s._pos[c][2] as Vector3).y - (tg[c][2] as Vector3).y)
			for j in [1, 2]:
				var p: Vector3 = s._pos[c][j]
				for cap in caps:
					var ab: Vector3 = cap[1] - cap[0]
					var t := clampf((p - cap[0]).dot(ab) / ab.length_squared(), 0.0, 1.0)
					var r: float = minf(lerpf(cap[2], cap[3], t), lerpf(cap[4], cap[5], t))
					inside = maxf(inside, r - p.distance_to(cap[0] + ab * t))
	Check.ok(lift > 0.05, "walking, the front of the skirt lifts over the stepping thigh (%.0f cm)" % (lift * 100))
	Check.ok(inside < 0.01, "and its joints stay out of her thighs (%.1f cm in at worst)" % (inside * 100))
	# The cloth: a point inside a thigh goes onto its outside, over it (outward and up).
	var A := Vector3(0.1, 0.7, 0.0)
	var B := Vector3(0.1, 0.45, 0.2)   # a thigh stepping forward
	var R := Vector4(0.12, 0.09, 0.09, 0.07)
	var under := Vector3(0.1, 0.52, 0.06)   # cloth caught under it
	var out := SoftPress.out_of_leg(under, A, B, R, Vector3.RIGHT, Vector3(0, 0.7, -0.05))
	var ab := B - A
	var q := A + ab * clampf((out - A).dot(ab) / ab.length_squared(), 0.0, 1.0)
	Check.ok(out.distance_to(q) > 0.069 and out.y > under.y, "cloth inside a thigh goes onto it, over it (%.1f cm out, %.1f cm up)" % [out.distance_to(q) * 100, (out.y - under.y) * 100])
	var free := Vector3(0.4, 0.6, 0.0)
	Check.ok(SoftPress.out_of_leg(free, A, B, R, Vector3.RIGHT, Vector3.ZERO) == free, "cloth off the thigh stays where it is")
	Check.finish(self)
