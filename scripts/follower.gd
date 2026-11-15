class_name Follower
extends Node3D
## The fox kit: trots after the wolf, and is dragged along when the leash is taut.

const WALK := 2.9
const RADIUS := 0.2

var world: Node
var leader: Player
var leash_len := 3.0
var critter: Critter
var velocity := Vector3.ZERO
var dragged := false


func _ready() -> void:
	critter = Critter.new()
	critter.name = "Fox"
	add_child(critter)
	critter.build(Critter.FOX_KIT)


## Keeps `kid` within `length` of `owner` on the ground plane.
static func clamp_to_leash(kid: Vector3, owner: Vector3, length: float) -> Vector3:
	var d := Vector2(kid.x - owner.x, kid.z - owner.z)
	if d.length() <= length:
		return kid
	d = d.normalized() * length
	return Vector3(owner.x + d.x, kid.y, owner.z + d.y)


## How fast the kit wants to walk toward the leader at this distance.
static func desired_speed(dist: float, length: float) -> float:
	var start := length * 0.6
	if dist <= start:
		return 0.0
	return WALK * clampf((dist - start) / (length * 0.3), 0.3, 1.0)


func _physics_process(delta: float) -> void:
	if leader == null:
		return
	var to := leader.position - position
	to.y = 0.0
	var dist := to.length()
	var want := Vector3.ZERO
	if dist > 0.001:
		want = to / dist * desired_speed(dist, leash_len)
	velocity = velocity.move_toward(want, 10.0 * delta)
	var p := position + velocity * delta
	var free := p
	p = clamp_to_leash(p, leader.position, leash_len)
	dragged = free.distance_to(p) > 0.002
	if world != null:
		p = world.resolve(p, RADIUS)
	p.y = Terrain.height(p.x, p.z)
	var moved := Vector2(p.x - position.x, p.z - position.z) / maxf(delta, 0.0001)
	position = p
	leader.drag_slow = 0.85 if dragged else 1.0
	if dragged:
		# Pulled along: faces the wolf and leans back.
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-12.0 * delta))
	elif moved.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(moved.x, moved.y), 1.0 - exp(-10.0 * delta))
	critter.speed = moved.length()
	critter.lean = -0.3 if dragged else 0.0
