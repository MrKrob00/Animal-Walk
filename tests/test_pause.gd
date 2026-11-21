extends SceneTree
## The pause button (the player asked): the game stops under the pause menu, "Костюмы" opens the
## dressing room with the real bunny in it, a set or a single item puts the clothes on her there,
## "Готово" keeps the choice and dresses the bunny in the game, "Продолжить" goes on.

func _initialize() -> void:
	_run()


func _shown(a: Node, node: String) -> bool:
	var n := a.find_child(node, true, false)
	return n != null and (n as Node3D).visible


func _press_touch(b: Control) -> void:
	for down in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = b.center()
		e.pressed = down
		b._input(e)


func _run() -> void:
	var before := Wardrobe.load_choice()
	Wardrobe.save_choice(Wardrobe.DEFAULT)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var bunny: Actor = main.bunny
	_press_touch(main.pause_button)
	await process_frame
	Check.ok(paused and main.pause_menu != null, "the pause button stops the game and opens the menu")
	var p0: Vector3 = main.tofu.position
	for i in 20:
		await physics_frame
	Check.ok(main.tofu.position == p0, "nothing moves while paused")
	main.pause_menu.costumes.emit()
	await process_frame
	await process_frame
	var room: DressingRoom = main.dressing_room
	Check.ok(room != null and not main.pause_menu.visible, "Костюмы opens the dressing room")
	Check.ok(room.bunny != null and room.bunny.skeleton != null, "the real bunny stands in it")
	var bone := Gait.find_bone(room.bunny.skeleton, Actor.BUNNY.bones.head)
	var c0 := room.bunny.skeleton.get_bone_global_pose(bone).origin
	for i in 40:
		await process_frame
	Check.ok(room.bunny.skeleton.get_bone_global_pose(bone).origin != c0, "she is alive in it (breathing, looking round) while the game is paused")
	room._wear_set("Agnes")
	Check.ok(_shown(room.bunny, "Blouse") and _shown(room.bunny, "Sundress") and not _shown(room.bunny, "Object_670"), "the Agnes set dresses her in the room")
	room._wear("lower", "shorts")
	Check.ok(_shown(room.bunny, "Blouse") and _shown(room.bunny, "Object_672") and not _shown(room.bunny, "Sundress"), "one item at a time: the blouse with her shorts")
	Check.ok(not _shown(bunny, "Blouse"), "the game's bunny is not changed before Готово")
	room._finish()
	await process_frame
	Check.ok(main.dressing_room == null and main.pause_menu.visible, "Готово goes back to the menu")
	Check.ok(_shown(bunny, "Blouse") and _shown(bunny, "Object_672") and not _shown(bunny, "Object_670"), "the game's bunny wears the choice")
	var saved := Wardrobe.load_choice()
	Check.ok(saved.upper == "blouse" and saved.lower == "shorts", "the choice is kept")
	main.pause_menu.close()
	await process_frame
	Check.ok(not paused and main.pause_menu == null, "Продолжить goes on")
	Wardrobe.save_choice(before)
	Check.finish(self)
