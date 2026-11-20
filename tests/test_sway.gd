extends SceneTree
## Running, the bunny's shoulders sway evenly to both sides and only a little: her rest's
## turned shoulders do not roll her to one side, and the clip's cartoon swing is halved.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	a.set_process(false)
	var sk := a.skeleton
	var l := Gait.find_bone(sk, "DEF-upper_arm.L")
	var r := Gait.find_bone(sk, "DEF-upper_arm.R")
	var side := a.body.global_basis.x
	var fwd := a.body.global_basis.z
	for spd in [1.3, 3.6]:
		var rolls := []
		var yaws := []
		for i in 240:
			a.position += a.global_basis.z * spd / 60.0
			a.animate(1.0 / 60.0, spd)
			if i < 120:
				continue
			var d: Vector3 = sk.global_transform.basis * (sk.get_bone_global_pose(l).origin - sk.get_bone_global_pose(r).origin)
			rolls.append(rad_to_deg(atan2(d.y, absf(d.dot(side)))))
			yaws.append(rad_to_deg(atan2(d.dot(fwd), absf(d.dot(side)))))
		var mid: float = (rolls.max() + rolls.min()) * 0.5
		Check.ok(absf(mid) < 4.0, "at %.1f m/s the shoulders roll evenly to both sides (centre %.1f deg)" % [spd, mid])
		Check.ok(rolls.max() - rolls.min() < 30.0 and yaws.max() - yaws.min() < 40.0, "at %.1f m/s the sway stays small (roll %.0f, twist %.0f deg in all)" % [spd, rolls.max() - rolls.min(), yaws.max() - yaws.min()])
	Check.finish(self)
