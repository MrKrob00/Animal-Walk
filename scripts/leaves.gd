class_name Leaves
extends CPUParticles3D
## Leaves drifting down near the woods (the player: leaves and wind for a pretty picture): a few
## dozen paper leaves round the camera's focus, tumbling and carried the wind's way
## (foliage.gdshader's wind_dir), only while there are trees close by. CPU particles: cheap and
## safe on the phone's GL.

const AMOUNT := 32
const NEAR_WOOD := 18.0   ## metres: falling while a wood is this close

var follow: Node3D        ## what the leaves fall round (the camera rig)
var _check := 0.0


func _ready() -> void:
	amount = AMOUNT
	lifetime = 7.0
	preprocess = 4.0
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(10, 2, 10)
	direction = Vector3(0.8, -0.4, 0.6)
	spread = 25.0
	gravity = Vector3(0.45, -0.55, 0.35)   # down, and with the wind
	initial_velocity_min = 0.2
	initial_velocity_max = 0.6
	angular_velocity_min = -160.0
	angular_velocity_max = 160.0
	angle_min = 0.0
	angle_max = 360.0
	scale_amount_min = 0.7
	scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color("#c98a3a"))
	g.set_color(1, Color("#8fb04a"))
	color_initial_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.07)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	q.material = m
	mesh = q
	local_coords = false
	emitting = false


func _process(delta: float) -> void:
	if follow == null:
		return
	global_position = follow.global_position + Vector3(0, 5.0, 0)
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		emitting = _woods_near(follow.global_position)


static func _woods_near(p: Vector3) -> bool:
	for a in 8:
		for r in [4.0, 10.0, NEAR_WOOD]:
			var q: Vector2 = Vector2(p.x, p.z) + Vector2.from_angle(a * TAU / 8.0) * r
			if Terrain.kind(q.x, q.y) == 3:
				return true
	return false
