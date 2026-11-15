extends SceneTree
## Walks the wolf along a scripted path and saves a screenshot.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 --script tools/shot.gd -- out.png [frames_per_leg]

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shot.png"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var path: Array[Vector2] = [Vector2(0.4, -1.0), Vector2(1.0, -0.2), Vector2(0.2, 0.9), Vector2(-1.0, 0.3)]
	var frames := int(args[1]) if args.size() > 1 else 50
	for dir in path:
		main.player.forced_input = dir.normalized()
		for i in range(frames):
			await physics_frame
	main.player.forced_input = Vector2(-0.3, -1.0).normalized()
	for i in range(25):
		await physics_frame
	if args.size() > 2 and args[2] == "close":
		main.camera_rig.camera.position *= 0.4
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit()
