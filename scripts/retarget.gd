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

## Source bone -> the left / right pair whose line is its side axis: these bones are lined up
## with the source only by turning that line about the vertical (`_yaw_align`).
## (Not the pelvis: a rest that stands on one leg tilts the pelvis and its hip line together.)
const SIDE_PAIR := {
	"DEF-spine.002": ["DEF-upper_arm.L", "DEF-upper_arm.R"], "DEF-spine.003": ["DEF-upper_arm.L", "DEF-upper_arm.R"],
	"DEF-neck": ["DEF-upper_arm.L", "DEF-upper_arm.R"],
}

const LOCOMOTION := ["Walk", "Jog_Fwd", "Sprint"]

## The library's jog throws the torso about like a cartoon (the chest rolls 25 degrees each way and
## twists 35): a character can keep only a share of that swing around the clip's average pose
## ("torso_swing" in its map; the bunny keeps half, at the player's word that she sways oddly).
const TORSO := ["DEF-hips", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003", "DEF-neck", "DEF-head"]

var src: ClipSource
var skel: Skeleton3D
var pairs := []        ## [src bone, dst bone, alignment (char space), dst rest rotation (char space)] parents first
var to_char := Quaternion.IDENTITY   ## dst skeleton space -> character space (rotation only)
var scale := 1.0       ## our hip height / the source's (for the hips' bob)
var leg_scale := 1.0   ## our leg length / the source's (for how far a step goes)
var phase := 0.0       ## 0..1 through the locomotion cycle, 0 = left foot lands
var crawl := 0.0       ## 0..1: how far down into the army crawl (set by Gait)
var crawl_phase := 0.0 ## 0..1 through the crawl cycle
const CRAWL_STRIDE := 0.5   ## metres one crawl cycle moves the clip's own body (tools/make_crawl.gd)
var idle_time := 0.0
var speeds := {}       ## clip -> ground speed at our size, m/s
var _contact := {}     ## clip -> where the left foot lands, 0..1
var _hips_src := -1
var _last := []        ## the source's global pose this frame (for arm directions)
var _hips_rest := Vector3.ZERO
var _calm := {}         ## source bone -> share of the clip's swing kept


## `map`: source bone name -> our bone index. `body` faces +Z.
## `keep`: source bones whose shape at rest is ours, not lined up with the clip's (a rabbit's
## bent leg would be straightened like the clip's man's): the clip's motion goes on top of it.
func setup(skeleton: Skeleton3D, map: Dictionary, body: Node3D, our_hip_height: float, torso_swing := 1.0, keep: Array = []) -> void:
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
		if aim != "" and not map.has(aim) and sname.begins_with("DEF-foot"):
			# A foot with no toe bone of ours (TOFU): it points forward along the ground, as the
			# clip's foot points to its toe; lined up as the shin, its shoe turned up its toes.
			var s_dir := src.rest_global[src.bone(aim)].origin - src.rest_global[i].origin
			a = _frame_align(Vector3.BACK, s_dir.normalized())
		elif aim != "" and map.has(aim):
			var s_dir := src.rest_global[src.bone(aim)].origin - src.rest_global[i].origin
			var d_dir: Vector3 = to_char * (skel.get_bone_global_rest(map[aim]).origin - skel.get_bone_global_rest(d).origin)
			if s_dir.length() > 1e-6 and d_dir.length() > 1e-6:
				var sides := _side_axes(sname, map)
				if keep.has(sname):
					a = Quaternion.IDENTITY
				elif SIDE_PAIR.has(sname):
					a = _yaw_align(sides[0], sides[1])
				else:
					a = _frame_align(d_dir.normalized(), s_dir.normalized(), sides[0], sides[1])
		elif src.parent[i] >= 0 and align.has(src.parent[i]):
			a = align[src.parent[i]]      # an end bone turns like its parent
		align[i] = a
		var d_rest := to_char * skel.get_bone_global_rest(d).basis.orthonormalized().get_rotation_quaternion()
		pairs.append([i, d, a, d_rest])
	leg_scale = sqrt(scale * _leg_length_ratio(map))   # between hip height and leg length: least slide for both
	if torso_swing < 1.0:
		for n in TORSO:
			_calm[src.bone(n)] = torso_swing
	for c in LOCOMOTION:
		speeds[c] = src.ground_speed(c) * leg_scale
		_contact[c] = src.left_contact(c)


## [our side axis, the source's] for a bone (character space): the line between its left / right
## pair where both skeletons have one, else the character's side (X).
func _side_axes(sname: String, map: Dictionary) -> Array:
	var pair: Array = SIDE_PAIR.get(sname, [])
	if pair.is_empty():
		return [Vector3.RIGHT, Vector3.RIGHT]
	var ours := []
	for n in pair:
		var d: int = map.get(n, Gait.find_bone(skel, n))
		if d < 0:
			return [Vector3.RIGHT, Vector3.RIGHT]
		ours.append(skel.get_bone_global_rest(d).origin)
	var d_side: Vector3 = to_char * (ours[0] - ours[1])
	var s_side: Vector3 = src.rest_global[src.bone(pair[0])].origin - src.rest_global[src.bone(pair[1])].origin
	return [d_side.normalized(), s_side.normalized()]


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
	var stand := 1.0 - crawl
	var mix := [["Idle", idle_time, w["Idle"] * stand]]
	for c in LOCOMOTION:
		var len: float = src.clips[c].length
		mix.append([c, fposmod(phase + _contact[c], 1.0) * len, w[c] * stand])
	if crawl > 0.001 and src.clips.has("Crawl_Fwd"):
		crawl_phase = fposmod(crawl_phase + speed * delta / (CRAWL_STRIDE * leg_scale), 1.0)
		var go := smoothstep(0.02, 0.2, speed)
		mix.append(["Crawl_Fwd", crawl_phase * src.clips["Crawl_Fwd"].length, crawl * go])
		mix.append(["Crawl_Idle", idle_time, crawl * (1.0 - go)])
	var s := src.sample(mix, _calm)
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
	if wsum > 0.001 and crawl < 0.5:   # no footprints while crawling
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


## Turns our bone onto the source's: its direction onto theirs, and also the body's side axis
## onto theirs (both characters face +Z with the side along X). Lining up the direction alone
## leaves the bone twisted about itself, and a twisted chest rolls the shoulders to one side.
## For the upper spine: only turn our shoulder line onto the source's about the vertical. The
## lean of our chest stays as the model has it: Chobby's chest bone leans 30 degrees back in her
## rest while her ribcage is upright, and lining the bone up with the clip's tipped her chest
## forward ~45 degrees (the player: her chest hung).
static func _yaw_align(d_side: Vector3, s_side: Vector3) -> Quaternion:
	var a := Vector2(d_side.x, d_side.z)
	var b := Vector2(s_side.x, s_side.z)
	if a.length() < 1e-4 or b.length() < 1e-4:
		return Quaternion.IDENTITY
	return Quaternion(Vector3.UP, -a.angle_to(b))


static func _frame_align(d_dir: Vector3, s_dir: Vector3, d_ref := Vector3.RIGHT, s_ref := Vector3.RIGHT, side_first := false) -> Quaternion:
	if absf(d_dir.dot(d_ref)) > 0.8 or absf(s_dir.dot(s_ref)) > 0.8:
		d_ref = Vector3.BACK       # a bone along the side (an arm in a T-pose): use forward instead
		s_ref = Vector3.BACK
	if side_first:
		# The side line is exact (level shoulders stay level), the bone's direction is the nearest.
		d_dir = (d_dir - d_ref * d_ref.dot(d_dir)).normalized()
		s_dir = (s_dir - s_ref * s_ref.dot(s_dir)).normalized()
	var d_side := (d_ref - d_dir * d_ref.dot(d_dir)).normalized()
	var s_side := (s_ref - s_dir * s_ref.dot(s_dir)).normalized()
	var d_basis := Basis(d_side, d_dir, d_side.cross(d_dir).normalized())
	var s_basis := Basis(s_side, s_dir, s_side.cross(s_dir).normalized())
	return (s_basis * d_basis.inverse()).get_rotation_quaternion()


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Quaternion(c.normalized(), atan2(c.length(), d))
