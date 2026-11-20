class_name Actor
extends Node3D
## A character from a model file: scaled to a height, stood on the terrain,
## walked by `steer`, animated by Gait. Faces +Z.

signal footstep(pos: Vector3, size: float)

## Chobby Bun: the hero (rigify deform bones from the Sketchfab file).
## Her deform bones hang from rigify's helper bones, which nothing moves here, so the legs,
## arms, head, chest and fingers are re-hung under the spine and the hands ("reparent").
const BUNNY := {
	"path": "res://assets/free_download_-_chobby_bun.glb", "height": 1.6,
	"walk": 1.5, "run": 3.4, "stride": 1.45, "run_stride": 2.5, "radius": 0.3,
	"bones": {
		"pelvis": "DEF-spine", "spine": ["DEF-spine.001", "DEF-spine.002", "DEF-spine.003"],
		"neck": "DEF-neck", "head": "DEF-head",
		"thigh_l": "DEF-thigh.L", "shin_l": "DEF-shin.L", "foot_l": "DEF-foot.L",
		"thigh_r": "DEF-thigh.R", "shin_r": "DEF-shin.R", "foot_r": "DEF-foot.R",
		"upper_arm_l": "DEF-upper_arm.L", "forearm_l": "DEF-forearm.L",
		"upper_arm_r": "DEF-upper_arm.R", "forearm_r": "DEF-forearm.R",
		"hand_l": "DEF-hand.L", "hand_r": "DEF-hand.R",
		"ears": ["DEF-ear01.L", "DEF-ear01.R"],
		"tail": ["DEF-spine.004"],
		"soft": [["DEF-breast01.L", "DEF-breast04.L"], ["DEF-breast01.R", "DEF-breast04.R"]],
		"arms_down": true,
		"clip_arms": true, "torso_swing": 0.5,   # arms aimed like the clip's from arms-down (her V-sign rest wrings copied arms); half the clips' torso swing
		"tires": true,
		# Real clips (tools: ClipSource / Retarget): source bone -> our bone.
		"clips": {
			"DEF-hips": "DEF-spine", "DEF-spine.001": "DEF-spine.001", "DEF-spine.002": "DEF-spine.002",
			"DEF-spine.003": "DEF-spine.003", "DEF-neck": "DEF-neck", "DEF-head": "DEF-head",
			"DEF-thigh.L": "DEF-thigh.L", "DEF-shin.L": "DEF-shin.L", "DEF-foot.L": "DEF-foot.L", "DEF-toe.L": "DEF-toe.L",
			"DEF-thigh.R": "DEF-thigh.R", "DEF-shin.R": "DEF-shin.R", "DEF-foot.R": "DEF-foot.R", "DEF-toe.R": "DEF-toe.R",
		},
		"fingers": {"finger": "DEF-f_%s.%02d.%s", "palm": "DEF-palm.%02d.%s", "thumb": "DEF-thumb.%02d.%s"},
		"reparent": {
			"DEF-thigh.L": "DEF-spine", "DEF-thigh.R": "DEF-spine",
			"DEF-butt.L": "DEF-spine", "DEF-butt.R": "DEF-spine", "DEF-spine.004": "DEF-spine",
			"DEF-shoulder.L": "DEF-spine.003", "DEF-shoulder.R": "DEF-spine.003",
			"DEF-upper_arm.L": "DEF-spine.003", "DEF-upper_arm.R": "DEF-spine.003",
			"DEF-peck.B.L": "DEF-spine.003", "DEF-peck.B.R": "DEF-spine.003",
			"DEF-peck.U.L": "DEF-spine.003", "DEF-peck.U.R": "DEF-spine.003",
			"DEF-breast01.L": "DEF-spine.003", "DEF-breast01.R": "DEF-spine.003",
			"DEF-neck": "DEF-spine.003",
			"DEF-ear01.L": "DEF-head", "DEF-ear01.R": "DEF-head",
			"DEF-palm.01.L": "DEF-hand.L", "DEF-palm.02.L": "DEF-hand.L", "DEF-palm.03.L": "DEF-hand.L", "DEF-palm.04.L": "DEF-hand.L",
			"DEF-f_index.01.L": "DEF-hand.L", "DEF-f_middle.01.L": "DEF-hand.L", "DEF-f_ring.01.L": "DEF-hand.L",
			"DEF-f_pinky.01.L": "DEF-hand.L", "DEF-thumb.01.L": "DEF-hand.L",
			"DEF-palm.01.R": "DEF-hand.R", "DEF-palm.02.R": "DEF-hand.R", "DEF-palm.03.R": "DEF-hand.R", "DEF-palm.04.R": "DEF-hand.R",
			"DEF-f_index.01.R": "DEF-hand.R", "DEF-f_middle.01.R": "DEF-hand.R", "DEF-f_ring.01.R": "DEF-hand.R",
			"DEF-f_pinky.01.R": "DEF-hand.R", "DEF-thumb.01.R": "DEF-hand.R",
		},
	},
	"hand": "DEF-hand.R",
	"hide": ["Icosphere"],
}

## TOFU: the red panda on the leash (rig made by tools/blender/rig_tofu.py).
const TOFU := {
	"path": "res://assets/tofu_rigged.glb", "height": 1.1,
	"walk": 1.6, "run": 3.8, "stride": 1.1, "run_stride": 2.0, "radius": 0.25,
	"bones": {
		"pelvis": "hips", "spine": ["spine", "chest"], "neck": "neck", "head": "head",
		"thigh_l": "thigh.L", "shin_l": "shin.L", "foot_l": "foot.L",
		"thigh_r": "thigh.R", "shin_r": "shin.R", "foot_r": "foot.R",
		"upper_arm_l": "upper_arm.L", "forearm_l": "forearm.L",
		"upper_arm_r": "upper_arm.R", "forearm_r": "forearm.R",
		"tail": ["tail1", "tail2", "tail3"],
		"clips": {
			"DEF-hips": "hips", "DEF-spine.001": "spine", "DEF-spine.003": "chest", "DEF-neck": "neck", "DEF-head": "head",
			"DEF-upper_arm.L": "upper_arm.L", "DEF-forearm.L": "forearm.L", "DEF-hand.L": "hand.L",
			"DEF-upper_arm.R": "upper_arm.R", "DEF-forearm.R": "forearm.R", "DEF-hand.R": "hand.R",
			"DEF-thigh.L": "thigh.L", "DEF-shin.L": "shin.L", "DEF-foot.L": "foot.L",
			"DEF-thigh.R": "thigh.R", "DEF-shin.R": "shin.R", "DEF-foot.R": "foot.R",
		},
	},
	# A red leather collar with a brass ring at the front (the leash clips to the ring).
	# Numbers are in the rig's own units (skeleton space of tofu_rigged.glb, Y up, +Z forward),
	# measured from the neck: it is about 0.17 wide around y = 3.26.
	"collar": {"bone": "neck", "center": Vector3(0, 3.28, 0.02), "radius": Vector2(0.2, 0.19),
		"tube": 0.032, "tilt": 0.26, "color": "#c8333f", "ring": "#e2b84f"},
	"hide": [],
}

var data: Dictionary
var world: Node              ## needs resolve(pos, radius) -> Vector3
var velocity := Vector3.ZERO
var speed := 0.0             ## horizontal speed this frame, m/s
var gait := Gait.new()
var body: Node3D             ## turns and leans; holds the scaled model
var skeleton: Skeleton3D
var face_target := Vector3.INF   ## when set, faces this point instead of the motion
var extra_lean := 0.0
var _model: Node3D
var _fit_scale := 1.0


func setup(d: Dictionary) -> void:
	data = d


func _ready() -> void:
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_model = Node3D.new()
	_model.name = "Model"
	body.add_child(_model)
	var scene: Node3D = load(data.path).instantiate()
	_model.add_child(scene)
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.name in data.hide:
			mi.visible = false
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		ap.stop()   # files may carry a broken showcase clip; Gait drives the bones
	var skels := scene.find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] if skels.size() > 0 else null
	_fit(float(data.height))
	if skeleton != null:
		gait.setup(skeleton, data.bones, body)
		gait.stride = data.stride
		gait.run_stride = data.run_stride
		gait._height_hint = float(data.height)
		gait.walk_speed = data.walk
		gait.run_speed = data.run


## Scale to `height` metres by the deform bones (+10% for the head above the top bone),
## feet on y = 0.
func _fit(height: float) -> void:
	var pts := PackedVector3Array()
	if skeleton != null:
		var has_def := false
		for i in skeleton.get_bone_count():
			has_def = has_def or skeleton.get_bone_name(i).begins_with("DEF-")
		for i in skeleton.get_bone_count():
			if has_def and not skeleton.get_bone_name(i).begins_with("DEF-"):
				continue
			pts.append(_model.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin)
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var foot := minf(box.position.y, _feet_y())
	var h := box.end.y - foot
	_fit_scale = height / maxf(h * 1.1, 0.0001)
	_model.scale = Vector3.ONE * _fit_scale
	_model.position = -Vector3(box.get_center().x, foot, box.get_center().z) * _fit_scale


## Lowest foot bone tail is above the sole: take the lowest foot/toe bone.
func _feet_y() -> float:
	var y := INF
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i).to_lower()
		if n.contains("foot") or n.contains("toe"):
			y = minf(y, (_model.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin).y)
	return y


## Builds the collar from data.collar on its bone; returns the ring the leash clips to.
func add_collar() -> Node3D:
	var c: Dictionary = data.collar
	var bone := Gait.find_bone(skeleton, c.bone)
	var ba := BoneAttachment3D.new()
	ba.bone_name = skeleton.get_bone_name(bone)
	skeleton.add_child(ba)
	# Things are made in skeleton space, then expressed relative to the bone at rest.
	var to_bone := skeleton.get_bone_global_rest(bone).affine_inverse()
	var tilt := Basis(Vector3.RIGHT, float(c.tilt))   # + tilt: lower at the front, higher at the back
	var r: Vector2 = c.radius
	var st := PaperMesh.begin()
	PaperMesh.torus(st, Transform3D(tilt.scaled(Vector3(r.x / r.y, 1.0, 1.0)), c.center), r.y, float(c.tube), 18, 6, PaperMesh.col(c.color))
	var front: Vector3 = c.center + tilt * Vector3(0, -0.01, r.y + float(c.tube) * 1.6)
	PaperMesh.torus(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.FORWARD, 0.0), front), float(c.tube) * 1.25, float(c.tube) * 0.35, 10, 4, PaperMesh.col(c.ring))
	var mi := MeshInstance3D.new()
	mi.name = "Collar"
	mi.mesh = PaperMesh.commit(st)
	mi.material_override = PaperMesh.material()
	ba.add_child(mi)
	mi.transform = to_bone
	var clip := Marker3D.new()
	clip.name = "LeashRing"
	ba.add_child(clip)
	clip.transform = to_bone * Transform3D(Basis.IDENTITY, front + Vector3(0, -float(c.tube) * 1.2, float(c.tube) * 0.3))
	return clip


## Node to hang a leash on: a bone of this model, with an offset in metres.
func attach_point(bone_name: String, offset := Vector3.ZERO) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = skeleton.get_bone_name(Gait.find_bone(skeleton, bone_name))
	skeleton.add_child(ba)
	var m := Marker3D.new()
	ba.add_child(m)
	m.global_position = ba.global_position + global_transform.basis * offset
	return m


## Moves toward `desired` velocity (m/s, horizontal) with acceleration `accel`.
func steer(desired: Vector3, delta: float, accel := 12.0) -> void:
	velocity = velocity.move_toward(desired, accel * delta)
	place(position + velocity * delta, delta)


## Puts the character at `p` (on the ground, out of obstacles) and measures its speed.
func place(p: Vector3, delta: float) -> void:
	if world != null:
		p = world.resolve(p, float(data.radius))
	p.y = Terrain.height(p.x, p.z)
	var moved := Vector2(p.x - position.x, p.z - position.z)
	speed = moved.length() / maxf(delta, 0.0001)
	position = p
	var look := Vector2.ZERO
	if face_target != Vector3.INF:
		look = Vector2(face_target.x - p.x, face_target.z - p.z)
	elif speed > 0.15:
		look = moved
	if look.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(look.x, look.y), 1.0 - exp(-10.0 * delta))


func _process(delta: float) -> void:
	if skeleton != null:
		animate(delta, speed)


## Poses the body for this frame at `spd` m/s (also used by the view tools).
func animate(delta: float, spd: float) -> void:
	gait.lean = lerpf(gait.lean, extra_lean, 1.0 - exp(-6.0 * delta))
	var landed := gait.update(delta, spd)
	body.position = gait.body_offset(float(data.height))
	body.rotation.x = lerpf(body.rotation.x, gait.body_lean(), 1.0 - exp(-8.0 * delta))
	if landed != 0:
		footstep.emit(gait.foot_position(landed > 0), float(data.height) / 1.6)
