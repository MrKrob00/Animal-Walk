class_name Player
extends Node3D
## The wolf: walks where the stick or keys point. The camera never turns,
## so "up" on the stick is always "away from the camera" (-Z).

const SPEED := 3.2
const ACCEL := 14.0
const RADIUS := 0.35

var world: Node              ## needs resolve(pos, radius) -> Vector3
var joystick: Node           ## needs `vector: Vector2`
var critter: Critter
var velocity := Vector3.ZERO
var forced_input := Vector2.ZERO   ## for scripted runs (screenshots, tests)
var drag_slow := 1.0               ## the kit slows us a little when the leash is taut


func _ready() -> void:
	critter = Critter.new()
	critter.name = "Wolf"
	add_child(critter)
	critter.build(Critter.WOLF)


func read_input() -> Vector2:
	var v := forced_input
	if v == Vector2.ZERO and joystick != null:
		v = joystick.vector
	if v == Vector2.ZERO:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	var v := read_input()
	var target := Vector3(v.x, 0, v.y) * SPEED * drag_slow
	velocity = velocity.move_toward(target, ACCEL * delta)
	var p := position + velocity * delta
	if world != null:
		p = world.resolve(p, RADIUS)
	p.y = Terrain.height(p.x, p.z)
	position = p
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), 1.0 - exp(-10.0 * delta))
	critter.speed = hv.length()
