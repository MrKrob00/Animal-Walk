extends SceneTree
## Herm's places to find and its paper map (the player: a real map, paths dashed until walked,
## the goals from it): what stands at the places, which are goals (none on an islet or a reef),
## paths marked walked as the walkers pass, places found close by, kept between games, and the map
## opened from the pause menu.

func _initialize() -> void:
	_run()


func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var names := {}
	var with_things := 0
	for f in main.finds:
		names[f.name] = f
		if f.has != "":
			with_things += 1
	Check.ok(main.finds.size() >= 30 and main.finds.size() <= 70, "Herm's named places are goals (%d)" % main.finds.size())
	Check.ok(names.has("Shell Beach Café") and names.has("Pierre Aux Rats (Obelisk)") and names.has("Herm Harbour") and names.has("Copper Mining"), "the cafe, the obelisk, the harbour and the mine among them")
	Check.ok(with_things >= 15, "something stands at %d of them" % with_things)
	Check.ok(not names.has("Putrainez") and not names.has("Les Petits Bouillons") and not names.has("Crevichon"), "nothing on an islet or a reef (nobody can walk there)")
	var bad := 0
	for f in main.finds:
		if not Terrain.reachable(f.pos.x, f.pos.y):
			bad += 1
	Check.ok(bad == 0, "every goal can be walked to")
	var ex: Exploration = main.explore
	ex.reset()
	var piece: Array = ex.pieces[ex.pieces.size() / 2]
	var mid: Vector2 = (piece[0] + piece[1]) * 0.5
	var got := []
	ex.found.connect(func(f): got.append(f.name))
	ex.visit([mid])
	var far := 0
	for i in ex.pieces.size():
		if ex.walked[i] == 1 and (ex.pieces[i][0] as Vector2).distance_to(mid) > 10.0:
			far += 1
	Check.ok(ex.walked[ex.pieces.size() / 2] == 1 and far == 0, "passing a path marks that bit of it walked, and only nearby")
	var obelisk: Dictionary = names["Pierre Aux Rats (Obelisk)"]
	ex.visit([obelisk.pos + Vector2(3, 0)])
	Check.ok(ex.found_names.has(obelisk.name) and obelisk.name in got, "coming close to a place finds it")
	ex.save_state()
	var again := Exploration.new(main.finds)
	Check.ok(again.found_names.has(obelisk.name) and again.walked[ex.pieces.size() / 2] == 1, "kept for the next game")
	ex.reset()
	ex.save_state()
	main.pause()
	await process_frame
	main.pause_menu.map.emit()
	await process_frame
	Check.ok(main.map_screen != null and not main.pause_menu.visible, "Карта opens the map from the pause menu")
	main.map_screen.closed.emit()
	await process_frame
	Check.ok(main.map_screen == null and main.pause_menu.visible, "Назад goes back to the menu")
	main.pause_menu.close()
	Check.finish(self)
