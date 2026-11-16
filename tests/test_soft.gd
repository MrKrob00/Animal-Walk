extends SceneTree
## The chest follows the body softly: it lags while walking, swings on after a stop,
## and settles by itself.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	a.set_process(false)
	var sk := a.skeleton
	var b := Gait.find_bone(sk, "DEF-breast01.L")
	var rest := sk.get_bone_rest(b).basis.get_rotation_quaternion()
	var dt := 1.0 / 60.0
	var vel := 0.0
	var walk_max := 0.0
	for i in 150:
		vel = move_toward(vel, a.data.walk, 12.0 * dt)
		a.position.z += vel * dt
		a.animate(dt, vel)
		if i > 60:
			walk_max = maxf(walk_max, sk.get_bone_pose_rotation(b).angle_to(rest))
	var stop_max := 0.0
	for i in 40:
		vel = move_toward(vel, 0.0, 12.0 * dt)
		a.position.z += vel * dt
		a.animate(dt, vel)
		stop_max = maxf(stop_max, sk.get_bone_pose_rotation(b).angle_to(rest))
	for i in 180:
		a.animate(dt, 0.0)
	var settled := sk.get_bone_pose_rotation(b).angle_to(rest)
	print("  walk %.3f rad, stop %.3f rad, settled %.4f rad" % [walk_max, stop_max, settled])
	Check.ok(walk_max > 0.03, "the chest moves a little while walking")
	Check.ok(stop_max > 0.06, "after a stop it swings on")
	Check.ok(walk_max < 0.5 and stop_max < 0.5, "never wildly")
	Check.ok(settled < 0.02, "it settles by itself")
	Check.finish(self)
