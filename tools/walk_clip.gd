extends SceneTree
## A side-view clip of one character: walk in, stop, run, stop. For judging the motion.
## xvfb-run ... godot --path . --rendering-driver opengl3 --resolution 960x540 --write-movie out/f.png --fixed-fps 30 --script tools/walk_clip.gd -- bunny|tofu

const PLAN := [[0.0, 0.6], [1.0, 2.2], [0.0, 1.6], [2.0, 1.6], [0.0, 1.8]]  # [share of run speed... see below, seconds]

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var who: Dictionary = Actor.BUNNY if args[0] == "bunny" else Actor.TOFU
	var zoom := float(args[1]) if args.size() > 1 else 1.0      # 0.6 = closer
	var look_h := float(args[2]) if args.size() > 2 else 0.55   # camera height, share of body height
	var turn := float(args[3]) if args.size() > 3 else 0.0      # camera angle around, radians
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
	var a := Actor.new()
	a.setup(who)
	root.add_child(a)
	a.position = Vector3(-6, 0, 0)
	a.rotation.y = PI * 0.5
	await process_frame
	a.set_process(false)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(who.height) * 1.5 * zoom
	root.add_child(cam)
	cam.make_current()
	var vel := 0.0
	for step in PLAN:
		var target: float = 0.0 if step[0] == 0.0 else (float(who.walk) if step[0] == 1.0 else float(who.run))
		var frames := int(step[1] * 60)
		for i in frames:
			var dt := 1.0 / 60.0
			vel = move_toward(vel, target, 6.0 * dt)
			a.position.x += vel * dt
			a.animate(dt, vel)
			var at := Vector3(a.position.x, float(who.height) * look_h, 0)
			cam.position = at + Vector3(sin(turn), 0, cos(turn)) * 6.0
			cam.look_at(at)
			await physics_frame
	quit()
