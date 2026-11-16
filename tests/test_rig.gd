extends SceneTree
## The bunny's skeleton is re-hung for animation without moving any bone,
## her fingers relax, and the leash hand and the hammer change the pose.

func _initialize() -> void:
	_run()


func _run() -> void:
	var raw: Node3D = load(Actor.BUNNY.path).instantiate()
	root.add_child(raw)
	var raw_sk: Skeleton3D = raw.find_children("*", "Skeleton3D", true, false)[0]
	var before := {}
	for n in ["DEF-thigh.L", "DEF-upper_arm.R", "DEF-neck", "DEF-f_index.01.R", "DEF-breast01.L"]:
		before[n] = raw_sk.get_bone_global_rest(Gait.find_bone(raw_sk, n))
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	var sk := a.skeleton
	var parent_of := func(n: String) -> String: return sk.get_bone_name(sk.get_bone_parent(Gait.find_bone(sk, n)))
	Check.ok(parent_of.call("DEF-thigh.L").begins_with("DEF-spine_"), "the leg hangs from the pelvis")
	Check.ok(parent_of.call("DEF-neck").begins_with("DEF-spine.003"), "the neck hangs from the chest")
	Check.ok(parent_of.call("DEF-breast01.L").begins_with("DEF-spine.003"), "the chest moves with the spine, no bouncing")
	Check.ok(parent_of.call("DEF-f_index.01.R").begins_with("DEF-hand.R"), "the fingers hang from the hand")
	var still := true
	for n in before:
		var g: Transform3D = sk.get_bone_global_rest(Gait.find_bone(sk, n))
		still = still and g.origin.is_equal_approx(before[n].origin)
	Check.ok(still, "re-hanging moves no bone")
	var idx := Gait.find_bone(sk, "DEF-f_index.02.R")
	Check.ok(sk.get_bone_pose_rotation(idx).angle_to(sk.get_bone_rest(idx).basis.get_rotation_quaternion()) > 0.1, "the V-sign fingers are relaxed")
	a.set_process(false)
	var ua := Gait.find_bone(sk, "DEF-upper_arm.R")
	a.animate(0.016, 0.0)
	var free_arm := sk.get_bone_pose_rotation(ua)
	a.gait.hold_target = a.global_position + Vector3(0, 1.0, 3.0)
	a.gait.hold_pull = 1.0
	for i in 60:
		a.animate(0.016, 0.0)
	Check.ok(sk.get_bone_pose_rotation(ua).angle_to(free_arm) > 0.3, "the hand reaches for the leash")
	a.gait.hold_target = Vector3.INF
	a.gait.hammer()
	Check.ok(a.gait.hammering(), "the hammering starts")
	for i in 60:
		a.animate(0.016, 0.0)
	Check.ok(not a.gait.hammering(), "the hammering ends by itself")
	Check.finish(self)
