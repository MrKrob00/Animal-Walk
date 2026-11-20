class_name Leash
extends MeshInstance3D
## A soft rope between two hands: verlet points, drawn as a thin ribbon facing the camera.

const POINTS := 24
const WIDTH := 0.02
const SMOOTH_PASSES := 3
const GRAVITY := Vector3(0, -9.8, 0)

var a: Node3D          ## anchor at one end (the wolf's hand)
var b: Node3D          ## anchor at the other end (the kit's hand)
var length := 3.6      ## rope length in 3D (a little slack over the walking limit)
var use_ground := true
## Bodies the rope lies over instead of passing through: [a, b, radius] capsules in world space,
## set every frame by the game (TOFU's torso and tail).
var colliders: Array = []

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


## Moves one end to a new anchor without a whip: the rope is laid out again, at rest.
func reattach_b(node: Node3D) -> void:
	b = node
	if a != null and b != null and is_inside_tree():
		var pa := a.global_position
		var pb := b.global_position
		for i in range(POINTS):
			var t := float(i) / (POINTS - 1)
			var p := pa.lerp(pb, t)
			p.y -= sin(t * PI) * 0.3   # a soft sag, as if it had been lying there
			pts[i] = p
			_prev[i] = p


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
		for c in colliders:
			for i in range(1, POINTS - 1):
				pts[i] = push_out(pts[i], c[0], c[1], c[2])
		if use_ground:
			for i in range(1, POINTS - 1):
				var g := maxf(Terrain.height(pts[i].x, pts[i].z), 0.0) + 0.03   # floats on the sea
				if pts[i].y < g:
					pts[i].y = g
	pts[0] = pa
	pts[POINTS - 1] = pb


## `p` moved out of the capsule a-b of `radius` (unchanged if it is outside).
static func push_out(p: Vector3, a: Vector3, b: Vector3, radius: float) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var c := a + ab * t
	var d := p - c
	var l := d.length()
	if l >= radius:
		return p
	if l < 1e-5:
		d = Vector3.UP
		l = 1.0
	return c + d / l * radius


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
	var line := smooth(pts)
	var n := line.size()
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(n):
		var dir := line[mini(i + 1, n - 1)] - line[maxi(i - 1, 0)]
		var to_eye := (eye - line[i]).normalized()
		var side := dir.cross(to_eye).normalized() * WIDTH
		_im.surface_set_normal(to_eye)
		_im.surface_add_vertex(line[i] + side)
		_im.surface_set_normal(to_eye)
		_im.surface_add_vertex(line[i] - side)
	_im.surface_end()


## The rope drawn as a smooth curve near the simulated points (corners cut three times, Chaikin),
## so a slack rope bends round instead of folding into sharp corners. The ends stay put.
static func smooth(p: PackedVector3Array) -> PackedVector3Array:
	var line := p
	for _pass in SMOOTH_PASSES:
		var out := PackedVector3Array([line[0]])
		for i in range(line.size() - 1):
			out.append(line[i].lerp(line[i + 1], 0.25))
			out.append(line[i].lerp(line[i + 1], 0.75))
		out.append(line[line.size() - 1])
		line = out
	return line
