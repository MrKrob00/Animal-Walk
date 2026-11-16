class_name CameraRig
extends Node3D
## High three-quarter camera that floats after the pair. It never turns.

const PITCH_DEG := 52.0
const DISTANCE := 8.0
const FOV := 40.0

var target: Node3D       ## the wolf
var second: Node3D       ## the kit (the camera leans a little toward it)
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.far = 160.0
	var p := deg_to_rad(PITCH_DEG)
	camera.position = Vector3(0, sin(p) * DISTANCE, cos(p) * DISTANCE)
	camera.rotation.x = -p
	add_child(camera)
	camera.make_current()
	if target != null:
		position = _focus()


func _focus() -> Vector3:
	var f := target.position
	if second != null:
		f = f.lerp(second.position, 0.3)
	return f + Vector3(0, 0.6, 0)


func _process(delta: float) -> void:
	if target == null:
		return
	position = position.lerp(_focus(), 1.0 - exp(-4.0 * delta))
