extends SceneTree
## Plays a scripted walk and saves screenshots along the way.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 --script tools/shot.gd -- out_prefix

const STEPS := [
	# [stick x, stick y, run, frames, action at the end ("" / "act" / "shot")]
	# stick x = "stake": walk the bunny back to the stake.
	[0.3, -1.0, false, 70, "shot"],     # TOFU walks, drags the bunny
	[1.0, -0.2, true, 60, "shot"],      # TOFU runs
	[0.0, 0.0, false, 30, "act"],       # stop, hammer the stake
	[0.0, 0.0, false, 12, "shot"],      # mid-hammer
	[0.0, 0.0, false, 30, ""],
	[-1.0, 0.4, false, 60, "shot"],     # now the bunny walks away, TOFU stays tied
	["stake", 0.0, false, 160, "act"],   # back to the stake, pull it out
	[0.0, 1.0, false, 50, "shot"],      # TOFU again
]

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0]
	var zoom := float(args[1]) if args.size() > 1 else 1.0
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.camera_rig.camera.position *= zoom
	var n := 0
	for s in STEPS:
		main.forced_run = s[2]
		for i in range(s[3]):
			if s[0] is String:
				var d: Vector3 = main.rules.stake_pos - main.bunny.position
				main.forced_input = Vector2(d.x, d.z).normalized() * (0.0 if Vector2(d.x, d.z).length() < 0.6 else 0.8)
			else:
				main.forced_input = Vector2(s[0], s[1]).limit_length(1.0)
			await physics_frame
		if s[4] == "act":
			var dd: Vector3 = main.rules.stake_pos - main.bunny.position
			print("act -> ", main.act(), " dist ", Vector2(dd.x, dd.z).length(), " stake ", main.rules.stake_pos, " bunny ", main.bunny.position)
		elif s[4] == "shot":
			await RenderingServer.frame_post_draw
			n += 1
			var path := "%s_%d.png" % [prefix, n]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
	quit()
