extends SceneTree
## Side view of one character stepping on the spot, a few frames of the cycle per speed.
## xvfb-run ... godot --path . --rendering-driver opengl3 --resolution 1600x500 --script tools/gait_view.gd -- bunny|tofu out.png

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var who: Dictionary = Actor.BUNNY if a[0] == "bunny" else Actor.TOFU
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9fb0c8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	root.add_child(sun)
	var h: float = who.height
	var actors := []
	var speeds := [0.0, who.walk, who.walk, who.run, who.run]
	var phases := [0.0, 0.0, PI * 0.5, 0.0, PI * 0.5]
	for i in speeds.size():
		var ac := Actor.new()
		ac.setup(who)
		ac.position = Vector3((i - 2) * h * 0.85, -Terrain.height(0, 0), 0)
		ac.rotation.y = PI * 0.5   # walking to the right of the screen
		root.add_child(ac)
		actors.append(ac)
	await process_frame
	for i in actors.size():
		var ac: Actor = actors[i]
		ac.set_process(false)
		ac.speed = speeds[i]
		ac.gait.phase = phases[i] - 0.0001
		ac.gait.update(0.0, speeds[i])
		ac.body.position.y = ac.gait.bob(speeds[i]) * h
		ac.body.rotation.x = ac.gait.body_lean(speeds[i])
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h * 1.35
	cam.position = Vector3(0, h * 0.5, 10)
	root.add_child(cam)
	cam.make_current()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(a[1])
	quit()
