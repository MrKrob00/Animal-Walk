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

var _b := {}               ## role -> bone index, or Array of indices
var _q := {}               ## bone -> base rotation (rest, with any base pose folded in)
var _ax := {}              ## bone -> [side, up, forward] axes in the bone's own frame
var _time := 0.0
var _last_sign := 0
var _yaw_prev := 0.0
var _turn := 0.0           ## smoothed turning rate, rad/s
var _hold := 0.0           ## smoothed 0..1: the hand is on the leash
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

const HAMMER_TIME := 0.62


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
	if map.get("arms_down", false):
		for s in [["l", 1.0], ["r", -1.0]]:
			_arm_down(s[0], _side_sk * s[1])
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
	phase = fmod(phase + speed / _stride() * TAU * delta, TAU)
	var yaw := _body.global_rotation.y if _body != null else 0.0
	_turn = lerpf(_turn, angle_difference(_yaw_prev, yaw) / maxf(delta, 0.0001), 1.0 - exp(-6.0 * delta))
	_yaw_prev = yaw
	var w := clampf(speed / walk_speed, 0.0, 1.0)
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var idle := 1.0 - w
	var s := sin(phase)
	var c := cos(phase)
	var hm := _hammer_env(delta)

	# Pelvis: twists with the forward leg, drops on the swinging side, shifts weight when idle.
	var p_yaw := -lerpf(0.12, 0.16, r) * w * s
	var p_roll := -0.05 * w * c + 0.035 * idle * sin(_time * 0.7)
	_pose_bone(_one("pelvis"), 0.0, p_yaw, p_roll)

	# Spine: twists back against the pelvis, leans into the run, breathes.
	var spine := _ids("spine")
	var n := maxf(spine.size(), 1)
	var breath := sin(_time * 2.1) * 0.022 * (0.4 + 0.6 * idle)
	for b in spine:
		var pitch := (0.1 * r * w + breath + 0.42 * hm) / n
		_pose_bone(b, pitch, -p_yaw * 0.85 / n, -p_roll * 0.7 / n)

	# Head: keeps level against the body, nods with the steps, looks at things.
	var look := _look_yaw()
	var head_yaw := _look.step(look, delta, 4.0, 0.9)
	var nod := 0.035 * w * cos(phase * 2.0) - 0.1 * r * w - 0.25 * hm + 0.03 * sin(_time * 0.5) * idle
	_pose_bone(_one("neck"), nod * 0.4, head_yaw * 0.4 + p_yaw * 0.1, 0.0)
	_pose_bone(_one("head"), nod * 0.6, head_yaw * 0.6 + p_yaw * 0.05, -p_roll * 0.3)

	# Legs: swing, bend the knee in the swing, keep the foot flat, crouch for the hammer.
	var thigh := lerpf(0.4, 0.72, r) * w
	var knee := lerpf(0.6, 1.25, r) * w
	for side in [["l", 0.0], ["r", PI]]:
		var ph: float = phase + side[1]
		var a_t: float = -thigh * sin(ph) - 0.35 * hm
		var a_k: float = (0.05 + knee * pow(maxf(0.0, cos(ph)), 1.4)) * w + 0.04 * idle + 0.6 * hm
		_pose_bone(_one("thigh_" + side[0]), a_t, 0.0, 0.0)
		_pose_bone(_one("shin_" + side[0]), a_k, 0.0, 0.0)
		_pose_bone(_one("foot_" + side[0]), -(a_t + a_k) * 0.75 - 0.2 * w * maxf(0.0, -sin(ph)) * maxf(0.0, cos(ph)) - 0.25 * hm, 0.0, 0.0)

	# Arms: swing against the legs a touch late, bend more in the run, strike for the hammer.
	var arm := lerpf(0.3, 0.55, r) * w
	for side in [["l", 0.0, 1.0], ["r", PI, -1.0]]:
		var ph: float = phase + side[1] - 0.2
		var hold := _hold if side[0] == "r" else 0.0
		var swing: float = arm * sin(ph) * (1.0 - 0.7 * hold) + 0.03 * sin(_time * 1.6 + side[1]) * idle
		var strike := -(0.55 + 0.75 * (0.5 + 0.5 * cos(_hammer_knock() * TAU))) * hm
		var elbow := -(0.05 + 0.22 * w * maxf(0.0, -sin(ph)) + lerpf(0.1, 0.7, r) * w) - 0.5 * hm
		_pose_bone(_one("upper_arm_" + side[0]), swing + strike, 0.0, side[2] * (0.07 * r + 0.02))
		_pose_bone(_one("forearm_" + side[0]), elbow * (1.0 - 0.6 * hold), 0.0, 0.0)

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
		var e_pitch: float = sp[0].step(-0.12 * w - 0.35 * r * w, delta, 5.0, 0.2, bob_acc * 0.4 + (twitch if k == 0 else 0.0))
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

	var sign := 1 if s > 0.0 else -1
	var landed := 0
	if w > 0.15 and sign != _last_sign:
		landed = sign
	_last_sign = sign
	return landed


func _stride() -> float:
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	return lerpf(stride, run_stride, r)


## Soft parts (the chest) follow the body through a damped spring: a point mass is pulled
## toward where the part's tip would be, lags behind each push, and settles after a stop.
## The lag turns the part's root bone so its tip sits at the mass. Realistic, not exaggerated:
## SOFT_FREQ / SOFT_DAMP / SOFT_MAX set how it moves.
const SOFT_FREQ := 2.4     ## oscillations per second
const SOFT_DAMP := 0.32    ## 0 = endless wobble, 1 = no overshoot
const SOFT_MAX := 0.02     ## largest lag, as a share of the character's height

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


## Forward lean of the whole body (radians), from the gait plus any extra lean.
func body_lean() -> float:
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	return lerpf(0.02, 0.1, r) * clampf(speed / walk_speed, 0.0, 1.0) + lean


func foot_position(left: bool) -> Vector3:
	var b := _one("foot_l" if left else "foot_r")
	if b < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin


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


## The right hand reaches toward the leash; a taut leash pulls the arm straight.
func _reach_for_leash(delta: float) -> void:
	_hold = lerpf(_hold, 1.0 if hold_target != Vector3.INF else 0.0, 1.0 - exp(-6.0 * delta))
	var ua := _one("upper_arm_r")
	var fa := _one("forearm_r")
	var hand := _one("hand_r")
	if _hold < 0.01 or ua < 0 or fa < 0 or hand < 0 or hold_target == Vector3.INF:
		return
	var to_sk := skeleton.global_transform.affine_inverse()
	var g_ua := skeleton.get_bone_global_pose(ua)
	var g_fa := skeleton.get_bone_global_pose(fa)
	var cur := (g_fa.origin - g_ua.origin).normalized()
	var want := ((to_sk * hold_target) - g_ua.origin).normalized()
	var down := (-_up_sk + _fwd_sk * 0.35).normalized()
	var aim := down.slerp(want, clampf(0.25 + 0.6 * hold_pull, 0.0, 0.85)).normalized()
	var q := Quaternion(_arc(cur, aim)).slerp(Quaternion.IDENTITY, 1.0 - _hold)
	var gb := g_ua.basis.orthonormalized()
	var extra := Quaternion(gb.inverse() * Basis(q) * gb)
	skeleton.set_bone_pose_rotation(ua, skeleton.get_bone_pose_rotation(ua) * extra)


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
	var curls := [0.3, 0.55, 0.45]
	for i in names.size():
		var palm := find_bone(skeleton, f.palm % [i + 1, s])
		var seg := []
		for j in 3:
			seg.append(find_bone(skeleton, f.finger % [names[i], j + 1, s]))
		if palm < 0 or seg.has(-1):
			continue
		var dir: Vector3 = (o.call(seg[0]) - o.call(palm)).normalized()
		var acc := Quaternion.IDENTITY
		for j in 3:
			var b: int = seg[j]
			var nxt: Vector3 = o.call(seg[j + 1]) if j < 2 else o.call(b) + (o.call(seg[1]) - o.call(seg[0])).normalized()
			var cur: Vector3 = acc * (nxt - o.call(b)).normalized()
			dir = Quaternion(dir.cross(normal).normalized(), curls[j] + (0.06 * i)) * dir
			var q := _arc(cur, dir)
			var g := Basis(acc) * skeleton.get_bone_global_rest(b).basis.orthonormalized()
			_q[b] = skeleton.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(g.inverse() * Basis(q) * g)
			skeleton.set_bone_pose_rotation(b, _q[b])
			acc = q * acc


## Shortest rotation taking direction a to direction b.
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Quaternion(c.normalized(), atan2(c.length(), d))
