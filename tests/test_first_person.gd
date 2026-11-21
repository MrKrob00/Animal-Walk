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
	Check.finish(self)


## How far the head is tipped from upright, degrees.
func _head_tip(a: Actor, hb: int) -> float:
	var sk := a.skeleton
	var hu: Vector3 = (sk.global_transform.basis * sk.get_bone_global_pose(hb).basis).orthonormalized() * (sk.get_bone_global_rest(hb).basis.orthonormalized().inverse() * (sk.global_transform.basis.orthonormalized().inverse() * Vector3.UP))
	return rad_to_deg(hu.angle_to(Vector3.UP))
