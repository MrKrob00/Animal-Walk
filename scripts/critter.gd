class_name Critter
extends Node3D
## A paper-craft anthro animal built from faceted parts, animated in code.
## Faces +Z. Origin at the feet. Set `speed` every frame; it walks by itself.

signal footstep(pos: Vector3, size: float)

## Big grey wolf with a mustard scarf: the hero, holds the leash.
const WOLF := {
	"leg_len": 0.8, "hip_w": 0.16, "leg_r": 0.09,
	"torso_h": 0.72, "torso_w": 0.36, "torso_d": 0.28,
	"arm_len": 0.62, "arm_r": 0.075,
	"head_r": 0.27, "snout_len": 0.3, "ear_h": 0.24, "ear_w": 0.1,
	"tail_len": 0.75, "step_len": 0.85,
	"fur": "#9a98a3", "belly": "#efe9df", "dark": "#3a3840", "legs": "#9a98a3",
	"tail_tip": "#e9e4dc", "accent": "#e0a234", "accessory": "scarf",
}

## Little fox kit in a red knitted hat: follows on the leash.
const FOX_KIT := {
	"leg_len": 0.3, "hip_w": 0.08, "leg_r": 0.055,
	"torso_h": 0.34, "torso_w": 0.19, "torso_d": 0.16,
	"arm_len": 0.27, "arm_r": 0.045,
	"head_r": 0.22, "snout_len": 0.15, "ear_h": 0.21, "ear_w": 0.085,
	"tail_len": 0.48, "step_len": 0.4,
	"fur": "#e2742f", "belly": "#f6efe4", "dark": "#3a2a26", "legs": "#3a2a26",
	"tail_tip": "#f6efe4", "accent": "#d0393b", "accessory": "hat",
}

var speed := 0.0        ## horizontal speed, m/s (set by the controller)
var lean := 0.0         ## forward (+) / backward (-) lean, radians (e.g. being dragged)
var hand_r: Node3D      ## right hand: leash anchor
var hand_l: Node3D      ## left hand: leash anchor

var _p: Dictionary
var _rig: Node3D
var _body: Node3D
var _hip_l: Node3D
var _hip_r: Node3D
var _sh_l: Node3D
var _sh_r: Node3D
var _head: Node3D
var _tail: Node3D
var _phase := 0.0
var _time := 0.0
var _last_side := 0


func build(p: Dictionary) -> void:
	_p = p
	var mat := PaperMesh.material()
	var fur := PaperMesh.col(p.fur)
	var belly := PaperMesh.col(p.belly)
	var dark := PaperMesh.col(p.dark)
	var legs := PaperMesh.col(p.legs)
	var accent := PaperMesh.col(p.accent)
	var hip_y: float = p.leg_len
	var down := Basis(Vector3.RIGHT, PI)   # +Y becomes -Y: limbs hang down

	_rig = _node(self, "Rig", Vector3.ZERO)

	# Legs: pivot at the hip, foot at the bottom.
	for side in [-1, 1]:
		var hip := _node(_rig, "Hip", Vector3(side * p.hip_w, hip_y, 0))
		var st := PaperMesh.begin()
		PaperMesh.frustum(st, Transform3D(down, Vector3.ZERO), p.leg_r, p.leg_r * 0.75, p.leg_len - 0.05, 6, legs)
		PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0, -p.leg_len + p.leg_r * 0.5, p.leg_r * 0.6)),
				Vector3(p.leg_r * 0.9, p.leg_r * 0.6, p.leg_r * 1.5), 6, 3, dark)
		_mesh(hip, st, mat)
		if side < 0:
			_hip_l = hip
		else:
			_hip_r = hip

	# Body: torso, belly, scarf. Arms, head and tail hang off it.
	_body = _node(_rig, "Body", Vector3.ZERO)
	var st_body := PaperMesh.begin()
	PaperMesh.ellipsoid(st_body, Transform3D(Basis.IDENTITY, Vector3(0, hip_y + p.torso_h * 0.5, 0)),
			Vector3(p.torso_w, p.torso_h * 0.58, p.torso_d), 8, 5, fur)
	PaperMesh.ellipsoid(st_body, Transform3D(Basis.IDENTITY, Vector3(0, hip_y + p.torso_h * 0.45, p.torso_d * 0.42)),
			Vector3(p.torso_w * 0.66, p.torso_h * 0.44, p.torso_d * 0.62), 8, 4, belly)
	if p.accessory == "scarf":
		var neck_y: float = hip_y + p.torso_h * 0.9
		PaperMesh.frustum(st_body, Transform3D(Basis.IDENTITY, Vector3(0, neck_y, 0)), p.torso_w * 0.68, p.torso_w * 0.52, 0.14, 8, accent)
		PaperMesh.frustum(st_body, Transform3D(Basis(Vector3.RIGHT, PI - 0.25), Vector3(p.torso_w * 0.35, neck_y + 0.02, p.torso_d * 0.75)),
				0.07, 0.06, 0.38, 4, accent)
	_mesh(_body, st_body, mat)

	for side in [-1, 1]:
		var sh := _node(_body, "Shoulder", Vector3(side * (p.torso_w + p.arm_r * 0.6), hip_y + p.torso_h * 0.82, 0))
		var st := PaperMesh.begin()
		PaperMesh.frustum(st, Transform3D(down, Vector3.ZERO), p.arm_r, p.arm_r * 0.8, p.arm_len, 6, fur)
		PaperMesh.ellipsoid(st, Transform3D(Basis.IDENTITY, Vector3(0, -p.arm_len, 0)), Vector3.ONE * p.arm_r * 1.15, 6, 3, dark)
		_mesh(sh, st, mat)
		var hand := _node(sh, "Hand", Vector3(0, -p.arm_len - p.arm_r * 0.5, 0))
		if side < 0:
			_sh_l = sh
			hand_l = hand
		else:
			_sh_r = sh
			hand_r = hand

	# Head: skull, muzzle, nose, eyes, ears, hat.
	_head = _node(_body, "Head", Vector3(0, hip_y + p.torso_h, 0))
	var hr: float = p.head_r
	var st_head := PaperMesh.begin()
	PaperMesh.ellipsoid(st_head, Transform3D(Basis.IDENTITY, Vector3(0, hr * 0.9, 0)), Vector3(hr, hr * 0.92, hr * 0.95), 8, 6, fur)
	var fwd := Basis(Vector3.RIGHT, PI * 0.5)   # +Y becomes +Z: muzzle points forward
	PaperMesh.frustum(st_head, Transform3D(fwd, Vector3(0, hr * 0.68, hr * 0.62)), hr * 0.46, hr * 0.17, p.snout_len, 7, belly)
	PaperMesh.ellipsoid(st_head, Transform3D(Basis.IDENTITY, Vector3(0, hr * 0.7, hr * 0.62 + p.snout_len)), Vector3.ONE * hr * 0.15, 5, 3, dark)
	for side in [-1, 1]:
		PaperMesh.ellipsoid(st_head, Transform3D(Basis.IDENTITY, Vector3(side * hr * 0.4, hr * 1.02, hr * 0.8)),
				Vector3(hr * 0.12, hr * 0.15, hr * 0.08), 5, 3, dark)
		var ear := Basis(Vector3.FORWARD, side * -0.32).scaled(Vector3(1.0, 1.0, 0.45))
		PaperMesh.frustum(st_head, Transform3D(ear, Vector3(side * hr * 0.55, hr * 1.45, -hr * 0.05)), p.ear_w, 0.0, p.ear_h, 3, fur)
	if p.accessory == "hat":
		PaperMesh.ellipsoid(st_head, Transform3D(Basis.IDENTITY, Vector3(0, hr * 1.38, -hr * 0.05)), Vector3(hr * 0.98, hr * 0.62, hr * 0.98), 8, 4, accent)
		PaperMesh.frustum(st_head, Transform3D(Basis.IDENTITY, Vector3(0, hr * 1.05, -hr * 0.05)), hr * 1.0, hr * 0.98, hr * 0.22, 8, belly)
		PaperMesh.ellipsoid(st_head, Transform3D(Basis.IDENTITY, Vector3(0, hr * 2.05, -hr * 0.05)), Vector3.ONE * hr * 0.24, 6, 3, belly)
	_mesh(_head, st_head, mat)

	# Tail: back and down from the hips, light tip.
	_tail = _node(_body, "Tail", Vector3(0, hip_y + 0.04, -p.torso_d * 0.85))
	var tl: float = p.tail_len
	var tail_b := Basis(Vector3.RIGHT, 0.55)
	var st_tail := PaperMesh.begin()
	PaperMesh.ellipsoid(st_tail, Transform3D(tail_b, tail_b * Vector3(0, 0, -tl * 0.45)), Vector3(tl * 0.22, tl * 0.22, tl * 0.48), 7, 5, fur)
	PaperMesh.ellipsoid(st_tail, Transform3D(tail_b, tail_b * Vector3(0, 0, -tl * 0.9)), Vector3(tl * 0.15, tl * 0.15, tl * 0.16), 6, 3, PaperMesh.col(p.tail_tip))
	_mesh(_tail, st_tail, mat)


func _process(delta: float) -> void:
	if _rig == null:
		return
	_time += delta
	var walk := clampf(speed / 2.0, 0.0, 1.0)
	_phase += delta * speed / float(_p.step_len) * PI
	var s := sin(_phase)
	var swing := 0.6 * walk
	_hip_l.rotation.x = s * swing
	_hip_r.rotation.x = -s * swing
	_sh_l.rotation.x = -s * swing * 0.8
	_sh_r.rotation.x = s * swing * 0.8
	_sh_l.rotation.z = -0.12
	_sh_r.rotation.z = 0.12
	_body.position.y = absf(cos(_phase)) * 0.05 * walk * float(_p.leg_len) + sin(_time * 2.4) * 0.006
	_body.rotation.y = s * 0.08 * walk
	_head.rotation.x = 0.06 * walk + sin(_time * 1.7) * 0.03
	_tail.rotation.y = sin(_time * (3.0 + 6.0 * walk)) * (0.25 + 0.2 * walk)
	_rig.rotation.x = lerpf(_rig.rotation.x, lean + 0.08 * walk, 1.0 - exp(-8.0 * delta))
	# A footstep each time a foot passes under the hip.
	var side := 1 if s > 0.0 else -1
	if walk > 0.15 and side != _last_side:
		var hip := _hip_l if side > 0 else _hip_r
		footstep.emit(hip.global_transform * Vector3(0, -float(_p.leg_len), 0), float(_p.leg_r) / 0.09)
	_last_side = side


func _node(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = PaperMesh.commit(st)
	mi.material_override = mat
	parent.add_child(mi)
