extends SceneTree
## First / third person (the player asked for a switch): in first person the camera is at the
## steered character's eyes, its head is hidden (never in the way), looking all the way down tips
## the head only so far (no broken neck); back in third person the head shows again and the camera
## is behind; a touch on the view button does not turn the camera.

func _initialize() -> void:
	_run()


func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var rig: CameraRig = main.camera_rig
	var tofu: Actor = main.tofu
	var hb := Gait.find_bone(tofu.skeleton, Actor.TOFU.bones.head)
	main.toggle_view()
	rig.look = 0.0
	for i in 60:
		await physics_frame
	var ahead := _head_tip(tofu, hb)
	rig.look = CameraRig.LOOK_MIN
	for i in 60:
		await physics_frame
	await process_frame
	Check.ok(rig.first_person and main.view_button.first_person, "the button switches to first person")
	Check.ok(rig.camera.global_position.distance_to(tofu.eye_position()) < 0.04, "the camera is at the eyes (%.1f cm off)" % (rig.camera.global_position.distance_to(tofu.eye_position()) * 100))
	Check.ok(tofu.skeleton.get_bone_pose_scale(hb).x < 0.01, "the head is hidden")
	var tip := _head_tip(tofu, hb) - ahead
	Check.ok(tip > 10.0 and tip < 40.0, "looking straight down (%.0f degrees), the head tips %.0f more than looking ahead (the eyes do the rest)" % [-rad_to_deg(CameraRig.LOOK_MIN), tip])
	var yaw := rig.yaw
	var e := InputEventScreenTouch.new()
	e.index = 4
	e.position = main.view_button.center()
	e.pressed = true
	rig._input(e)
	var d := InputEventScreenDrag.new()
	d.index = 4
	d.position = e.position + Vector2(80, 0)
	d.relative = Vector2(80, 0)
	rig._input(d)
	Check.ok(rig.yaw == yaw, "a touch on the view button does not turn the camera")
	main.toggle_view()
	for i in 30:
		await physics_frame
	await process_frame
	Check.ok(not rig.first_person and tofu.skeleton.get_bone_pose_scale(hb).x > 0.99, "back in third person the head shows again")
	Check.ok(rig.camera.global_position.distance_to(tofu.eye_position()) > 1.5, "and the camera is behind again")
	# The view is the body's own: it starts where the character faces, turns with the body when
	# it walks off another way, and walking on never turns the body round (it did: it kept
	# facing a point 3 m ahead and spun round once it walked past it, the view staying put).
	tofu.rotation.y = 1.0
	main.toggle_view()
	Check.ok(absf(angle_difference(rig.yaw, CameraRig.body_yaw(tofu))) < 0.01, "first person starts looking where the character faces")
	main.forced_input = Vector2(0, 0.7)   # the stick pulled back: turn round and walk off
	for i in 90:
		await physics_frame
	await process_frame
	var turned := absf(angle_difference(CameraRig.body_yaw(tofu), 1.0 + PI))
	var with_body := absf(angle_difference(rig.yaw, CameraRig.body_yaw(tofu)))
	Check.ok(turned > 2.9, "stick back: the body turns round (%.0f degrees)" % rad_to_deg(turned))
	Check.ok(with_body < 0.1, "and the view turns with it (%.0f degrees off the body)" % rad_to_deg(with_body))
	main.forced_input = Vector2(0, -0.7)   # stick forward for a while: no turning round
	for i in 60:
		await physics_frame
	var y0 := CameraRig.body_yaw(tofu)
	var worst := 0.0
	for i in 240:
		await physics_frame
		worst = maxf(worst, absf(angle_difference(CameraRig.body_yaw(tofu), y0)))
	Check.ok(worst < 0.15, "walking straight on, the body keeps its way (turned at most %.0f degrees)" % rad_to_deg(worst))
	main.forced_input = Vector2.ZERO
	for i in 60:
		await physics_frame
	await process_frame
	Check.ok(absf(angle_difference(rig.yaw, CameraRig.body_yaw(tofu))) < 0.1, "stopped, the view and the body still agree")
	# Nothing of TOFU's snout stays in front of the eyes (the player saw its nose): in first person
	# all its skin with more than a little weight on the head goes away with the head.
	var share := float(Actor.TOFU.fp_head_share)
	var left_on := 0
	for mi in tofu.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.skin == null:
			continue
		var hbind := HairRig._bind_of(m.skin, tofu.skeleton, hb)
		if hbind < 0:
			continue
		var arr := m.mesh.surface_get_arrays(0)
		var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bb.size() / (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for v in bb.size() / per:
			var wh := 0.0
			for k in per:
				if bb[v * per + k] == hbind:
					wh += ww[v * per + k]
			if wh > share and wh < 0.999:
				left_on += 1
	Check.ok(left_on == 0, "first person, TOFU's snout goes away with its head (%d vertices left half on it)" % left_on)
	# Up and down are the head's (the player): standing still the view is level at look 0, a run's
	# lean tips it down, and it moves smoothly (it jerked: the body moved on physics ticks only).
	rig.look = 0.0
	for i in 60:
		await process_frame
	var level := rad_to_deg(asin((-rig.camera.global_basis.z).y))
	Check.ok(absf(level) < 3.0, "standing, the view is level at look 0 (%.1f degrees)" % level)
	main.forced_run = true
	var cams := []
	for i in 150:
		main.forced_input = Vector2(0, -1)
		await process_frame
		if i > 50:
			cams.append(rig.camera.global_position)
	var run_tip := rad_to_deg(asin((-rig.camera.global_basis.z).y))
	Check.ok(run_tip < -3.0 and run_tip > -25.0, "running, the head's lean tips the view down (%.0f degrees)" % run_tip)
	var jerk := 0.0
	for k in range(1, cams.size() - 1):
		jerk += ((cams[k + 1] - cams[k] * 2.0 + cams[k - 1]) as Vector3).length()
	jerk = jerk / (cams.size() - 2) * 1000.0
	Check.ok(jerk < 2.0, "running, the eyes move smoothly with more frames than ticks (%.1f mm a frame of change in step; it was 5)" % jerk)
	main.forced_run = false
	main.forced_input = Vector2.ZERO
	Check.finish(self)


## How far the head is tipped from upright, degrees.
func _head_tip(a: Actor, hb: int) -> float:
	var sk := a.skeleton
	var hu: Vector3 = (sk.global_transform.basis * sk.get_bone_global_pose(hb).basis).orthonormalized() * (sk.get_bone_global_rest(hb).basis.orthonormalized().inverse() * (sk.global_transform.basis.orthonormalized().inverse() * Vector3.UP))
	return rad_to_deg(hu.angle_to(Vector3.UP))
