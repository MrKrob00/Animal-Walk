class_name PauseMenu
extends CanvasLayer
## The pause menu (the player asked): the game stops under it; "Продолжить" goes on, "Карта" shows
## the map (MapScreen), "Костюмы" opens the dressing room (DressingRoom). Esc / P closes it.

signal costumes
signal map
signal closed

const PANEL := Color("#f4ede2")
const INK := Color("#3b4a5e")


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.12, 0.16, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var mid := CenterContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(mid)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	mid.add_child(box)
	var title := Label.new()
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)
	box.add_child(button("Продолжить", close))
	box.add_child(button("Карта", func(): map.emit()))
	box.add_child(button("Костюмы", func(): costumes.emit()))


## A soft rounded button (shared with the dressing room).
static func button(text: String, on_press: Callable, wide := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(wide, 72)
	b.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = PANEL.darkened(0.08 if state == "pressed" else 0.0)
		sb.set_corner_radius_all(22)
		sb.border_color = Color(INK, 0.25 if state != "focus" else 0.5)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	b.pressed.connect(on_press)
	return b


func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
