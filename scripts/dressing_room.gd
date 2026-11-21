class_name DressingRoom
extends CanvasLayer
## The dressing room (the player asked; from the pause menu's "Костюмы"): the real 3D bunny on a
## little stage in a world of her own (a SubViewport), turned by a drag, and on the right the
## outfits: the ready sets and each slot's items, one per slot. "Готово" keeps the choice
## (Wardrobe) and puts it on the bunny in the game.

signal done(choice: Dictionary)

const BACK := Color("#d9cdbd")
const STAGE := Color("#b89f86")
const INK := Color("#3b4a5e")
const WORN := Color("#bfdcb4")    ## the buttons of what she wears
const TURN := 0.008          ## radians per pixel dragged

var choice := {}
var bunny: Actor
var _vp: SubViewport
var _buttons := {}           ## item -> Button
var _drag := false
var _finger := -1


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	choice = Wardrobe.load_choice()
	var bg := ColorRect.new()
	bg.color = BACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.anchor_right = 0.62
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	view.add_child(_vp)
	_build_stage()
	_build_panel()


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.73, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 25, 0)
	sun.light_energy = 0.8
	_vp.add_child(sun)
	var stage := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.58
	cyl.height = 0.06
	stage.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = STAGE
	stage.material_override = sm
	stage.position = Vector3(0, -0.03, 0)
	_vp.add_child(stage)
	bunny = Actor.new()
	bunny.setup(Actor.BUNNY)
	bunny.rotation.y = 0.35
	_vp.add_child(bunny)
	bunny.set_outfit(choice)
	var cam := Camera3D.new()
	cam.fov = 32
	_vp.add_child(cam)
	cam.position = Vector3(0, 0.95, 2.95)
	cam.look_at(Vector3(0, 0.84, 0))
	cam.make_current()


func _build_panel() -> void:
	var panel := VBoxContainer.new()
	panel.anchor_left = 0.62
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 12
	panel.offset_right = -24
	panel.offset_top = 32
	panel.offset_bottom = -24
	panel.add_theme_constant_override("separation", 10)
	add_child(panel)
	panel.add_child(_label("Костюмы", 40))
	panel.add_child(_label("Комплекты", 24))
	var sets := HBoxContainer.new()
	sets.add_theme_constant_override("separation", 10)
	panel.add_child(sets)
	for s in Wardrobe.SETS:
		var b := PauseMenu.button(s, _wear_set.bind(s), 150.0)
		b.toggle_mode = true
		sets.add_child(b)
		_buttons["set:" + s] = b
	for slot in Wardrobe.SLOTS:
		panel.add_child(_label(Wardrobe.SLOTS[slot], 24))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		for item in Wardrobe.items_for(slot):
			var b := PauseMenu.button(Wardrobe.ITEMS[item].name if item != "" else "Нет", _wear.bind(slot, item), 150.0)
			b.toggle_mode = true
			row.add_child(b)
			_buttons[item] = b
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(spacer)
	panel.add_child(PauseMenu.button("Готово", _finish))
	_mark()


func _label(t: String, size: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l


func _wear(slot: String, item: String) -> void:
	choice[slot] = item
	bunny.set_outfit(choice)
	_mark()


func _wear_set(name: String) -> void:
	choice = (Wardrobe.SETS[name] as Dictionary).duplicate()
	bunny.set_outfit(choice)
	_mark()


## Lights the buttons of what she wears.
func _mark() -> void:
	for item in _buttons:
		var b: Button = _buttons[item]
		var on := false
		if item.begins_with("set:"):
			var outfit: Dictionary = Wardrobe.SETS[item.substr(4)]
			on = outfit.keys().all(func(k): return choice.get(k, "") == outfit[k])
		elif item != "":
			on = choice.get(Wardrobe.ITEMS[item].slot, "") == item
		b.set_pressed_no_signal(on)
		var sb := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.bg_color = WORN if b.button_pressed else PauseMenu.PANEL
		sb.border_color = Color(INK, 0.6 if b.button_pressed else 0.25)
		sb.set_border_width_all(3 if b.button_pressed else 2)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, sb)


func _finish() -> void:
	Wardrobe.save_choice(choice)
	done.emit(choice)


## A drag on the stage turns her round.
func _input(event: InputEvent) -> void:
	var w := get_viewport().get_visible_rect().size.x * 0.62
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x < w and _finger < 0:
			_finger = event.index
		elif not event.pressed and event.index == _finger:
			_finger = -1
	elif event is InputEventScreenDrag and event.index == _finger:
		bunny.rotation.y += event.relative.x * TURN
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		bunny.rotation.y += event.relative.x * TURN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish()
