class_name Gait
extends RefCounted
## Walk, run and idle without baked clips: poses the bones of a humanoid skeleton every frame.
## The step follows the real (smoothed) speed, so feet do not slide. The pelvis sways and twists,
## the chest twists back, the head keeps level and looks around, ears and tail hang on springs.
## Rotations are about the character's own axes (side +X, up +Y, forward +Z), converted once into
## each bone's frame, so bone roll and file axes do not matter.

var skeleton: Skeleton3D
var stride := 1.0          ## metres covered by one walking cycle (two steps)
var run_stride := 2.0      ## metres covered by one running cycle (longer strides, calmer cadence)
var walk_speed := 1.5      ## m/s at which the walk is at full swing
var run_speed := 3.5       ## m/s at which the run is at full swing
var phase := 0.0
var lean := 0.0            ## extra whole-body lean, radians: + forward, - back (being dragged)
var look_target := Vector3.INF   ## world point the head turns to (Vector3.INF: look around)
var hold_target := Vector3.INF   ## world point the right hand reaches to (the leash), or INF
var hold_pull := 0.0       ## 0..1: how hard the leash pulls the hand
var speed := 0.0           ## smoothed speed used for the pose, m/s
var dragged := false       ## set by the game: the leash is taut and pulls this character
var fatigue := 0.0         ## 0..1: builds while dragged at a run, goes when the pace is easy

var _b := {}               ## role -> bone index, or Array of indices
var _q := {}               ## bone -> base rotation (rest, with any base pose folded in)
var _ax := {}              ## bone -> [side, up, forward] axes in the bone's own frame
var _time := 0.0
var _last_sign := 0
var _yaw_prev := 0.0
var _turn := 0.0           ## smoothed turning rate, rad/s
var _hold := 0.0           ## smoothed 0..1: the hand is on the leash
var _pull := 0.0           ## smoothed hold_pull
var _hold_point := Vector3.ZERO
var _tires := false        ## only characters with "tires" in their map get tired
var _stumble := -1.0       ## time into a stumble, or < 0
var _stumble_side := 1.0
var _stumble_wait := 2.0
var _winded := 0.0         ## 0..1: bent over, hand on the knee, catching breath
var _breath_ph := 0.0
var _grip := []            ## right-hand finger bones: [bone, curl axis in the bone frame]
var _ik_x := Vector3.ZERO  ## smoothed wrist goal, relative to the shoulder (skeleton space)
var _ik_v := Vector3.ZERO
var _ik_ready := false
var _hammer := -1.0        ## time into the hammering, or < 0
var _ears := []            ## springs: [pitch, yaw] per ear
var _tail := []            ## springs per tail bone
var _soft := []            ## soft parts: [root bone, tip bone, mass pos, mass vel, ready, last anchor]
var _look := Spring.new()
var _twitch := 2.0
var _rng := RandomNumberGenerator.new()
var _side_sk := Vector3.RIGHT
var _up_sk := Vector3.UP
var _fwd_sk := Vector3.BACK
var _body: Node3D
var rt: Retarget            ## real clips, when the map has "clips"; else the old procedural walk
var _offset := Vector3.ZERO ## body offset from the clips' hips (metres, character space)
var _clip_arms := false     ## arms aimed like the clip's, from a natural arms-down pose

const HAMMER_TIME := 0.62
const TIRE_TIME := 4.0      ## seconds of being dragged at a run until fully worn out
const REST_TIME := 4.5      ## seconds of easy pace or standing to recover fully
const STUMBLE_TIME := 0.42


## A damped spring: soft follow-through for ears, tail and the head.
class Spring:
	var x := 0.0
	var v := 0.0
	func step(target: float, dt: float, freq := 10.0, damp := 0.3, push := 0.0) -> float:
		var w := TAU * freq / 6.0
		v += (w * w * (target - x) - 2.0 * damp * w * v + push) * dt
		x += v * dt
		return x


## `map`: role -> bone name or Array of names; options "arms_down", "reparent", "fingers".
## `body` is the node that faces the character's forward (+Z).
func setup(skel: Skeleton3D, map: Dictionary, body: Node3D) -> void:
	skeleton = skel
	_body = body
	_rng.seed = hash(skel.get_path())
	var rel := body.global_transform.basis.inverse() * skel.global_transform.basis
	_side_sk = (rel.inverse() * Vector3.RIGHT).normalized()
	_up_sk = (rel.inverse() * Vector3.UP).normalized()
	_fwd_sk = (rel.inverse() * Vector3.BACK).normalized()
	for child in map.get("reparent", {}):
		reparent_bone(skel, child, map.reparent[child])
	for role in map:
		if role == "soft" or not (map[role] is Array or map[role] is String):
			continue
		var names: Array = map[role] if map[role] is Array else [map[role]]
		var ids := []
		for n in names:
			var b := find_bone(skel, n)
			if b < 0:
				push_warning("Gait: no bone %s" % n)
				continue
			ids.append(b)
			_frame(b)
		_b[role] = ids if map[role] is Array else (ids[0] if ids.size() > 0 else -1)
	for e in _ids("ears"):
		_ears.append([Spring.new(), Spring.new()])
	for t in _ids("tail"):
		_tail.append(Spring.new())
	for pair in map.get("soft", []):
		var root := find_bone(skel, pair[0])
		var tip := find_bone(skel, pair[1])
		if root >= 0 and tip >= 0:
			_q[root] = skel.get_bone_rest(root).basis.get_rotation_quaternion()
			_soft.append([root, tip, Vector3.ZERO, Vector3.ZERO, false, Vector3.ZERO])
	_tires = map.get("tires", false)
	if map.has("clips"):
		var cmap := {}
		for src_name in map.clips:
			var b := find_bone(skel, map.clips[src_name])
			if b >= 0:
				cmap[src_name] = b
		rt = Retarget.new()
		var pel := _one("pelvis")
		var hip_h: float = (skel.global_transform * skel.get_bone_global_rest(pel).origin).y - body.global_position.y
		rt.setup(skel, cmap, body, hip_h)
	_clip_arms = map.get("clip_arms", false) and rt != null
	if map.get("arms_down", false) and (rt == null or _clip_arms):
		for s in [["l", 1.0], ["r", -1.0]]:
			_arm_down(s[0], _side_sk * s[1])
			if map.has("fingers"):
				_palm_to_body(s[0], _side_sk * s[1], map.fingers)
	if map.has("fingers"):
		for s in ["L", "R"]:
			_relax_fingers(map.fingers, s)


## Exact name, or the same name with the "_123" suffix Sketchfab exports add.
static func find_bone(skel: Skeleton3D, bone_name: String) -> int:
	var b := skel.find_bone(bone_name)
	if b >= 0:
		return b
	var re := RegEx.create_from_string("^" + _escape(bone_name) + "_\\d+$")
	for i in skel.get_bone_count():
		if re.search(skel.get_bone_name(i)) != null:
			return i
	return -1


## Hangs `child` under `parent` without moving it: the rest is recomputed so the bone stays
## where it was (the skin binds are global, so the mesh does not change).
static func reparent_bone(skel: Skeleton3D, child: String, parent: String) -> void:
	var c := find_bone(skel, child)
	var p := find_bone(skel, parent)
	if c < 0 or p < 0:
		return
	var g := skel.get_bone_global_rest(c)
	skel.set_bone_parent(c, p)
	var r := skel.get_bone_global_rest(p).affine_inverse() * g
	skel.set_bone_rest(c, r)
	skel.set_bone_pose(c, r)


static func _escape(s: String) -> String:
	for c in ["\\", ".", "+", "*", "?", "(", ")", "[", "]", "{", "}", "^", "$", "|"]:
		s = s.replace(c, "\\" + c)
	return s


func has_role(role: String) -> bool:
	return not _ids(role).is_empty()


func _ids(role: String) -> Array:
	var v = _b.get(role, -1)
	if v is Array:
		return v
	return [] if v < 0 else [v]


func _one(role: String) -> int:
	var ids := _ids(role)
	return ids[0] if ids.size() > 0 else -1


func _frame(b: int) -> void:
	var g := skeleton.get_bone_global_rest(b).basis.orthonormalized()
	_ax[b] = [(g.inverse() * _side_sk).normalized(), (g.inverse() * _up_sk).normalized(), (g.inverse() * _fwd_sk).normalized()]
	_q[b] = skeleton.get_bone_rest(b).basis.get_rotation_quaternion()


## Starts the three-knock hammering (the stake).
func hammer() -> void:
	_hammer = 0.0


func hammering() -> bool:
	return _hammer >= 0.0


## Poses the bones for this frame. `measured` is the real speed, m/s.
## Returns +1 / -1 when the left / right foot lands this frame, else 0.
func update(delta: float, measured: float) -> int:
	_time += delta
	speed = lerpf(speed, measured, 1.0 - exp(-7.0 * delta))
	var st := _tire(delta)          # stumble envelope 0..1
	var r0 := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var clip_landed := 0
	if rt != null:
		# Real clips first; everything below is added on top of them.
		var res := rt.apply(delta, speed * (1.0 + 0.2 * fatigue * r0))
		_offset = res[0]
		clip_landed = res[1]
		if _clip_arms:
			_aim_arms_like_clip()
		phase = rt.phase * TAU
	else:
		phase = fmod(phase + speed / (_stride() * (1.0 - 0.22 * fatigue * r0)) * TAU * delta, TAU)
	var loco := 0.0 if rt != null else 1.0   # the procedural walk only without clips
	var yaw := _body.global_rotation.y if _body != null else 0.0
	_turn = lerpf(_turn, angle_difference(_yaw_prev, yaw) / maxf(delta, 0.0001), 1.0 - exp(-6.0 * delta))
	_yaw_prev = yaw
	var w := clampf(speed / walk_speed, 0.0, 1.0)
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var idle := 1.0 - w
	var s := sin(phase)
	var c := cos(phase)
	var hm := _hammer_env(delta)
	var ft := fatigue * w          # tired while moving
	var wd := _winded              # bent over after the run
	_breath_ph += delta * (2.1 + 3.6 * maxf(fatigue, wd))

	# Pelvis: twists with the forward leg, drops on the swinging side, shifts weight when idle.
	var p_yaw := -lerpf(0.12, 0.16, r) * w * s * loco
	var p_roll := (-0.05 * w * c + 0.035 * idle * sin(_time * 0.7)) * loco
	# Bending over (catching breath, a stumble) happens mostly at the hips.
	var hip_bend := 0.55 * wd + 0.18 * st
	_pose(_one("pelvis"), hip_bend, p_yaw, p_roll)

	# Spine: twists back against the pelvis, leans into the run, breathes.
	var spine := _ids("spine")
	var n := maxf(spine.size(), 1)
	var breath := sin(_breath_ph) * (0.022 * (0.4 + 0.6 * idle) * loco + 0.05 * maxf(fatigue * 0.6, wd))
	for b in spine:
		var pitch := (0.1 * r * w * loco + breath + 0.42 * hm + 0.4 * st + 0.62 * wd) / n
		_pose(b, pitch, -p_yaw * 0.85 / n, -p_roll * 0.7 / n)

	# Head: keeps level against the body, nods with the steps, looks at things.
	var look := _look_yaw()
	var head_yaw := _look.step(look, delta, 4.0, 0.9)
	var nod := (0.035 * w * cos(phase * 2.0) - 0.1 * r * w + 0.03 * sin(_time * 0.5) * idle) * loco - 0.25 * hm
	nod += 0.16 * ft + 0.06 * ft * sin(phase * 2.0) + 0.2 * st - 0.42 * wd   # droops, bobs; looks up when bent over
	_pose(_one("neck"), nod * 0.4, head_yaw * 0.4 + p_yaw * 0.1, 0.0)
	_pose(_one("head"), nod * 0.6, head_yaw * 0.6 + p_yaw * 0.05, -p_roll * 0.3)

	# Legs: swing, bend the knee in the swing, keep the foot flat, crouch for the hammer.
	var thigh := lerpf(0.4, 0.72, r) * w * loco
	var knee := lerpf(0.6, 1.25, r) * w * loco
	for side in [["l", 0.0], ["r", PI]]:
		var ph: float = phase + side[1]
		var buckle: float = st * (1.0 if (side[0] == "l") == (_stumble_side > 0.0) else 0.0)
		var a_t: float = -thigh * sin(ph) - 0.35 * hm - 0.3 * buckle + 0.15 * (st - buckle) - 0.22 * wd - hip_bend
		var a_k: float = ((0.05 + knee * pow(maxf(0.0, cos(ph)), 1.4)) * w + 0.04 * idle) * loco + 0.6 * hm + 0.75 * buckle + 0.32 * wd
		_pose(_one("thigh_" + side[0]), a_t, 0.0, 0.0)
		_pose(_one("shin_" + side[0]), a_k, 0.0, 0.0)
		_pose(_one("foot_" + side[0]), -(a_t + a_k) * 0.75 - 0.2 * w * maxf(0.0, -sin(ph)) * maxf(0.0, cos(ph)) * loco - 0.25 * hm, 0.0, 0.0)

	# Arms: swing against the legs a touch late, bend more in the run, strike for the hammer.
	var arm := lerpf(0.3, 0.55, r) * w * loco
	for side in [["l", 0.0, 1.0], ["r", PI, -1.0]]:
		var ph: float = phase + side[1] - 0.2
		var hold := _hold if side[0] == "r" else 0.0
		var swing: float = (arm * sin(ph) * (1.0 - 0.7 * hold) + 0.03 * sin(_time * 1.6 + side[1]) * idle) * loco
		var strike := -(0.55 + 0.75 * (0.5 + 0.5 * cos(_hammer_knock() * TAU))) * hm
		var elbow := -(0.05 + 0.22 * w * maxf(0.0, -sin(ph)) + lerpf(0.1, 0.7, r) * w) * loco - 0.5 * hm
		var free := 1.0 - hold
		# Worn out: the free arm flails out for balance; a stumble throws both arms forward;
		# bent over, the free hand goes to the knee.
		var flail: float = ft * free * (0.55 + 0.35 * sin(phase * 1.3 + side[1] * 0.7))
		swing += -0.45 * ft * free * sin(phase * 1.6 + 0.8) - 0.6 * st - 0.6 * wd * free
		elbow += -0.35 * ft * free - 0.12 * wd * free
		_pose(_one("upper_arm_" + side[0]), swing + strike, 0.0, side[2] * ((0.07 * r + 0.02) * loco + flail))
		_pose(_one("forearm_" + side[0]), elbow * (1.0 - 0.6 * hold), 0.0, 0.0)

	# Ears and tail on springs: they lag behind the steps and the turns.
	_twitch -= delta
	var twitch := 0.0
	if _twitch <= 0.0:
		_twitch = _rng.randf_range(2.5, 6.0)
		twitch = _rng.randf_range(-40.0, 40.0)
	var bob_acc := -cos(phase * 2.0) * (TAU * speed / _stride()) * 0.6
	var k := 0
	for b in _ids("ears"):
		var sp: Array = _ears[k]
		var e_pitch: float = sp[0].step(-0.12 * w - 0.35 * r * w - 0.3 * ft + 0.2 * wd, delta, 5.0, 0.2, bob_acc * 0.4 + (twitch if k == 0 else 0.0) + 60.0 * st)
		var e_yaw: float = sp[1].step(clampf(-_turn * 0.12, -0.5, 0.5), delta, 6.0, 0.25)
		_pose_bone(b, e_pitch, e_yaw, 0.0)
		k += 1
	var prev := 0.0
	k = 0
	for b in _ids("tail"):
		var drive := (0.3 * w * sin(phase) + 0.14 * idle * sin(_time * 1.3)) if k == 0 else prev
		var t_yaw: float = _tail[k].step(drive - _turn * 0.08, delta, 6.0 - k, 0.3)
		_pose_bone(b, -0.06 * w, t_yaw, 0.0)
		prev = t_yaw
		k += 1

	_reach_for_leash(delta)
	_soft_parts(delta)

	if rt != null:
		return clip_landed
	var sign := 1 if s > 0.0 else -1
	var landed := 0
	if w > 0.15 and sign != _last_sign:
		landed = sign
	_last_sign = sign
	return landed


## Tiredness: builds while dragged at a run, a stumble now and then when worn out,
## bent over catching breath after stopping. Returns the stumble envelope (0..1).
func _tire(delta: float) -> float:
	if not _tires:
		return 0.0
	var straining := (dragged or hold_pull > 0.6) and speed > walk_speed * 1.15
	if straining:
		fatigue = minf(1.0, fatigue + delta / TIRE_TIME)
	else:
		fatigue = maxf(0.0, fatigue - delta / REST_TIME)
	if _stumble < 0.0 and straining and fatigue > 0.45:
		_stumble_wait -= delta
		if _stumble_wait <= 0.0:
			_stumble = 0.0
			_stumble_side = 1.0 if _rng.randf() < 0.5 else -1.0
			_stumble_wait = _rng.randf_range(1.2, 2.8) * (1.3 - 0.5 * fatigue)
	var st := 0.0
	if _stumble >= 0.0:
		_stumble += delta
		if _stumble > STUMBLE_TIME:
			_stumble = -1.0
		else:
			st = sin(PI * _stumble / STUMBLE_TIME)
	# Stopped worn out (over half), she stays bent over until she is mostly rested.
	var bent := speed < 0.4 and not straining and fatigue > 0.22 and (_winded > 0.05 or fatigue > 0.5)
	var bend := 1.0 if bent else 0.0
	_winded = move_toward(_winded, bend, delta * (1.2 if bend > _winded else 0.8))
	return st


func stumbling() -> bool:
	return _stumble >= 0.0


func winded() -> float:
	return _winded


func _stride() -> float:
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	return lerpf(stride, run_stride, r)


## Soft parts (the chest) follow the body through a damped spring: a point mass is pulled
## toward where the part's tip would be, lags behind each push, and settles after a stop.
## The lag turns the part's root bone so its tip sits at the mass. Realistic, not exaggerated:
## SOFT_FREQ / SOFT_DAMP / SOFT_MAX set how it moves.
const SOFT_FREQ := 2.0     ## oscillations per second
const SOFT_DAMP := 0.27    ## 0 = endless wobble, 1 = no overshoot
const SOFT_MAX := 0.024     ## largest lag, as a share of the character's height

func _soft_parts(delta: float) -> void:
	if _soft.is_empty():
		return
	var to_sk := skeleton.global_transform.affine_inverse()
	var w := TAU * SOFT_FREQ
	var limit := SOFT_MAX * _height_hint
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var dt := delta / steps
	for part in _soft:
		var root: int = part[0]
		var tip: int = part[1]
		skeleton.set_bone_pose_rotation(root, _q[root])
		var g_root := skeleton.get_bone_global_pose(root)
		var anchor := skeleton.global_transform * skeleton.get_bone_global_pose(tip).origin
		if not part[4]:
			part[2] = anchor
			part[3] = Vector3.ZERO
			part[4] = true
			part[5] = anchor
		var x: Vector3 = part[2]
		var v: Vector3 = part[3]
		var from: Vector3 = part[5]
		var v_anchor := (anchor - from) / maxf(delta, 0.0001)
		part[5] = anchor
		# Damping acts on the motion relative to the body: steady walking leaves no lag,
		# only pushes (steps, starts, stops, turns) do.
		for i in steps:
			var a_now := from.lerp(anchor, float(i + 1) / steps)
			v += (w * w * (a_now - x) - 2.0 * SOFT_DAMP * w * (v - v_anchor)) * dt
			x += v * dt
		var lag := (x - anchor).limit_length(limit)
		x = anchor + lag
		part[2] = x
		part[3] = v
		var base := (to_sk * anchor) - g_root.origin
		var moved := (to_sk * x) - g_root.origin
		if base.length() < 1e-6:
			continue
		var q := _arc(base.normalized(), moved.normalized())
		var gb := g_root.basis.orthonormalized()
		skeleton.set_bone_pose_rotation(root, _q[root] * Quaternion(gb.inverse() * Basis(q) * gb))


var _height_hint := 1.6    ## character height in metres (set by the actor)


## Vertical bob of the whole body, metres per metre of height: low when a foot lands.
func bob() -> float:
	var w := clampf(speed / walk_speed, 0.0, 1.0)
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	return lerpf(0.012, 0.035, r) * w * (0.5 + 0.5 * cos(phase * 2.0)) - 0.06 * _hammer_env(0.0)


## Where the body sits this frame (metres, character space): the clips' hips, or the bob.
func body_offset(height: float) -> Vector3:
	if rt != null:
		return _offset - Vector3(0, 0.06 * _hammer_env(0.0) * height, 0)
	return Vector3(0, bob() * height, 0)


## Forward lean of the whole body (radians), from the gait plus any extra lean.
func body_lean() -> float:
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var run_lean := 0.0 if rt != null else lerpf(0.02, 0.1, r) * clampf(speed / walk_speed, 0.0, 1.0)
	return run_lean + lean - 0.1 * fatigue * r


func foot_position(left: bool) -> Vector3:
	var b := _one("foot_l" if left else "foot_r")
	if b < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin


## Without clips: sets the bone (rest + these angles). With clips: adds the angles on top of the
## clip's pose, about the character's own axes as seen in the bone's current frame.
func _pose(b: int, pitch: float, yaw: float, roll: float) -> void:
	if rt == null:
		_pose_bone(b, pitch, yaw, roll)
		return
	if b < 0 or (absf(pitch) < 1e-5 and absf(yaw) < 1e-5 and absf(roll) < 1e-5):
		return
	var g := skeleton.get_bone_global_pose(b).basis.orthonormalized().inverse()
	var extra := Quaternion((g * _side_sk).normalized(), pitch) * Quaternion((g * _up_sk).normalized(), yaw) * Quaternion((g * _fwd_sk).normalized(), roll)
	skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b) * extra)


func _pose_bone(b: int, pitch: float, yaw: float, roll: float) -> void:
	if b < 0:
		return
	var ax: Array = _ax[b]
	skeleton.set_bone_pose_rotation(b, _q[b] * Quaternion(ax[0], pitch) * Quaternion(ax[1], yaw) * Quaternion(ax[2], roll))


## 0..1 envelope of the hammering (eases in and out). Advances it when delta > 0.
func _hammer_env(delta: float) -> float:
	if _hammer < 0.0:
		return 0.0
	_hammer += delta
	if _hammer > HAMMER_TIME:
		_hammer = -1.0
		return 0.0
	var t := _hammer / HAMMER_TIME
	return smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.85, 1.0, t))


## 0..1 within each of the three knocks.
func _hammer_knock() -> float:
	return fmod(maxf(_hammer, 0.0) / HAMMER_TIME * 3.0, 1.0)


func _look_yaw() -> float:
	if look_target != Vector3.INF and _body != null:
		var l := _body.global_transform.affine_inverse() * look_target
		return clampf(atan2(l.x, l.z), -0.9, 0.9)
	var idle := 1.0 - clampf(speed / walk_speed, 0.0, 1.0)
	return (0.35 * sin(_time * 0.37) + 0.15 * sin(_time * 0.91 + 1.0)) * idle


## The right hand holds the leash: two-bone IK puts the wrist on a point toward the leash.
## Slack leash: the elbow is softly bent and the hand rides the steps; taut leash: the arm
## straightens toward TOFU. The fingers close around the leash.
func _reach_for_leash(delta: float) -> void:
	# Slow, eased changes: the arm takes about half a second to come up or settle.
	_hold = move_toward(_hold, 1.0 if hold_target != Vector3.INF else 0.0, delta * 2.2)
	_pull = lerpf(_pull, hold_pull, 1.0 - exp(-2.2 * delta))
	var hold := smoothstep(0.0, 1.0, _hold)
	for g in _grip:
		var b: int = g[0]
		skeleton.set_bone_pose_rotation(b, _q[b] * Quaternion(g[1], 0.5 * hold))
	var ua := _one("upper_arm_r")
	var fa := _one("forearm_r")
	var hand := _one("hand_r")
	if _hold < 0.001 or ua < 0 or fa < 0 or hand < 0:
		_ik_ready = false
		return
	if hold_target != Vector3.INF:
		_hold_point = hold_target
	var to_sk := skeleton.global_transform.affine_inverse()
	var g_ua := skeleton.get_bone_global_pose(ua)
	var g_fa := skeleton.get_bone_global_pose(fa)
	var g_h := skeleton.get_bone_global_pose(hand)
	var sh := g_ua.origin
	var el := g_fa.origin
	var wr := g_h.origin
	var l1 := (el - sh).length()
	var l2 := (wr - el).length()
	# Where the wrist goes: toward the leash, low and in front when slack, at reach when taut.
	var to_leash := _shoulder_limit(((to_sk * _hold_point) - sh).normalized())
	var rest_dir := (-_up_sk + _fwd_sk * 0.3 - _side_sk * 0.4).normalized()
	var dir := rest_dir.slerp(to_leash, 0.45 + 0.55 * _pull).normalized()
	var reach := (l1 + l2) * lerpf(0.86, 0.99, _pull)
	var bounce := _up_sk * (l1 + l2) * 0.025 * sin(phase * 2.0) * clampf(speed / walk_speed, 0.0, 1.0)
	var goal := sh + dir * reach
	# The wrist goal is followed through a soft spring in the shoulder's frame, so sudden turns
	# of TOFU swing the arm over smoothly instead of snapping it.
	var rel := goal - sh
	if not _ik_ready:
		_ik_x = rel
		_ik_v = Vector3.ZERO
		_ik_ready = true
	var wk := TAU * 1.1
	_ik_v += (wk * wk * (rel - _ik_x) - 2.0 * 0.85 * wk * _ik_v) * delta
	_ik_x += _ik_v * delta
	var target := sh + _ik_x.normalized() * minf(_ik_x.length(), (l1 + l2) * 0.99) + bounce
	target = wr.lerp(target, hold)
	# Two-bone IK: the elbow bends down, back and out.
	var d := clampf((target - sh).length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var u := (target - sh).normalized()
	var pole := (-_up_sk - _fwd_sk * 0.5 - _side_sk * 0.6)
	pole = (pole - u * pole.dot(u)).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var el_new := sh + (u * cos_a + pole * sqrt(1.0 - cos_a * cos_a)) * l1
	var q1 := _arc((el - sh).normalized(), (el_new - sh).normalized())
	var gb1 := g_ua.basis.orthonormalized()
	skeleton.set_bone_pose_rotation(ua, skeleton.get_bone_pose_rotation(ua) * Quaternion(gb1.inverse() * Basis(q1) * gb1))
	var fa_now := q1 * (wr - el).normalized()
	var q2 := _arc(fa_now, (sh + u * d - el_new).normalized())
	var gb2 := (Basis(q1) * g_fa.basis.orthonormalized()).orthonormalized()
	skeleton.set_bone_pose_rotation(fa, skeleton.get_bone_pose_rotation(fa) * Quaternion(gb2.inverse() * Basis(q2) * gb2))


## What a right shoulder can do: the arm follows the leash strongly, but never further than
## ARM_ACROSS across the chest, ARM_BACK behind the side, or ARM_UP above the horizon.
const ARM_ACROSS := deg_to_rad(30.0)
const ARM_BACK := deg_to_rad(115.0)
const ARM_UP := deg_to_rad(65.0)

func _shoulder_limit(d: Vector3) -> Vector3:
	var out := -_side_sk          # the right arm's outward side
	var o := d.dot(out)
	var f := d.dot(_fwd_sk)
	var u := d.dot(_up_sk)
	var az := atan2(o, f)                     # 0 = ahead, + = out to the right side
	if az < -ARM_ACROSS and f < 0.0:
		az = ARM_BACK                         # behind her left: reach back along the right side
	az = clampf(az, -ARM_ACROSS, ARM_BACK)
	var el := clampf(asin(clampf(u, -1.0, 1.0)), -PI * 0.5, ARM_UP)
	return (out * sin(az) * cos(el) + _fwd_sk * cos(az) * cos(el) + _up_sk * sin(el)).normalized()


## The arm's direction in the body frame: [azimuth, elevation] (for tests).
func right_arm_angles() -> Vector2:
	var ua := _one("upper_arm_r")
	var hand := _one("hand_r")
	var d := (skeleton.get_bone_global_pose(hand).origin - skeleton.get_bone_global_pose(ua).origin).normalized()
	return Vector2(atan2(d.dot(-_side_sk), d.dot(_fwd_sk)), asin(clampf(d.dot(_up_sk), -1.0, 1.0)))


## The hanging arm's palm should face the thigh, as people's do: twist the forearm about its own
## axis (shared over its twist segments so the wrist skin does not wring) until the palm faces
## the body, a little to the back, and straighten the wrist in line with the forearm.
func _palm_to_body(s: String, out_sk: Vector3, f: Dictionary) -> void:
	var fa := _one("forearm_" + s)
	var hand := _one("hand_" + s)
	var side := s.to_upper()
	var idx := find_bone(skeleton, f.finger % ["index", 1, side])
	var pinky := find_bone(skeleton, f.finger % ["pinky", 1, side])
	var mid := find_bone(skeleton, f.finger % ["middle", 1, side])
	var thumb := find_bone(skeleton, f.thumb % [3, side])
	if fa < 0 or hand < 0 or idx < 0 or pinky < 0 or mid < 0 or thumb < 0:
		return
	# The twist segments between the forearm and the hand.
	var chain := []
	var b := skeleton.get_bone_parent(hand)
	while b >= 0 and b != fa:
		chain.push_front(b)
		b = skeleton.get_bone_parent(b)
	chain.push_front(fa)
	skeleton.set_bone_pose_rotation(fa, _q[fa])
	var gp := func(i: int) -> Vector3: return skeleton.get_bone_global_pose(i).origin
	# Straighten the wrist: the hand points along the forearm.
	var axis: Vector3 = (gp.call(hand) - gp.call(fa)).normalized()
	var g_h := skeleton.get_bone_global_pose(hand).basis.orthonormalized()
	var hq := _arc((gp.call(mid) - gp.call(hand)).normalized(), axis)
	_q[hand] = skeleton.get_bone_pose_rotation(hand) * Quaternion(g_h.inverse() * Basis(hq) * g_h)
	skeleton.set_bone_pose_rotation(hand, _q[hand])
	# Palm normal now, and where it should face.
	var across: Vector3 = gp.call(idx) - gp.call(pinky)
	var normal := across.cross(axis).normalized()
	if normal.dot(gp.call(thumb) - (gp.call(idx) + gp.call(pinky)) * 0.5) < 0.0:
		normal = -normal
	var want := -out_sk - _fwd_sk * 0.35
	want = (want - axis * want.dot(axis)).normalized()
	var have := (normal - axis * normal.dot(axis)).normalized()
	var angle := atan2(have.cross(want).dot(axis), have.dot(want))
	for seg in chain:
		var g := skeleton.get_bone_global_pose(seg).basis.orthonormalized()
		var turn := Quaternion((g.inverse() * axis).normalized(), angle / chain.size())
		var now := skeleton.get_bone_pose_rotation(seg) * turn
		skeleton.set_bone_pose_rotation(seg, now)
		if seg == fa:
			_q[fa] = now


## Arms for a model whose rest is far from the clip's (Chobby's V-sign): instead of copying the
## clip's arm rotations (which carry the clip's twist and wring the wrists), start from a
## natural arms-down pose and swing the upper arm and the forearm by the shortest turn to point
## where the clip's point. The swing comes from the clip; the twist stays natural.
func _aim_arms_like_clip() -> void:
	var to_sk := rt.to_char.inverse()
	for s in [["l", "L"], ["r", "R"]]:
		var ua := _one("upper_arm_" + s[0])
		var fa := _one("forearm_" + s[0])
		var hand := _one("hand_" + s[0])
		var dirs := rt.arm_dirs(s[1])
		if ua < 0 or fa < 0 or hand < 0 or dirs.is_empty():
			continue
		skeleton.set_bone_pose_rotation(ua, _q[ua])
		skeleton.set_bone_pose_rotation(fa, _q[fa])
		var g_ua := skeleton.get_bone_global_pose(ua)
		var g_fa := skeleton.get_bone_global_pose(fa)
		var q1 := _arc((g_fa.origin - g_ua.origin).normalized(), (to_sk * dirs[0]).normalized())
		var gb1 := g_ua.basis.orthonormalized()
		skeleton.set_bone_pose_rotation(ua, _q[ua] * Quaternion(gb1.inverse() * Basis(q1) * gb1))
		g_fa = skeleton.get_bone_global_pose(fa)
		var g_h := skeleton.get_bone_global_pose(hand)
		var q2 := _arc((g_h.origin - g_fa.origin).normalized(), (to_sk * dirs[1]).normalized())
		var gb2 := g_fa.basis.orthonormalized()
		skeleton.set_bone_pose_rotation(fa, _q[fa] * Quaternion(gb2.inverse() * Basis(q2) * gb2))


## Base pose for models whose rest pose has the arms up: hang each arm down at the side,
## elbow a little bent. Folded into the base rotation, so the swing is added on top.
func _arm_down(s: String, out_sk: Vector3) -> void:
	var ua := _one("upper_arm_" + s)
	var fa := _one("forearm_" + s)
	var hand := _one("hand_" + s)
	if ua < 0 or fa < 0 or hand < 0:
		return
	var p_ua := skeleton.get_bone_global_rest(ua).origin
	var p_fa := skeleton.get_bone_global_rest(fa).origin
	var p_h := skeleton.get_bone_global_rest(hand).origin
	var g_ua := skeleton.get_bone_global_rest(ua).basis.orthonormalized()
	var g_fa := skeleton.get_bone_global_rest(fa).basis.orthonormalized()
	var q1 := _arc((p_fa - p_ua).normalized(), (-_up_sk + out_sk * 0.3 + _fwd_sk * 0.02).normalized())
	_q[ua] = _q[ua] * Quaternion(g_ua.inverse() * Basis(q1) * g_ua)
	var q2 := _arc(q1 * (p_h - p_fa).normalized(), (-_up_sk + _fwd_sk * 0.15 + out_sk * 0.04).normalized())
	var g_fa_now := Basis(q1) * g_fa
	_q[fa] = _q[fa] * Quaternion(g_fa_now.inverse() * Basis(q2) * g_fa_now)
	var g_ua_now := Basis(q1) * g_ua
	var g_fa_end := Basis(q2) * g_fa_now
	_ax[ua] = [(g_ua_now.inverse() * _side_sk).normalized(), (g_ua_now.inverse() * _up_sk).normalized(), (g_ua_now.inverse() * _fwd_sk).normalized()]
	_ax[fa] = [(g_fa_end.inverse() * _side_sk).normalized(), (g_fa_end.inverse() * _up_sk).normalized(), (g_fa_end.inverse() * _fwd_sk).normalized()]


## Base pose for the fingers: a soft, relaxed curl instead of whatever gesture the file has.
## `f`: {"finger": "DEF-f_%s.%02d.%s", "palm": "DEF-palm.%02d.%s", "thumb": "DEF-thumb.%02d.%s"}
func _relax_fingers(f: Dictionary, s: String) -> void:
	var names := ["index", "middle", "ring", "pinky"]
	var thumb := find_bone(skeleton, f.thumb % [3, s])
	var p_index := find_bone(skeleton, f.finger % ["index", 1, s])
	var p_pinky := find_bone(skeleton, f.finger % ["pinky", 1, s])
	var palm1 := find_bone(skeleton, f.palm % [1, s])
	var palm4 := find_bone(skeleton, f.palm % [4, s])
	if thumb < 0 or p_index < 0 or p_pinky < 0 or palm1 < 0 or palm4 < 0:
		return
	var o := func(b: int) -> Vector3: return skeleton.get_bone_global_rest(b).origin
	var across: Vector3 = (o.call(p_index) - o.call(p_pinky)).normalized()
	var along: Vector3 = ((o.call(p_index) - o.call(palm1)) + (o.call(p_pinky) - o.call(palm4))).normalized()
	var normal := along.cross(across).normalized()
	var mid: Vector3 = (o.call(palm1) + o.call(palm4)) * 0.5
	if normal.dot(o.call(thumb) - mid) < 0.0:
		normal = -normal          # the palm faces the side where the thumb tip is
	var curls := [0.42, 0.78, 0.55]   # knuckle, middle joint, tip joint: a soft, relaxed hand
	for i in names.size():
		var palm := find_bone(skeleton, f.palm % [i + 1, s])
		var seg := []
		for j in 3:
			seg.append(find_bone(skeleton, f.finger % [names[i], j + 1, s]))
		var tip := find_bone(skeleton, (f.finger % [names[i], 3, s]) + "_end")
		if palm < 0 or seg.has(-1):
			continue
		var dir: Vector3 = (o.call(seg[0]) - o.call(palm)).normalized()
		var acc := Quaternion.IDENTITY
		for j in 3:
			var b: int = seg[j]
			var nxt: Vector3
			if j < 2:
				nxt = o.call(seg[j + 1])
			elif tip >= 0 and (o.call(tip) - o.call(b)).length() > 1e-5:
				nxt = o.call(tip)                # the real fingertip
			else:
				nxt = o.call(b) + (o.call(seg[1]) - o.call(seg[0])).normalized()
			var cur: Vector3 = acc * (nxt - o.call(b)).normalized()
			dir = Quaternion(dir.cross(normal).normalized(), curls[j] + (0.06 * i)) * dir
			var q := _arc(cur, dir)
			var g := Basis(acc) * skeleton.get_bone_global_rest(b).basis.orthonormalized()
			_q[b] = skeleton.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(g.inverse() * Basis(q) * g)
			skeleton.set_bone_pose_rotation(b, _q[b])
			if s == "R":
				var g_now := Basis(q) * g
				_grip.append([b, (g_now.inverse() * dir.cross(normal)).normalized()])
			acc = q * acc


## Shortest rotation taking direction a to direction b.
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Quaternion(c.normalized(), atan2(c.length(), d))
