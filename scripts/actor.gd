class_name Actor
extends Node3D
## A character from a model file: scaled to a height, stood on the terrain,
## walked by `steer`, animated by Gait. Faces +Z.

signal footstep(pos: Vector3, size: float)

## Chobby Bun: the hero (rigify deform bones from the Sketchfab file).
## Her deform bones hang from rigify's helper bones, which nothing moves here, so the legs,
## arms, head, chest and fingers are re-hung under the spine and the hands ("reparent").
const BUNNY := {
	# Her T-posed model with a clean skeleton (tools/tpose_bunny.gd makes it from the Sketchfab file).
	"path": "res://assets/chobby_tpose.glb", "height": 1.6, "sole": 0.032,
	"jump": "hop",   # the jump button: a hare's hop (Gait.JUMP)
	"sit": "w",   # the sit button: her "frog" W-sit (the player chose it; Gait.SIT)
	"soft_press": true,   # lying down, her chest, belly and thighs give against the ground (per vertex)
	# Her hair gets bones at load (HairRig: a short chain per strand on spring bones) and slides
	# round these spheres: [bone, offset in metres, radius in metres].
	"hair": {"mesh": "Object_11", "head": "DEF-head", "spheres": [
		["DEF-head", Vector3(0, 0.11, 0.0), 0.085], ["DEF-head", Vector3(0, 0.06, 0.06), 0.07], ["DEF-neck", Vector3(0, 0.04, 0), 0.05],
		["DEF-upper_arm.L", Vector3.ZERO, 0.06], ["DEF-upper_arm.R", Vector3.ZERO, 0.06],
		["DEF-spine.003", Vector3(0, 0.06, -0.03), 0.10]]},
	"flesh": ["Object_11", "Object_672"],   # her butt, thighs and belly are soft and springy (SoftFlesh; the player asked): skin and shorts
	"eye": Vector3(0, 0.10, 0.125),   # first person: from her head bone (measured on her face)
	"walk": 1.5, "run": 3.4, "stride": 1.45, "run_stride": 2.5, "radius": 0.3,
	# Her top and shorts take the skin's bone weights, so no gap opens when the chest moves.
	# The leash lies over these instead of passing through: [from bone, to bone, radius m, reach past "to" m].
	"capsules": [["DEF-spine", "DEF-spine.003", 0.14, 0.05], ["DEF-thigh.L", "DEF-thigh.R", 0.07, 0.0]],
	# TOFU's paw stops against these (PawReach): [from bone, to bone, radius m, metres up, soft,
	# flesh region (SoftFlesh: 0 her left butt and thigh, 1 right, 2 belly; -1 none)].
	# Radii about the skin's middle round each bone (measured; at the 90th percentile the paw
	# stopped short, the player said: her skin is pushed out of the paw where it is wider); soft parts let the paw
	# sink in a little, the skin gives (SoftPress) and they wobble (Gait.soft_poke, flesh_push).
	"touch": [
		["DEF-spine", "DEF-spine.002", 0.118, 0.0, true, 2], ["DEF-spine.002", "DEF-spine.003", 0.118, 0.0, false],
		["DEF-spine.003", "DEF-neck", 0.095, 0.0, false],
		["DEF-head", "DEF-head", 0.125, 0.08, false], ["DEF-thigh.L", "DEF-spine", 0.115, 0.0, true, 0], ["DEF-thigh.R", "DEF-spine", 0.115, 0.0, true, 1],
		["DEF-thigh.L", "DEF-shin.L", 0.10, 0.0, true, 0], ["DEF-thigh.R", "DEF-shin.R", 0.10, 0.0, true, 1],
		["DEF-shin.L", "DEF-foot.L", 0.06, 0.0, false], ["DEF-shin.R", "DEF-foot.R", 0.06, 0.0, false],
		["DEF-upper_arm.L", "DEF-forearm.L", 0.045, 0.0, false], ["DEF-upper_arm.R", "DEF-forearm.R", 0.045, 0.0, false],
		["DEF-forearm.L", "DEF-hand.L", 0.042, 0.0, false], ["DEF-forearm.R", "DEF-hand.R", 0.042, 0.0, false],
		["DEF-breast04.L", "DEF-breast04.L", 0.065, 0.0, true], ["DEF-breast04.R", "DEF-breast04.R", 0.065, 0.0, true],
	],
	"cloth": {"body": "Object_11", "items": ["Object_670", "Object_672"],
		"skip": ["DEF-upper_arm", "DEF-forearm", "DEF-hand", "DEF-f_", "DEF-thumb", "DEF-palm"], "lift": 0.0},   # lifted off the skin when baked
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
		"clip_arms": true, "torso_swing": 0.5, "feminine": 1.0, "crawl_lift": 0.03,
		# Her legs keep their rabbit shape (knee forward, heel up); the clips move them from there.
		"clip_keep": ["DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-toe.L", "DEF-thigh.R", "DEF-shin.R", "DEF-foot.R", "DEF-toe.R"],   # arms aimed like the clip's from arms-down (her V-sign rest wrings copied arms); half the clips' torso swing
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
	"jump": "surprise",   # the jump button: a red panda's "surprise!" leap (Gait.JUMP; no turn, the player)
	"sit": "dog",   # the sit button: sitting like a dog (the player chose it; Gait.SIT)
	"eye": Vector3(0, 0.09, 0.03),   # first person: from its head bone (back from its long snout, so the collar shows below)
	"walk": 1.6, "run": 3.8, "stride": 1.1, "run_stride": 2.0, "radius": 0.25,
	"bones": {
		"pelvis": "hips", "spine": ["spine", "chest"], "neck": "neck", "head": "head",
		"thigh_l": "thigh.L", "shin_l": "shin.L", "foot_l": "foot.L",
		"thigh_r": "thigh.R", "shin_r": "shin.R", "foot_r": "foot.R",
		"upper_arm_l": "upper_arm.L", "forearm_l": "forearm.L",
		"upper_arm_r": "upper_arm.R", "forearm_r": "forearm.R",
		"hand_l": "hand.L", "hand_r": "hand.R",
		"paw_fingers_l": "fingers.L", "paw_thumb_l": "thumb.L", "paw_fingers_r": "fingers.R", "paw_thumb_r": "thumb.R",
		"tail": ["tail1", "tail2", "tail3"],
		"crawl_lift": 0.09, "crawl_thick": 1.9,   # lying down, its thick body, big paws and sleeves would sink
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
	# The leash lies over these instead of passing through: [from bone, to bone, radius m, reach past "to" m].
	"capsules": [["hips", "chest", 0.16, 0.0], ["tail1", "tail3", 0.12, 0.3]],
	# The right paw on the second stick (PawReach): its palm, half as thick as "r", its middle "off"
	# past the wrist; skin it presses is pushed out of a ball of radius "ball" (measured on the mesh:
	# the paw is about 5 cm thick, 12 wide, 14 long).
	"paw": {"r": 0.028, "off": 0.065, "ball": 0.055},
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
var _press := []             ## soft-skin materials (SoftPress), when the character has them
var hair: HairSprings   ## her hair's spring chains (HairRig), when she has them
var _flesh_regions := []      ## SoftFlesh regions (her soft butt, thighs and belly), when she has them
var paw_touch := Vector4.ZERO   ## another's paw pressing this skin: centre (world) and radius (0: none)
var head_hidden := false     ## first person: the head (and all it carries) shrunk away
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
	if data.has("cloth"):
		var skin_mi: MeshInstance3D = scene.find_child(data.cloth.body, true, false)
		for n in data.cloth.items:
			var c: MeshInstance3D = scene.find_child(n, true, false)
			if skin_mi != null and c != null:
				SkinFit.follow_body(skin_mi, c, data.cloth.get("skip", []), float(data.cloth.get("lift", SkinFit.INFLATE)))
	var skels0 := scene.find_children("*", "Skeleton3D", true, false)
	if data.has("flesh") and skels0.size() > 0:
		var sk0: Skeleton3D = skels0[0]
		var rel := body.global_transform.basis.inverse() * sk0.global_transform.basis
		_flesh_regions = SoftFlesh.apply(scene, sk0, (rel.inverse() * Vector3.BACK).normalized(), (rel.inverse() * Vector3.RIGHT).normalized(), data.flesh)
	if data.get("soft_press", false):
		_press = SoftPress.apply(scene)   # soft skin against the ground, lying down
	var skels := scene.find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] if skels.size() > 0 else null
	_fit(float(data.height))
	if skeleton != null:
		gait.setup(skeleton, data.bones, body)
		gait.stride = data.stride
		gait.run_stride = data.run_stride
		gait._height_hint = float(data.height)
		gait.sit_style = String(data.get("sit", ""))
		gait.jump_style = String(data.get("jump", ""))
		if gait.rt != null:
			gait.rt.height = float(data.height)
		gait.walk_speed = data.walk
		gait.run_speed = data.run
		if not _flesh_regions.is_empty():
			gait.set_flesh(_flesh_regions)
		if data.has("hair"):
			hair = HairRig.build(self, skeleton, data.hair)


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
	_model.position.y += float(data.get("sole", 0.0))   # the paw's skin below its lowest bone


## Lowest foot bone tail is above the sole: take the lowest foot/toe bone.
func _feet_y() -> float:
	var y := INF
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i).to_lower()
		if n.contains("foot") or n.contains("toe"):
			y = minf(y, (_model.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin).y)
	return y


const HEAD_TUCK := 0.12   ## share of the height below the neck a hidden head is put away
var _eye := Vector3.INF


## Where the eyes are (world): `data.eye` (metres, character space: up, forward) from the head
## bone, turned as the head is turned (as of the last `animate`, before a hidden head is put away).
func eye_position() -> Vector3:
	return _eye if _eye != Vector3.INF else _eye_now()


func _eye_now() -> Vector3:
	var hb := Gait.find_bone(skeleton, data.bones.head)
	if hb < 0:
		return global_position + Vector3(0, float(data.height) * 0.9, 0)
	var now := (skeleton.global_transform.basis * skeleton.get_bone_global_pose(hb).basis).orthonormalized()
	var rest := (skeleton.global_transform.basis * skeleton.get_bone_global_rest(hb).basis).orthonormalized()
	var turn := now * rest.inverse()
	var off: Vector3 = data.get("eye", Vector3(0, 0.1, 0.1))
	return skeleton.global_transform * skeleton.get_bone_global_pose(hb).origin + turn * (body.global_basis.orthonormalized() * off)


## Builds the collar from data.collar on its bone; returns the ring the leash clips to.
## The ring slides round the collar toward the leash (`aim_collar`), as a real one does.
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
	var mi := MeshInstance3D.new()
	mi.name = "Collar"
	mi.mesh = PaperMesh.commit(st)
	mi.material_override = PaperMesh.material()
	ba.add_child(mi)
	mi.transform = to_bone
	# The ring, made at its own origin, standing across the collar.
	var rs := PaperMesh.begin()
	PaperMesh.torus(rs, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), float(c.tube) * 1.25, float(c.tube) * 0.35, 10, 4, PaperMesh.col(c.ring))
	_ring = MeshInstance3D.new()
	_ring.name = "CollarRing"
	_ring.mesh = PaperMesh.commit(rs)
	_ring.material_override = PaperMesh.material()
	ba.add_child(_ring)
	var clip := Marker3D.new()
	clip.name = "LeashRing"
	_ring.add_child(clip)
	clip.position = Vector3(0, -float(c.tube) * 1.2, float(c.tube) * 0.3)
	_collar_frame = to_bone * Transform3D(tilt, c.center)
	_ring_angle = 0.0
	_place_ring()
	return clip


var _ring: MeshInstance3D
var _collar_frame := Transform3D.IDENTITY   ## collar space (centre, tilted) -> bone attachment space
var _ring_angle := 0.0                       ## round the collar from the front, + toward its left (+X)

const RING_SLIDE := 6.0   ## how fast the ring slides round toward the leash (1/s)


## Slides the collar's ring round toward `target` (world), e.g. the leash a little way along.
func aim_collar(target: Vector3, delta: float) -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	var to_collar: Transform3D = (_ring.get_parent() as Node3D).global_transform * _collar_frame
	var q := to_collar.affine_inverse() * target
	if Vector2(q.x, q.z).length() < 0.05:
		return   # straight below or above the collar: no side to turn to
	var want := atan2(q.x, q.z)
	_ring_angle += wrapf(want - _ring_angle, -PI, PI) * (1.0 - exp(-RING_SLIDE * delta))
	_place_ring()


func _place_ring() -> void:
	var c: Dictionary = data.collar
	var r: Vector2 = c.radius
	var out := float(c.tube) * 1.6
	var t := _ring_angle
	var pos := Vector3(sin(t) * (r.x + out), -0.01, cos(t) * (r.y + out))
	_ring.transform = _collar_frame * Transform3D(Basis(Vector3.UP, t), pos)


## The body's capsules in world space for the leash to lie over: [a, b, radius].
func capsules() -> Array:
	var out := []
	for c in data.get("capsules", []):
		var a := Gait.find_bone(skeleton, c[0])
		var b := Gait.find_bone(skeleton, c[1])
		if a < 0 or b < 0:
			continue
		var pa: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(a).origin
		var pb: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(b).origin
		pb += (pb - pa).normalized() * float(c[3])
		out.append([pa, pb, float(c[2])])
	return out


## The body's shapes in world space for TOFU's paw to stop against: [a, b, radius, soft].
func touch_shapes() -> Array:
	var out := []
	for c in data.get("touch", []):
		var a := Gait.find_bone(skeleton, c[0])
		var b := Gait.find_bone(skeleton, c[1])
		if a < 0 or b < 0:
			continue
		var up := Vector3.UP * float(c[3])
		out.append([skeleton.global_transform * skeleton.get_bone_global_pose(a).origin + up,
			skeleton.global_transform * skeleton.get_bone_global_pose(b).origin + up, float(c[2]), bool(c[4]), int(c[5]) if c.size() > 5 else -1])
	return out


## The paw's centre (world) and how far it is out (0 = hanging, 1 = reaching): see Gait.paw_target.
func paw_center() -> Vector3:
	var paw: Dictionary = data.get("paw", {})
	var h := Gait.find_bone(skeleton, data.bones.get("hand_r", ""))
	if paw.is_empty() or h < 0:
		return Vector3.INF
	var g := skeleton.get_bone_global_pose(h)
	var wr: Vector3 = skeleton.global_transform * g.origin
	return wr + (skeleton.global_transform.basis * g.basis.y).normalized() * float(paw.off)   # along the hand


func ring_angle() -> float:
	return _ring_angle


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
	_tick_from = position
	position = p
	var look := Vector2.ZERO
	if face_target != Vector3.INF:
		look = Vector2(face_target.x - p.x, face_target.z - p.z)
	elif speed > 0.15:
		look = moved
	if look.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(look.x, look.y), 1.0 - exp(-10.0 * delta))


var _tick_from := Vector3.INF   ## where the last physics tick moved it from


func _process(delta: float) -> void:
	# The springs (chest, soft flesh) feel the body's motion smoothly between physics ticks: with
	# more frames than ticks (a 90-120 Hz screen) it moves in steps, which hit them like blows
	# (the flesh hung at its limit). They get where it would be, eased between the ticks.
	if _tick_from != Vector3.INF:
		var frac := Engine.get_physics_interpolation_fraction()
		gait.motion_fix = (_tick_from - position) * (1.0 - frac)
	if skeleton != null:
		animate(delta, speed)


## Poses the body for this frame at `spd` m/s (also used by the view tools).
func animate(delta: float, spd: float) -> void:
	gait.lean = lerpf(gait.lean, extra_lean, 1.0 - exp(-6.0 * delta))
	gait._on_island = world != null
	var landed := gait.update(delta, spd)
	body.position = gait.body_offset(float(data.height))
	if skeleton != null:
		var hb := Gait.find_bone(skeleton, data.bones.head)
		if hb >= 0:
			skeleton.set_bone_pose_position(hb, skeleton.get_bone_rest(hb).origin)
			skeleton.set_bone_pose_scale(hb, Vector3.ONE)
			_eye = _eye_now()   # where the eyes are, before the head is put away
			if head_hidden:
				# Shrunk to a point inside the chest, below the neck: the skin between neck and
				# head goes in with it, so nothing of the head is left in front of the eyes.
				var par := skeleton.get_bone_parent(hb)
				var neck_w := skeleton.global_transform * skeleton.get_bone_global_pose(par if par >= 0 else hb).origin
				var into := skeleton.global_transform.affine_inverse() * (neck_w - Vector3.UP * HEAD_TUCK * float(data.height))
				var par_pose := skeleton.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
				skeleton.set_bone_pose_position(hb, par_pose.affine_inverse() * into)
				skeleton.set_bone_pose_scale(hb, Vector3.ONE * 0.001)
	if hair != null:
		if head_hidden:
			hair.reset()   # first person: the head (and its hair) is put away
		else:
			hair.step(delta, gait.motion_fix, body.global_position + global_basis * (gait.body_offset(float(data.height)) - body.position))   # the body as it will be this frame (bob, crouch, jump)
	if not _press.is_empty():
		var k := smoothstep(0.0, 1.0, gait.crawl)
		for m in _press:
			m.set_shader_parameter("floor_p", global_position)
			m.set_shader_parameter("floor_n", Terrain.normal(global_position.x, global_position.z) if world != null else Vector3.UP)
			m.set_shader_parameter("press", maxf(k, smoothstep(0.0, 1.0, gait.sit)))   # sitting, her butt and thighs give against the ground too
			m.set_shader_parameter("paw", paw_touch)
			if not _flesh_regions.is_empty():
				m.set_shader_parameter("flesh_on", 1.0)
				m.set_shader_parameter("flesh_l", gait.flesh_offset[0])
				m.set_shader_parameter("flesh_r", gait.flesh_offset[1])
				m.set_shader_parameter("flesh_b", gait.flesh_offset[2])
	body.rotation.x = lerpf(body.rotation.x, gait.body_lean(), 1.0 - exp(-8.0 * delta))
	body.rotation.y = gait.jump_spin()   # a turn in the air, for a jump that has one
	if landed != 0:
		if landed == 2:   # landing a jump: both feet, and a bigger puff
			footstep.emit(gait.foot_position(true), float(data.height) / 1.6 * 1.4)
			footstep.emit(gait.foot_position(false), float(data.height) / 1.6 * 1.4)
		else:
			footstep.emit(gait.foot_position(landed > 0), float(data.height) / 1.6)
