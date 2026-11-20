class_name Retarget
extends RefCounted
## Puts the source clips' motion on one of our skeletons. For each mapped bone the clip's
## rotation away from its own rest (in character space) is applied on top of our bone's rest,
## after our rest is turned to point the same way as the source's (so a V-sign or A-pose rest
## does not matter). The hips' movement (bob and sway) comes back as a body offset, scaled to
## our size. Clips are blended walk / jog / sprint by speed and timed by the distance walked.

## Source bone -> the source bone it points at (for lining the rests up).
const AIM := {
	"DEF-hips": "DEF-spine.001", "DEF-spine.001": "DEF-spine.002", "DEF-spine.002": "DEF-spine.003",
	"DEF-spine.003": "DEF-neck", "DEF-neck": "DEF-head",
	"DEF-shoulder.L": "DEF-upper_arm.L", "DEF-upper_arm.L": "DEF-forearm.L", "DEF-forearm.L": "DEF-hand.L", "DEF-hand.L": "DEF-f_middle.01.L",
	"DEF-shoulder.R": "DEF-upper_arm.R", "DEF-upper_arm.R": "DEF-forearm.R", "DEF-forearm.R": "DEF-hand.R", "DEF-hand.R": "DEF-f_middle.01.R",
	"DEF-thigh.L": "DEF-shin.L", "DEF-shin.L": "DEF-foot.L", "DEF-foot.L": "DEF-toe.L",
	"DEF-thigh.R": "DEF-shin.R", "DEF-shin.R": "DEF-foot.R", "DEF-foot.R": "DEF-toe.R",
}

const LOCOMOTION := ["Walk", "Jog_Fwd", "Sprint"]

var src: ClipSource
var skel: Skeleton3D
var pairs := []        ## [src bone, dst bone, alignment (char space), dst rest rotation (char space)] parents first
var to_char := Quaternion.IDENTITY   ## dst skeleton space -> character space (rotation only)
var scale := 1.0       ## our hip height / the source's (for the hips' bob)
var leg_scale := 1.0   ## our leg length / the source's (for how far a step goes)
var phase := 0.0       ## 0..1 through the locomotion cycle, 0 = left foot lands
var idle_time := 0.0
var speeds := {}       ## clip -> ground speed at our size, m/s
var _contact := {}     ## clip -> where the left foot lands, 0..1
var _hips_src := -1
var _last := []        ## the source's global pose this frame (for arm directions)
var _hips_rest := Vector3.ZERO


## `map`: source bone name -> our bone index. `body` faces +Z.
func setup(skeleton: Skeleton3D, map: Dictionary, body: Node3D, our_hip_height: float) -> void:
	src = ClipSource.shared()
	skel = skeleton
	var rel := (body.global_transform.basis.inverse() * skel.global_transform.basis).orthonormalized()
	to_char = rel.get_rotation_quaternion()
	_hips_src = src.bone("DEF-hips")
	_hips_rest = src.rest_global[_hips_src].origin
	scale = our_hip_height / maxf(_hips_rest.y, 0.01)
	var align := {}
	for i in src.order:
		var sname := src.names[i]
		if not map.has(sname):
			continue
		var d: int = map[sname]
		var a := Quaternion.IDENTITY
		var aim: String = AIM.get(sname, "")
		if aim != "" and map.has(aim):
			var s_dir := src.rest_global[src.bone(aim)].origin - src.rest_global[i].origin
			var d_dir: Vector3 = to_char * (skel.get_bone_global_rest(map[aim]).origin - skel.get_bone_global_rest(d).origin)
			if s_dir.length() > 1e-6 and d_dir.length() > 1e-6:
				a = Quaternion(_arc(d_dir.normalized(), s_dir.normalized()))
		elif src.parent[i] >= 0 and align.has(src.parent[i]):
			a = align[src.parent[i]]      # an end bone turns like its parent
		align[i] = a
		var d_rest := to_char * skel.get_bone_global_rest(d).basis.orthonormalized().get_rotation_quaternion()
		pairs.append([i, d, a, d_rest])
	leg_scale = sqrt(scale * _leg_length_ratio(map))   # between hip height and leg length: least slide for both
	for c in LOCOMOTION:
		speeds[c] = src.ground_speed(c) * leg_scale
		_contact[c] = src.left_contact(c)


## Thigh + shin of ours over the source's, in metres (falls back to the hip height ratio).
func _leg_length_ratio(map: Dictionary) -> float:
	var chain := ["DEF-thigh.L", "DEF-shin.L", "DEF-foot.L"]
	for n in chain:
		if not map.has(n):
			return scale
	var s_len := 0.0
	var d_len := 0.0
	var to_world := skel.global_transform
	for k in 2:
		s_len += (src.rest_global[src.bone(chain[k + 1])].origin - src.rest_global[src.bone(chain[k])].origin).length()
		d_len += ((to_world * skel.get_bone_global_rest(map[chain[k + 1]]).origin) - (to_world * skel.get_bone_global_rest(map[chain[k]]).origin)).length()
	return d_len / maxf(s_len, 0.001)


## Clip weights for a speed: idle when standing, then walk, jog, sprint.
func weights(speed: float) -> Dictionary:
	var w := {"Idle": 0.0, "Walk": 0.0, "Jog_Fwd": 0.0, "Sprint": 0.0}
	var vw: float = speeds["Walk"]
	var vj: float = speeds["Jog_Fwd"]
	var vs: float = speeds["Sprint"]
	var move := smoothstep(0.05, vw * 0.45, speed)
	w["Idle"] = 1.0 - move
	if speed <= vw:
		w["Walk"] = move
	elif speed <= vj:
		var t := smoothstep(vw, vj, speed)
		w["Walk"] = move * (1.0 - t)
		w["Jog_Fwd"] = move * t
	else:
		var t := smoothstep(vj, vs, speed)
		w["Jog_Fwd"] = move * (1.0 - t)
		w["Sprint"] = move * t
	return w


## Advances the clips by `delta` at `speed` and poses our bones. Returns the body offset
## (character space, metres) and whether a foot landed: [Vector3, int].
func apply(delta: float, speed: float) -> Array:
	var w := weights(speed)
	# One cycle covers this many metres (the blend of the clips' own cycles).
	var cycle := 0.0
	var wsum := 0.0
	for c in LOCOMOTION:
		cycle += w[c] * speeds[c] * src.clips[c].length
		wsum += w[c]
	var before := phase
	if wsum > 0.001:
		phase = fposmod(phase + speed * delta / (cycle / wsum), 1.0)
	idle_time += delta
	var mix := [["Idle", idle_time, w["Idle"]]]
	for c in LOCOMOTION:
		var len: float = src.clips[c].length
		mix.append([c, fposmod(phase + _contact[c], 1.0) * len, w[c]])
	var s := src.sample(mix)
	var g := src.globals(s[0], s[1])
	_last = g
	var done := {}
	for p in pairs:
		var i: int = p[0]
		var d: int = p[1]
		var delta_rot := g[i].basis.get_rotation_quaternion() * src.rest_global[i].basis.get_rotation_quaternion().inverse()
		var want_char: Quaternion = delta_rot * p[2] * p[3]
		var want := to_char.inverse() * want_char
		var par := skel.get_bone_parent(d)
		var par_rot: Quaternion
		if done.has(par):
			par_rot = done[par]
		elif par >= 0:
			par_rot = skel.get_bone_global_pose(par).basis.orthonormalized().get_rotation_quaternion()
		else:
			par_rot = Quaternion.IDENTITY
		skel.set_bone_pose_rotation(d, (par_rot.inverse() * want).normalized())
		done[d] = want
	var hips_off := (g[_hips_src].origin - _hips_rest) * scale
	var landed := 0
	if wsum > 0.001:
		if before > phase:
			landed = 1          # wrapped: the left foot lands
		elif before < 0.5 and phase >= 0.5:
			landed = -1         # the right foot lands
	return [hips_off, landed]


## The clip's upper arm and forearm directions this frame (character space): [upper, fore].
## `side` is "L" or "R".
func arm_dirs(side: String) -> Array:
	if _last.is_empty():
		return []
	var sh: Vector3 = _last[src.bone("DEF-upper_arm." + side)].origin
	var el: Vector3 = _last[src.bone("DEF-forearm." + side)].origin
	var wr: Vector3 = _last[src.bone("DEF-hand." + side)].origin
	return [(el - sh).normalized(), (wr - el).normalized()]


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Quaternion(c.normalized(), atan2(c.length(), d))
