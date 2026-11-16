class_name Actor
extends Node3D
## A character from a model file: scaled to a height, stood on the terrain,
## walked by `steer`, animated by Gait. Faces +Z.

signal footstep(pos: Vector3, size: float)

## Chobby Bun: the hero (rigify deform bones from the Sketchfab file).
const BUNNY := {
	"path": "res://assets/free_download_-_chobby_bun.glb", "height": 1.6,
	"walk": 1.5, "run": 3.4, "stride": 1.15, "radius": 0.3,
	"bones": {
		"thigh_l": "DEF-thigh.L", "shin_l": "DEF-shin.L", "foot_l": "DEF-foot.L",
		"thigh_r": "DEF-thigh.R", "shin_r": "DEF-shin.R", "foot_r": "DEF-foot.R",
		"upper_arm_l": "DEF-upper_arm.L", "forearm_l": "DEF-forearm.L",
		"upper_arm_r": "DEF-upper_arm.R", "forearm_r": "DEF-forearm.R",
		"hand_l": "DEF-hand.L", "hand_r": "DEF-hand.R",
		"ears": ["DEF-ear01.L", "DEF-ear01.R"],
		"arms_down": true,
	},
	"hand": "DEF-hand.R",
	"hide": ["Icosphere"],
}

## TOFU: the red panda on the leash (rig made by tools/blender/rig_tofu.py).
const TOFU := {
	"path": "res://assets/tofu_rigged.glb", "height": 1.1,
	"walk": 1.6, "run": 3.8, "stride": 0.85, "radius": 0.25,
	"bones": {
		"thigh_l": "thigh.L", "shin_l": "shin.L", "foot_l": "foot.L",
		"thigh_r": "thigh.R", "shin_r": "shin.R", "foot_r": "foot.R",
		"upper_arm_l": "upper_arm.L", "forearm_l": "forearm.L",
		"upper_arm_r": "upper_arm.R", "forearm_r": "forearm.R",
		"tail": ["tail1", "tail2", "tail3"],
	},
	"collar": "chest",
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
	if skeleton == null:
		return
	gait.lean = extra_lean
	var landed := gait.update(delta, speed)
	body.position.y = gait.bob(speed) * float(data.height)
	body.rotation.x = lerpf(body.rotation.x, gait.body_lean(speed), 1.0 - exp(-8.0 * delta))
	if landed != 0:
		footstep.emit(gait.foot_position(landed > 0), float(data.height) / 1.6)
