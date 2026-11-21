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
	Check.finish(self)


## How far the head is tipped from upright, degrees.
func _head_tip(a: Actor, hb: int) -> float:
	var sk := a.skeleton
	var hu: Vector3 = (sk.global_transform.basis * sk.get_bone_global_pose(hb).basis).orthonormalized() * (sk.get_bone_global_rest(hb).basis.orthonormalized().inverse() * (sk.global_transform.basis.orthonormalized().inverse() * Vector3.UP))
	return rad_to_deg(hu.angle_to(Vector3.UP))
