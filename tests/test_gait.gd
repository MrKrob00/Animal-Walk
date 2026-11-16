extends SceneTree
## Walking moves the leg bones and lands feet; standing keeps them at rest.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Actor.new()
	a.setup(Actor.TOFU)
	root.add_child(a)
	await process_frame
	var sk := a.skeleton
	var thigh := Gait.find_bone(sk, "thigh.L")
	Check.ok(thigh >= 0, "TOFU has a left thigh bone")
	a.set_process(false)
	a.gait.update(0.5, 0.0)
	var rest := sk.get_bone_pose_rotation(thigh)
	var steps := 0
	for i in 60:
		steps += absi(a.gait.update(1.0 / 60.0, a.data.walk))
	var moved := sk.get_bone_pose_rotation(thigh)
	Check.ok(rest.angle_to(moved) > 0.05, "walking swings the thigh")
	Check.ok(steps >= 2, "walking for a second lands feet (%d)" % steps)
	for i in 120:
		a.gait.update(1.0 / 60.0, 0.0)
	Check.ok(sk.get_bone_pose_rotation(thigh).angle_to(rest) < 0.01, "standing still puts the leg back")
	Check.ok(Gait.find_bone(sk, "no_such_bone") == -1, "an unknown bone is reported as missing")
	Check.finish(self)
