extends SceneTree
## Close views of one character in several poses of the cycle, front and side.
## ... --script tools/pose_view.gd -- bunny|tofu out.png [front|side|hand]

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var who: Dictionary = Actor.BUNNY if a[0] == "bunny" else Actor.TOFU
	var view: String = a[2] if a.size() > 2 else "front"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9fb0c8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	root.add_child(sun)
	var h: float = who.height
	var speeds := [0.0, who.walk, who.walk, who.run, who.run]
	var phases := [0.0, PI * 0.5, PI * 1.5, PI * 0.5, PI * 1.5]
	var actors := []
	for i in speeds.size():
		var ac := Actor.new()
		ac.setup(who)
		ac.position = Vector3((i - 2) * h * 0.7, -Terrain.height(0, 0), 0)
		ac.rotation.y = 0.0 if view != "side" else PI * 0.5
		root.add_child(ac)
		actors.append(ac)
	await process_frame
	for i in actors.size():
		var ac: Actor = actors[i]
		ac.set_process(false)
		ac.gait.phase = phases[i]
		for k in 90:   # let the smoothing and springs settle on this speed
			ac.gait.phase = phases[i]
			ac.animate(1.0 / 60.0, speeds[i])
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	if view == "hand":
		cam.size = h * 0.55
		cam.position = Vector3(0, h * 0.5, 10)
	else:
		cam.size = h * 1.25
		cam.position = Vector3(0, h * 0.5, 10)
	root.add_child(cam)
	cam.make_current()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(a[1])
	quit()
