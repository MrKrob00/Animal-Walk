class_name Puffs
extends Node3D
## Little bursts of sand under the paws. A small pool of one-shot CPU particles.

const POOL := 8

var _pool: Array[CPUParticles3D] = []
var _next := 0


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 5
	mesh.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#efe0bb")
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	for i in range(POOL):
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 5
		p.lifetime = 0.45
		p.explosiveness = 1.0
		p.mesh = mesh
		p.direction = Vector3.UP
		p.spread = 55.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.3
		p.gravity = Vector3(0, -4.0, 0)
		p.scale_amount_min = 0.05
		p.scale_amount_max = 0.09
		p.scale_amount_curve = curve
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_pool.append(p)


func puff(pos: Vector3, size := 1.0) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.global_position = Vector3(pos.x, Terrain.height(pos.x, pos.z) + 0.03, pos.z)
	p.scale_amount_min = 0.05 * size
	p.scale_amount_max = 0.09 * size
	p.restart()
