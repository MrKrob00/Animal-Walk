extends SceneTree
## The jump button (the player asked): the one you steer jumps - the bunny a hare's hop, TOFU a
## red panda's "surprise!" leap with a whole turn. It leaves the ground as high as meant, the feet
## hold the ground in the crouch and the landing (none under it), no steps in the air, two prints
## and a puff on landing, no second jump in the air; the bunny's chest and hips move with it
## and settle after; sitting, the button gets her up instead.

var main


func _initialize() -> void:
	_run()


func _foot_y(a: Actor, side: String) -> float:
	var b := Gait.find_bone(a.skeleton, a.data.bones["foot_" + side])
	return (a.skeleton.global_transform * a.skeleton.get_bone_global_pose(b).origin).y - a.global_position.y


func _jump(a: Actor, style: String) -> void:
	var spec: Dictionary = Gait.JUMP[style]
	var foot0 := minf(_foot_y(a, "l"), _foot_y(a, "r"))
	var prints := [0]   # (a lambda gets a copy of a plain local)
	var in_air_steps := 0
	var cb := func(_p, _s): prints[0] += 1
	a.footstep.connect(cb)
	Check.ok(main.jump(), "%s: the button starts a jump" % style)
	var top := 0.0
	var feet_top := 0.0
	var ground_low := 99.0
	var ground_high := -99.0
	var spin := 0.0
	var second := false
	var soft := 0.0
	for i in 120:
		await physics_frame
		await process_frame
		top = maxf(top, a.gait.jump_height())
		spin = maxf(spin, absf(a.body.rotation.y))
		var fy := minf(_foot_y(a, "l"), _foot_y(a, "r"))
		if a.gait.airborne():
			feet_top = maxf(feet_top, fy)
			if prints[0] > 0:
				in_air_steps += 1
			if not second and main.jump():
				second = true
		elif a.gait.jumping():
			ground_low = minf(ground_low, fy)
			ground_high = maxf(ground_high, fy)
		for o in a.gait.flesh_offset:
			soft = maxf(soft, (o as Vector3).length())
		for part in a.gait._soft:
			soft = maxf(soft, ((part[2] as Vector3) - (part[5] as Vector3)).length() * Gait.SOFT_GAIN)
	a.footstep.disconnect(cb)
	Check.ok(absf(top - float(spec.height)) < 0.03, "%s: as high as meant (%.2f m)" % [style, top])
	Check.ok(feet_top > float(spec.height) * 0.5, "%s: the feet leave the ground (%.2f m up)" % [style, feet_top])
	Check.ok(ground_low > foot0 - 0.03 and ground_high < foot0 + 0.07, "%s: crouching and landing the feet hold the ground (%.1f .. %.1f cm from standing)" % [style, (ground_low - foot0) * 100, (ground_high - foot0) * 100])
	Check.ok(in_air_steps == 0 and prints[0] >= 2, "%s: no steps in the air, prints on landing (%d)" % [style, prints[0]])
	Check.ok(not second, "%s: no second jump in the air" % style)
	Check.ok(not a.gait.jumping() and absf(a.body.rotation.y) < 0.001, "%s: landed and done" % style)
	if float(spec.spin) > 0.0:
		Check.ok(spin > 3.0, "%s: a whole turn in the air" % style)
	if style == "hop":
		Check.ok(soft > 0.008, "hop: her chest and hips move with it (%.1f cm at most)" % (soft * 100))


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var tofu: Actor = main.tofu
	var bunny: Actor = main.bunny
	bunny.position = tofu.position + Vector3(1.3, 0, 0)
	for i in 40:
		await physics_frame
	await _jump(tofu, "surprise")
	main.switch_character()
	for i in 40:
		await physics_frame
	await _jump(bunny, "hop")
	for i in 150:
		await physics_frame
	var rest := 0.0
	for o in bunny.gait.flesh_offset:
		rest = maxf(rest, (o as Vector3).length())
	Check.ok(rest < 0.002, "after the hop it all settles (%.1f mm)" % (rest * 1000))
	main.sit_toggle()
	for i in 60:
		await physics_frame
	Check.ok(not main.jump() and not bunny.gait.sitting and not bunny.gait.jumping(), "sitting, the button gets her up instead")
	Check.finish(self)
