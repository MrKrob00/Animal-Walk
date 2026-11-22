class_name MapScreen
extends CanvasLayer
## The map, opened from the pause menu ("Карта"): MapView over the paused game, "Назад" closes it.

signal closed

var view: MapView


func _init(explore: Exploration, walkers: Array) -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	view = MapView.new()
	view.explore = explore
	view.walkers = walkers
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	var back := PauseMenu.button("Назад", func(): closed.emit(), 180.0)
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.offset_left = -220
	back.offset_right = -30
	back.offset_top = 20
	back.offset_bottom = 84
	add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()
