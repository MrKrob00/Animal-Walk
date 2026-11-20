extends SceneTree
## Pulled along by the leash, the bunny can't keep up: her body goes forward after the leash hand
## (head well ahead of her feet, the leash shoulder leading), the free hand swings back; on her
## own she runs upright. Worn out, her free hand never jerks (it jumped 18 cm in a frame once).

func _initialize() -> void:
	_run()


func _run() -> void:
	var free := await _sample(false)
	var pulled := await _sample(true)
	Check.ok(pulled.head - free.head > 0.1, "pulled, her body leans after the leash (head %.0f cm ahead, %.0f on her own)" % [pulled.head * 100, free.head * 100])
	Check.ok(pulled.lead - free.lead > 0.02, "the leash shoulder leads (%.0f cm, %.0f on her own)" % [pulled.lead * 100, free.lead * 100])
	Check.ok(pulled.hand < free.hand, "the free hand swings back for balance")
	Check.ok(pulled.jump < 0.04, "worn out and pulled, the free hand never jerks (%.1f cm in a frame at most)" % (pulled.jump * 100))
	Check.finish(self)


func _sample(pull: bool) -> Dictionary:
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	a.set_process(false)
	var sk := a.skeleton
	var at := func(n: String) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(Gait.find_bone(sk, n)).origin
	var fwd := a.global_basis.z
	var out := {"head": 0.0, "lead": 0.0, "hand": 0.0}
	var jump := 0.0
	var prev := Vector3.INF
	var n := 0
	for i in 480:   # long enough to wear her out
		a.position += fwd * 3.0 / 60.0
		a.gait.hold_target = a.global_position + fwd * 3.2 + Vector3(0, 0.6, 0)
		a.gait.hold_pull = 1.0 if pull else 0.15
		a.gait.dragged = pull
		a.extra_lean = 0.18 if pull else 0.0   # as the game sets it
		a.animate(1.0 / 60.0, 3.0)
		var h: Vector3 = a.global_transform.affine_inverse() * at.call("DEF-hand.L") - a.global_transform.affine_inverse() * at.call("DEF-upper_arm.L")
		if prev != Vector3.INF and i > 60:
			jump = maxf(jump, h.distance_to(prev))
		prev = h
		if i < 90:
			continue
		out.head += (at.call("DEF-head") - a.global_position).dot(fwd)
		out.lead += (at.call("DEF-upper_arm.R") - at.call("DEF-upper_arm.L")).dot(fwd)
		out.hand += (at.call("DEF-hand.L") - at.call("DEF-upper_arm.L")).dot(fwd)
		n += 1
	a.queue_free()
	for k in out:
		out[k] /= n
	out["jump"] = jump
	return out
