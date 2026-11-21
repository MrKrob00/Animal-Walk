extends SceneTree
## A short clip of the pause menu and the dressing room: walk, pause, Костюмы, turn her round,
## the Agnes set, the blouse with shorts, Готово, Продолжить, walk on.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 --script tools/pause_clip.gd --write-movie out.png --fixed-fps 30

func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.forced_input = Vector2(0.3, -1.0)
	await _frames(45)
	main.forced_input = Vector2.ZERO
	await _frames(20)
	main.pause()
	await _frames(35)
	main.pause_menu.costumes.emit()
	await _frames(40)
	var room: DressingRoom = main.dressing_room
	for i in 60:
		room.bunny.rotation.y += TAU / 60.0
		await process_frame
	room._wear_set("Agnes")
	await _frames(40)
	for i in 30:
		room.bunny.rotation.y -= 0.05
		await process_frame
	room._wear("lower", "shorts")
	await _frames(40)
	room._wear("upper", "top")
	room._wear("lower", "sundress")
	await _frames(40)
	room._wear_set("Agnes")
	await _frames(25)
	room._finish()
	await _frames(25)
	main.pause_menu.close()
	main.forced_input = Vector2(-0.4, -1.0)
	await _frames(70)
	quit()
