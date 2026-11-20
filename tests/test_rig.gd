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
	Check.ok(parent_of.call("DEF-breast01.L").begins_with("DEF-spine.003"), "the chest is carried by the spine")
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
	for i in 150:   # the arm comes up slowly on purpose
		a.animate(0.016, 0.0)
	Check.ok(sk.get_bone_pose_rotation(ua).angle_to(free_arm) > 0.3, "the hand reaches for the leash")
	var sh: Vector3 = sk.global_transform * sk.get_bone_global_pose(ua).origin
	var wr: Vector3 = sk.global_transform * sk.get_bone_global_pose(Gait.find_bone(sk, "DEF-hand.R")).origin
	Check.ok((wr - sh).angle_to(a.gait.hold_target - sh) < 0.3, "a taut leash points the arm at it")
	var fi := Gait.find_bone(sk, "DEF-f_index.02.R")
	Check.ok(sk.get_bone_pose_rotation(fi).angle_to(a.gait._q[fi]) > 0.3, "the fingers close around the leash")
	var hand_b := Gait.find_bone(sk, "DEF-hand.R")
	var hand_at := func() -> Vector3: return sk.global_transform * sk.get_bone_global_pose(hand_b).origin
	var last: Vector3 = hand_at.call()
	var biggest := 0.0
	a.gait.hold_target = a.global_position + Vector3(2.5, 1.0, -1.0)   # TOFU dashes to the other side
	for i in 60:
		a.animate(0.016, 0.0)
		var now: Vector3 = hand_at.call()
		biggest = maxf(biggest, now.distance_to(last))
		last = now
	Check.ok(biggest < 0.03, "the arm swings over smoothly (largest step %.3f m per frame)" % biggest)
	# Leash straight behind her, then far across to her left: the arm follows, within reason.
	a.gait.hold_target = a.global_position + Vector3(0.3, 1.0, -3.0)
	for i in 200:
		a.animate(0.016, 0.0)
	var behind := a.gait.right_arm_angles()
	Check.ok(behind.x > deg_to_rad(70.0) and behind.x <= Gait.ARM_BACK + 0.2, "leash behind: the arm reaches back along her side, only so far (%.0f deg)" % rad_to_deg(behind.x))
	a.gait.hold_target = a.global_position + Vector3(3.0, 1.0, 0.5)
	for i in 200:
		a.animate(0.016, 0.0)
	var across := a.gait.right_arm_angles()
	Check.ok(across.x >= -Gait.ARM_ACROSS - 0.2, "leash to her left: the arm crosses the chest only so far (%.0f deg)" % rad_to_deg(across.x))
	a.gait.hold_target = a.global_position + Vector3(-2.0, 0.9, 2.0)
	for i in 200:
		a.animate(0.016, 0.0)
	var front_right := a.gait.right_arm_angles()
	Check.ok(front_right.x > deg_to_rad(20.0) and front_right.x < deg_to_rad(70.0), "leash ahead to the right: the arm points there (%.0f deg)" % rad_to_deg(front_right.x))
	a.gait.hold_target = Vector3.INF
	a.gait.hammer()
	Check.ok(a.gait.hammering(), "the hammering starts")
	for i in 60:
		a.animate(0.016, 0.0)
	Check.ok(not a.gait.hammering(), "the hammering ends by itself")
	Check.finish(self)
