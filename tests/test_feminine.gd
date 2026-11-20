extends SceneTree
## The bunny walks like a woman: her steps are narrower than the clip's, the pelvis drops on
## the free side and moves over the standing leg (and her planted feet still hold: test_gait).

func _initialize() -> void:
	_run()


func _run() -> void:
	var plain := await _walk(0.0)
	var hers := await _walk(1.0)
	Check.ok(plain.width - hers.width > 0.03, "her feet land nearer one line (%.0f cm apart, the clip %.0f)" % [hers.width * 100, plain.width * 100])
	Check.ok(hers.drop < -0.01, "standing on one leg, the free side of her pelvis drops (%.1f cm)" % (hers.drop * 100))
	Check.ok(hers.over - plain.over > 0.02, "her hips move over the standing leg (%.1f cm more than the clip)" % ((hers.over - plain.over) * 100))
	Check.finish(self)


## Walks at 1.3 m/s; returns {width: feet apart sideways, drop: free hip below the standing
## one at mid-stance, over: hips toward the standing leg at mid-stance} (metres, averaged).
func _walk(fem: float) -> Dictionary:
	var a := Actor.new()
	var d: Dictionary = Actor.BUNNY.duplicate(true)
	d.bones.feminine = fem
	a.setup(d)
	root.add_child(a)
	await process_frame
	a.set_process(false)
	var sk := a.skeleton
	var at := func(n: String) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(Gait.find_bone(sk, n)).origin
	var left := a.body.global_basis * a.gait._left_char
	var width := 0.0
	var drop := 0.0
	var over := 0.0
	var n := 0
	var m := 0
	for i in 240:
		a.position += a.global_basis.z * 1.3 / 60.0
		a.animate(1.0 / 60.0, 1.3)
		if i < 120:
			continue
		width += absf((at.call("DEF-foot.L") - at.call("DEF-foot.R")).dot(left))
		n += 1
		var stand := sin(a.gait.rt.phase * TAU)   # +1: standing on the left leg
		if absf(stand) > 0.8:
			var hl: Vector3 = at.call("DEF-thigh.L")
			var hr: Vector3 = at.call("DEF-thigh.R")
			var free_minus_standing := (hr.y - hl.y) * signf(stand)
			drop += free_minus_standing
			over += ((hl + hr) * 0.5 - a.global_position).dot(left) * signf(stand)
			m += 1
	a.queue_free()
	return {"width": width / n, "drop": drop / maxf(m, 1), "over": over / maxf(m, 1)}
