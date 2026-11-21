extends SceneTree
## The sit button (the player chose the poses): the one you steer sits - the bunny in her "frog"
## W-sit (knees in front, shins folded back and out, paws beside the hips, hands on the thighs),
## TOFU like a dog (knees up, feet in front, front paws on the ground). The hips are down at the
## ground, the feet on it, nothing under it, the knees bend their natural way, both sides alike.
## The stick gets it up and walking; so does the leash pulling it along.

var main


func _initialize() -> void:
	_run()


func _w(a: Actor, n: String) -> Vector3:
	var b := Gait.find_bone(a.skeleton, n)
	return a.skeleton.global_transform * a.skeleton.get_bone_global_pose(b).origin


## In the body's frame: x to its left, y up from the ground, z forward.
func _local(a: Actor, p: Vector3) -> Vector3:
	var d := p - a.global_position
	return Vector3(d.dot(a.global_basis.x.normalized()), d.y, d.dot(a.global_basis.z.normalized()))


## The knee's bend in degrees, signed about the thigh's own side axis (the sign says which way).
func _knee_bend(a: Actor, thigh: String, shin: String, foot: String) -> float:
	var sk := a.skeleton
	var t := sk.get_bone_global_pose(Gait.find_bone(sk, thigh))
	var up := (_w(a, shin) - _w(a, thigh)).normalized()
	var down := (_w(a, foot) - _w(a, shin)).normalized()
	var axis := (sk.global_transform.basis * t.basis.x).normalized()
	return rad_to_deg(atan2(up.cross(down).dot(axis), up.dot(down)))


func _check(a: Actor, names: Dictionary, style: String) -> void:
	var ground := a.global_position.y
	var bend0 := {}
	for s in ["l", "r"]:
		bend0[s] = signf(_knee_bend(a, names["thigh_" + s], names["shin_" + s], names["foot_" + s]))
	main.sit_toggle()
	for i in 80:
		await physics_frame
	await process_frame
	Check.ok(a.gait.sitting and a.gait.sit > 0.99, "%s: the sit button sits it down" % style)
	var hip := minf(_w(a, names.thigh_l).y, _w(a, names.thigh_r).y) - ground
	Check.ok(hip < 0.2, "%s: the hips are down by the ground (%.2f m)" % [style, hip])
	var low := 99.0
	for n in names.values():
		low = minf(low, _w(a, n).y - ground)
	Check.ok(low > -0.015, "%s: no leg or arm joint under the ground (%.1f cm)" % [style, low * 100])
	for s in ["l", "r"]:
		var f := _w(a, names["foot_" + s]).y - ground
		Check.ok(f < 0.13, "%s: the %s foot is on the ground (%.1f cm up)" % [style, s, f * 100])
		var b := _knee_bend(a, names["thigh_" + s], names["shin_" + s], names["foot_" + s])
		Check.ok(signf(b) == bend0[s] and absf(b) > 20.0 and absf(b) < 165.0, "%s: the %s knee bends its natural way, not past its limit (%.0f degrees)" % [style, s, b])
	var kl := _local(a, _w(a, names.shin_l))
	var kr := _local(a, _w(a, names.shin_r))
	var fl := _local(a, _w(a, names.foot_l))
	var fr := _local(a, _w(a, names.foot_r))
	var mirror := maxf((kl - Vector3(-kr.x, kr.y, kr.z)).length(), (fl - Vector3(-fr.x, fr.y, fr.z)).length())
	Check.ok(mirror < 0.08, "%s: both sides alike (%.1f cm apart from mirrored)" % [style, mirror * 100])
	var hl := _local(a, _w(a, names.thigh_l))
	if style == "w":
		Check.ok(kl.z > hl.z + 0.12 and kr.z > hl.z + 0.12, "w: the knees in front")
		Check.ok(absf(kl.x - kr.x) > 0.08 and absf(kl.x - kr.x) < 0.3, "w: close together, not through each other (%.2f m apart)" % absf(kl.x - kr.x))
		Check.ok(absf(fl.x) > absf(hl.x) + 0.08 and absf(fr.x) > absf(hl.x) + 0.08, "w: the paws out beside the hips")
		var hand := _w(a, names.hand_l)
		var on_thigh := PawReach.seg_distance(hand, _w(a, names.thigh_l), _w(a, names.shin_l))
		Check.ok(on_thigh < 0.15, "w: a hand rests on the thigh (%.1f cm off its line)" % (on_thigh * 100))
	else:
		Check.ok(kl.y > hl.y + 0.08 and kr.y > hl.y + 0.08, "dog: the knees up")
		Check.ok(fl.z > hl.z + 0.05 and fr.z > hl.z + 0.05, "dog: the feet in front")
		var paw := _w(a, names.hand_l).y - ground
		Check.ok(paw < 0.15, "dog: the front paws down on the ground (%.1f cm)" % (paw * 100))


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var tofu: Actor = main.tofu
	var bunny: Actor = main.bunny
	bunny.position = tofu.position + Vector3(1.2, 0, 0)
	for i in 30:
		await physics_frame
	var tn := {}
	var bn := {}
	for role in ["thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r", "upper_arm_l", "upper_arm_r", "forearm_l", "forearm_r", "hand_l", "hand_r"]:
		tn[role] = tofu.data.bones[role]
		bn[role] = bunny.data.bones[role]
	await _check(tofu, tn, "dog")
	main.forced_input = Vector2(0, -0.7)
	for i in 70:
		await physics_frame
	Check.ok(not tofu.gait.sitting and tofu.speed > 0.5, "the stick gets it up and walking")
	main.forced_input = Vector2.ZERO
	main.switch_character()
	for i in 40:
		await physics_frame
	await _check(bunny, bn, "w")
	# She sits; TOFU, steered, walks off till the leash pulls her up.
	main.switch_character()
	var got_up := false
	for i in 240:
		main.forced_input = Vector2(0, -1)
		await physics_frame
		if not bunny.gait.sitting:
			got_up = true
			break
	Check.ok(got_up, "the leash pulling her along gets her up")
	main.forced_input = Vector2.ZERO
	Check.finish(self)
