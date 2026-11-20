extends SceneTree
## Third-person camera: walking goes away from the camera whichever way it looks; a drag on the
## right part turns it (up / down only so far); the wheel and a pinch zoom within limits; the
## walking stick's side and the action button keep their touches; it never goes under the ground.

func _initialize() -> void:
	_run()


func _run() -> void:
	var who := Node3D.new()
	root.add_child(who)
	who.position = Vector3(0, 0, -100)
	var rig := CameraRig.new()
	rig.target = who
	root.add_child(rig)
	await process_frame
	var away := true
	for y in [0.0, 1.0, 2.5, -2.0]:
		rig.yaw = y
		rig._place_camera()
		var from_cam := rig.global_position - rig.camera.global_position
		var up_dir := rig.to_ground(Vector2(0, -1))
		away = away and Vector2(up_dir.x, up_dir.z).dot(Vector2(from_cam.x, from_cam.z)) > 0.0
	Check.ok(away, "the stick's up walks away from the camera, whichever way it looks")
	var size := root.get_visible_rect().size
	var yaw0 := rig.yaw
	_touch(rig, 0, Vector2(size.x * 0.85, size.y * 0.5), true)
	_drag(rig, 0, Vector2(size.x * 0.85 + 100, size.y * 0.5), Vector2(100, 0))
	Check.ok(absf(rig.yaw - yaw0) > 0.3, "a drag on the right part turns the camera round")
	for i in 40:
		_drag(rig, 0, Vector2(size.x * 0.85, size.y * 0.5), Vector2(0, 200))
	_touch(rig, 0, Vector2(size.x * 0.85, size.y * 0.5), false)
	Check.ok(absf(rig.pitch - CameraRig.MAX_PITCH) < 1e-4, "it looks down only so far (%.0f deg)" % rad_to_deg(rig.pitch))
	var yaw1 := rig.yaw
	_touch(rig, 1, Vector2(size.x * 0.2, size.y * 0.5), true)
	_drag(rig, 1, Vector2(size.x * 0.2 + 100, size.y * 0.5), Vector2(100, 0))
	_touch(rig, 1, Vector2(size.x * 0.2, size.y * 0.5), false)
	Check.ok(rig.yaw == yaw1, "a touch on the walking stick's side does not turn it")
	for i in 30:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP
		e.pressed = true
		rig._input(e)
	Check.ok(absf(rig._zoom - CameraRig.MIN_DISTANCE) < 1e-4, "the wheel comes closer, only so far (%.1f m)" % rig._zoom)
	# Pinch: two fingers on the right part move apart -> closer; together -> farther.
	var start := rig._zoom
	_touch(rig, 2, Vector2(size.x * 0.75, size.y * 0.5), true)
	_touch(rig, 3, Vector2(size.x * 0.9, size.y * 0.5), true)
	_drag(rig, 3, Vector2(size.x * 0.9 - 150, size.y * 0.5), Vector2(-150, 0))
	Check.ok(rig._zoom > start, "pinching the fingers together moves the camera away (%.1f -> %.1f m)" % [start, rig._zoom])
	_touch(rig, 2, Vector2.ZERO, false)
	_touch(rig, 3, Vector2.ZERO, false)
	for i in 30:
		rig.zoom_by(CameraRig.WHEEL)
	Check.ok(absf(rig._zoom - CameraRig.MAX_DISTANCE) < 1e-4, "and goes back only so far (%.1f m)" % rig._zoom)
	# Low and far over a hill: the camera stays above the ground.
	var lowest := INF
	for x in range(-60, 61, 15):
		for z in range(-60, 61, 15):
			who.position = Vector3(x, Terrain.height(x, z), z)
			rig.global_position = who.position + Vector3(0, CameraRig.LOOK_HEIGHT, 0)
			rig.pitch = CameraRig.MIN_PITCH
			rig.distance = CameraRig.MAX_DISTANCE
			for y in [0.0, 1.6, 3.2, 4.7]:
				rig.yaw = y
				rig._place_camera()
				var c := rig.camera.global_position
				lowest = minf(lowest, c.y - maxf(Terrain.height(c.x, c.z), 0.0))
	Check.ok(lowest > CameraRig.CLEARANCE - 0.01, "it never goes under the ground (lowest %.2f m above it)" % lowest)
	Check.finish(self)


func _touch(rig: CameraRig, i: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = down
	rig._input(e)


func _drag(rig: CameraRig, i: int, p: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = p
	e.relative = rel
	rig._input(e)
