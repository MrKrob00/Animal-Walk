class_name ClipSource
extends RefCounted
## Real animation clips (Quaternius' Universal Animation Library, CC0) read straight from the
## file: the source skeleton's rest and the clips' bone tracks. Samples and blends local bone
## rotations at any time, without nodes, so each character can play its own phase.

const PATH := "res://assets/anim/ual_standard.glb"

static var _shared: ClipSource

var names: PackedStringArray       ## bone names
var parent: PackedInt32Array       ## parent index, -1 for the root
var order: PackedInt32Array        ## bones with parents first
var rest_local: Array[Transform3D] = []
var rest_global: Array[Transform3D] = []
var clips := {}                    ## name -> Animation
var _tracks := {}                  ## clip name -> {bone: [rotation track, position track]}


static func shared() -> ClipSource:
	if _shared == null:
		_shared = ClipSource.new()
		_shared._load()
	return _shared


func _load() -> void:
	var scene: Node = load(PATH).instantiate()
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
		parent.append(sk.get_bone_parent(i))
		rest_local.append(sk.get_bone_rest(i))
		rest_global.append(sk.get_bone_global_rest(i))
	var done := {}
	while order.size() < names.size():
		for i in names.size():
			if not done.has(i) and (parent[i] < 0 or done.has(parent[i])):
				order.append(i)
				done[i] = true
	for clip in ap.get_animation_list():
		var anim := ap.get_animation(clip)
		clips[clip] = anim
		var map := {}
		for t in anim.get_track_count():
			var bone := names.find(String(anim.track_get_path(t).get_concatenated_subnames()))
			if bone < 0:
				continue
			if not map.has(bone):
				map[bone] = [-1, -1]
			if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				map[bone][0] = t
			elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				map[bone][1] = t
		_tracks[clip] = map
	scene.free()


func bone(bone_name: String) -> int:
	return names.find(bone_name)


## Local rotations and positions of all bones, blended from `mix`: Array of [clip, time, weight].
## Returns [Array[Quaternion], Array[Vector3]].
func sample(mix: Array) -> Array:
	var rot: Array[Quaternion] = []
	var pos: Array[Vector3] = []
	rot.resize(names.size())
	pos.resize(names.size())
	for i in names.size():
		rot[i] = rest_local[i].basis.get_rotation_quaternion()
		pos[i] = rest_local[i].origin
	var acc := 0.0
	for m in mix:
		var w: float = m[2]
		if w <= 0.0001:
			continue
		var anim: Animation = clips[m[0]]
		var t: float = fposmod(m[1], anim.length)
		var share := w / (acc + w)
		var map: Dictionary = _tracks[m[0]]
		for b in map:
			var tr: Array = map[b]
			if tr[0] >= 0:
				var q := anim.rotation_track_interpolate(tr[0], t)
				rot[b] = q if acc == 0.0 else rot[b].slerp(q, share)
			if tr[1] >= 0:
				var p := anim.position_track_interpolate(tr[1], t)
				pos[b] = p if acc == 0.0 else pos[b].lerp(p, share)
		acc += w
	return [rot, pos]


## Global transforms (skeleton space) from local rotations and positions.
func globals(rot: Array[Quaternion], pos: Array[Vector3]) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(names.size())
	for i in order:
		var local := Transform3D(Basis(rot[i]), pos[i])
		g[i] = local if parent[i] < 0 else g[parent[i]] * local
	return g


## How fast the clip walks, metres per second at the source size: the left foot's backward sweep
## while it is on the ground, over the time it stays there.
func ground_speed(clip: String) -> float:
	var anim: Animation = clips[clip]
	var foot := bone("DEF-foot.L")
	var hips := bone("DEF-hips")
	var n := 80
	var ys := []
	var zs := []
	for k in n:
		var s := sample([[clip, anim.length * k / n, 1.0]])
		var g := globals(s[0], s[1])
		ys.append(g[foot].origin.y)
		zs.append(g[foot].origin.z - g[hips].origin.z)
	var low: float = ys.min()
	var stance := []
	for k in n:
		if ys[k] < low + 0.04:
			stance.append(zs[k])
	if stance.size() < 2:
		return 1.0
	var sweep: float = stance.max() - stance.min()
	return sweep / (anim.length * float(stance.size()) / n)


## Where in the clip (0..1) the left foot lands: its most forward point.
func left_contact(clip: String) -> float:
	var anim: Animation = clips[clip]
	var foot := bone("DEF-foot.L")
	var hips := bone("DEF-hips")
	var best := -INF
	var at := 0.0
	for k in 80:
		var s := sample([[clip, anim.length * k / 80.0, 1.0]])
		var g := globals(s[0], s[1])
		var z := g[foot].origin.z - g[hips].origin.z
		if z > best:
			best = z
			at = k / 80.0
	return at
