class_name Leash
extends MeshInstance3D
## A soft rope between two hands: verlet points, drawn as a thin ribbon facing the camera.

const POINTS := 16
const WIDTH := 0.035
const GRAVITY := Vector3(0, -9.8, 0)

var a: Node3D          ## anchor at one end (the wolf's hand)
var b: Node3D          ## anchor at the other end (the kit's hand)
var length := 3.6      ## rope length in 3D (a little slack over the walking limit)
var use_ground := true

var pts := PackedVector3Array()
var _prev := PackedVector3Array()
var _im := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#d8414a")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	material_override = m
	if a != null and b != null:
		reset(a.global_position, b.global_position)


func reset(pa: Vector3, pb: Vector3) -> void:
	pts.resize(POINTS)
	_prev.resize(POINTS)
	for i in range(POINTS):
		pts[i] = pa.lerp(pb, float(i) / (POINTS - 1))
		_prev[i] = pts[i]


func simulate(delta: float, pa: Vector3, pb: Vector3) -> void:
	var rest := length / (POINTS - 1)
	for i in range(1, POINTS - 1):
		var v := (pts[i] - _prev[i]) * 0.96
		_prev[i] = pts[i]
		pts[i] += v + GRAVITY * delta * delta
	for _k in range(10):
		pts[0] = pa
		pts[POINTS - 1] = pb
		for i in range(POINTS - 1):
			var d := pts[i + 1] - pts[i]
			var l := d.length()
			if l > rest and l > 0.0001:
				var fix := d * (0.5 * (l - rest) / l)
				if i > 0:
					pts[i] += fix
				else:
					pts[i + 1] -= fix
				if i + 1 < POINTS - 1:
					pts[i + 1] -= fix
				else:
					pts[i] += fix
		if use_ground:
			for i in range(1, POINTS - 1):
				var g := Terrain.height(pts[i].x, pts[i].z) + 0.03
				if pts[i].y < g:
					pts[i].y = g
	pts[0] = pa
	pts[POINTS - 1] = pb


func _physics_process(delta: float) -> void:
	if a == null or b == null:
		return
	if pts.size() != POINTS:
		reset(a.global_position, b.global_position)
	simulate(delta, a.global_position, b.global_position)


func _process(_delta: float) -> void:
	if pts.size() != POINTS:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(POINTS):
		var dir := pts[mini(i + 1, POINTS - 1)] - pts[maxi(i - 1, 0)]
		var to_eye := (eye - pts[i]).normalized()
		var side := dir.cross(to_eye).normalized() * WIDTH
		_im.surface_set_normal(to_eye)
		_im.surface_add_vertex(pts[i] + side)
		_im.surface_set_normal(to_eye)
		_im.surface_add_vertex(pts[i] - side)
	_im.surface_end()
