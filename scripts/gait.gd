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
var view_dir := Vector3.INF      ## first person: where the camera looks (world); the head follows it partly
var _view_pitch := 0.0
var hold_target := Vector3.INF   ## world point the right hand reaches to (the leash), or INF
var hold_pull := 0.0       ## 0..1: how hard the leash pulls the hand
var speed := 0.0           ## smoothed speed used for the pose, m/s
var dragged := false       ## set by the game: the leash is taut and pulls this character
var paw_target := Vector3.INF   ## set by the game: where the right paw's centre reaches (the paw stick); INF: hanging
var soft_poke := Vector4.ZERO   ## set by the game: a paw (centre, radius) the soft parts' tips are pushed out of
var soft_poke_vel := Vector3.ZERO   ## ... and how fast it moves (m/s)
var motion_fix := Vector3.ZERO  ## set by the actor: its position eased between physics ticks minus where it is (springs only)
var flesh_push := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]     ## set by the game: a paw pressing each flesh region (world metres)
var flesh_offset := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   ## out: how far each flesh region is moved now (for the shader)
var crawling := false      ## set by the game: under something low, crawl (army crawl)
var crawl := 0.0           ## 0..1 eased: how far down into the crawl
var crawl_lift := 0.0      ## metres the body is raised lying down (a thick body would sink: "crawl_lift")
var crawl_thick := 1.0     ## how thick the limbs are, for keeping them on the ground ("crawl_thick")
var _finger_bones := []    ## the fingers' joints (flat on the ground while crawling)
const CRAWL_TIME := 0.6    ## seconds to get down (or up)
const TAIL_CRAWL := -1.4    ## radians the tail bends over its bones when lying down (back along the ground)
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
		rt.setup(skel, cmap, body, hip_h, map.get("torso_swing", 1.0), map.get("clip_keep", []))
	_clip_arms = map.get("clip_arms", false) and rt != null
	_feminine = float(map.get("feminine", 0.0)) if rt != null else 0.0
	crawl_lift = float(map.get("crawl_lift", 0.0))
	crawl_thick = float(map.get("crawl_thick", 1.0))
	var tl := _one("thigh_l")
	var tr := _one("thigh_r")
	if tl >= 0 and tr >= 0:
		var d: Vector3 = body.global_basis.inverse() * (skel.global_transform.basis * (skel.get_bone_global_rest(tl).origin - skel.get_bone_global_rest(tr).origin))
		_left_char = Vector3(d.x, 0.0, d.z).normalized()
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
	b = skel.find_bone(bone_name.replace(".", "_"))   # glTF import turns "." into "_"
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
		crawl = move_toward(crawl, 1.0 if crawling else 0.0, delta / CRAWL_TIME)
		rt.crawl = smoothstep(0.0, 1.0, crawl)
		var res := rt.apply(delta, speed * (1.0 + 0.2 * fatigue * r0))
		_offset = res[0]
		clip_landed = res[1]
		if _feminine > 0.0:
			_feminine_walk()
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
	# First person: the head tips after the view, but only so far (the eyes do the rest).
	var want_pitch := 0.0
	if view_dir != Vector3.INF:
		want_pitch = clampf(-asin(clampf(view_dir.normalized().y, -1.0, 1.0)) * 0.55, -0.35, 0.6)
	_view_pitch = lerpf(_view_pitch, want_pitch, 1.0 - exp(-8.0 * delta))
	nod += _view_pitch
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
		# (Smooth in time: whole steps' phase wraps every cycle, and a fraction of it jumped the
		# arm each step; the player saw the free arm jerk.)
		var flail: float = ft * free * (0.3 + 0.12 * sin(_time * 2.3 + side[1] * 0.7))
		swing += -0.25 * ft * free * sin(_time * 3.1 + 0.8) - 0.6 * st - 0.6 * wd * free
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
		var sk_ := smoothstep(0.0, 1.0, sit) if sit_style == "dog" else 0.0   # sitting, it lies round on the ground
		_pose_bone(b, -0.06 * w + (TAIL_CRAWL / 3.0) * smoothstep(0.0, 1.0, crawl) + TAIL_SIT[0] / 3.0 * sk_, t_yaw + TAIL_SIT[1] / 3.0 * sk_, 0.0)   # lying down, it lies back along the ground
		prev = t_yaw
		k += 1

	_pulled_along(delta)
	_sit_pose(delta)
	_jump_pose(delta)
	_reach_for_leash(delta)
	_paw_reach(delta)
	_crawl_ground()
	_soft_parts(delta)
	_flesh_springs(delta)

	if rt != null:
		if airborne():
			return 0   # no steps in the air
		if _jump_landed:
			_jump_landed = false
			return 2   # both feet down at once (the actor leaves two prints)
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
	var straining := (dragged or hold_pull > 0.6) and speed > walk_speed * 1.15 and crawl < 0.5
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
const SOFT_FLOOR := 0.0   ## lying down, the chest's tip bone stays this share of her height above the ground (the skin gives: SoftPress)
const SOFT_GAIN := 0.6     ## share of the spring's lag shown: the clips swing the body three times
                           ## more than the old walk did, this keeps the chest's travel as it was

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
		var anchor := skeleton.global_transform * skeleton.get_bone_global_pose(tip).origin + motion_fix
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
			var a_now := from.lerp(anchor, float(i) / steps)   # where the anchor is at the start of the substep: taken at its end, the mass ran a substep ahead (1.2 cm walking, 2.8 running)
			v += (w * w * (a_now - x) - 2.0 * SOFT_DAMP * w * (v - v_anchor)) * dt
			x += v * dt
		var lag := x - anchor
		var reach := limit / SOFT_GAIN
		if lag.length() > reach:
			# At the limit: stop there, and lose the speed that pushes further out.
			var out := lag.normalized()
			lag = out * reach
			x = anchor + lag
			var rel := v - v_anchor
			v -= out * maxf(rel.dot(out), 0.0)
		# A paw pressing it (TOFU's, the player's easter egg): the tip is pushed out of the paw and
		# keeps the paw's speed into it, then swings back by itself.
		if soft_poke.w > 0.0:
			var c := Vector3(soft_poke.x, soft_poke.y, soft_poke.z)
			var shown := anchor + lag * SOFT_GAIN
			var off := shown - c
			if off.length() < soft_poke.w:
				var nrm := off.normalized() if off.length() > 1e-5 else Vector3.UP
				shown = c + nrm * soft_poke.w
				lag = (shown - anchor) / SOFT_GAIN
				if lag.length() > reach:
					lag = lag.normalized() * reach
				x = anchor + lag
				var into := (v - soft_poke_vel).dot(nrm)
				if into < 0.0:
					v -= nrm * into
		part[2] = x
		part[3] = v
		x = anchor + lag * SOFT_GAIN
		# Lying on the forearms, the chest never sinks into the ground.
		if crawl > 0.01 and _body != null and _body.get_parent() is Node3D:
			var floor_y := (_body.get_parent() as Node3D).global_position.y + SOFT_FLOOR * _height_hint
			if x.y < floor_y:
				x.y = floor_y
		var base := (to_sk * (anchor - motion_fix)) - g_root.origin   # back where the skeleton is now
		var moved := (to_sk * (x - motion_fix)) - g_root.origin
		if base.length() < 1e-6:
			continue
		var q := _arc(base.normalized(), moved.normalized())
		var gb := g_root.basis.orthonormalized()
		skeleton.set_bone_pose_rotation(root, _q[root] * Quaternion(gb.inverse() * Basis(q) * gb))


var _height_hint := 1.6    ## character height in metres (set by the actor)


## Soft flesh with no bones (SoftFlesh: her butt-and-thigh on each side, her belly): a spring per
## region riding on a bone; it lags behind the body's jolts (steps, starts, stops, each pull of
## the crawl), firmer and smaller than her chest; a paw pressing it moves it out of the way and
## it swings back after. Only the offsets go out (the shader moves the skin).
const FLESH_FREQ := 5.0     ## oscillations per second: firmer than the chest's 2.0; at 4 a run reached its limit every step
const FLESH_DAMP := 0.35
const FLESH_MAX := 0.011    ## largest lag shown, share of height (about 1.8 cm on her)
const FLESH_PUSH := 0.6     ## share of a paw's press the whole region gives (the rest: a local dent)
const FLESH_PUSH_MAX := 0.03

var _flesh := []   ## [bone, local, mass pos, mass vel, ready, last anchor]


func set_flesh(regions: Array) -> void:
	_flesh.clear()
	for r in regions:
		_flesh.append([r.bone, r.local, Vector3.ZERO, Vector3.ZERO, false, Vector3.ZERO])


func _flesh_springs(delta: float) -> void:
	if _flesh.is_empty():
		return
	var w := TAU * FLESH_FREQ
	var reach := FLESH_MAX * _height_hint / SOFT_GAIN
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var dt := delta / steps
	for k in _flesh.size():
		var part: Array = _flesh[k]
		if part[0] < 0:
			continue
		var push: Vector3 = (flesh_push[k] as Vector3).limit_length(FLESH_PUSH_MAX) * FLESH_PUSH
		var anchor: Vector3 = skeleton.global_transform * (skeleton.get_bone_global_pose(part[0]) * (part[1] as Vector3)) + motion_fix
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
		for i in steps:
			var a_now := from.lerp(anchor, float(i) / steps)   # where the anchor is at the start of the substep: taken at its end, the mass ran a substep ahead (1.2 cm walking, 2.8 running) + push
			v += (w * w * (a_now - x) - 2.0 * FLESH_DAMP * w * (v - v_anchor)) * dt
			x += v * dt
		var lag := x - (anchor + push)
		if lag.length() > reach:
			var out := lag.normalized()
			lag = out * reach
			x = anchor + push + lag
			v -= out * maxf((v - v_anchor).dot(out), 0.0)
		part[2] = x
		part[3] = v
		flesh_offset[k] = push + lag * SOFT_GAIN


## How far each flesh region is moved now (for tests).
func flesh_lag() -> Array:
	return flesh_offset.duplicate()


## Vertical bob of the whole body, metres per metre of height: low when a foot lands.
func bob() -> float:
	var w := clampf(speed / walk_speed, 0.0, 1.0)
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	return lerpf(0.012, 0.035, r) * w * (0.5 + 0.5 * cos(phase * 2.0)) - 0.06 * _hammer_env(0.0)


## Where the body sits this frame (metres, character space): the clips' hips, or the bob.
func body_offset(height: float) -> Vector3:
	if rt != null:
		return _offset - Vector3(0, 0.06 * _hammer_env(0.0) * height, 0) + Vector3(0, crawl_lift * smoothstep(0.0, 1.0, crawl), 0) - Vector3(0, _sit_drop() * smoothstep(0.0, 1.0, sit), 0) + Vector3(0, jump_height(), 0)
	return Vector3(0, bob() * height, 0)


## How far the body goes down to sit: from the hip joints' standing height to the style's.
func _sit_drop() -> float:
	if not SIT.has(sit_style):
		return 0.0
	if _hip_h < 0.0 and _body != null and _body.get_parent() is Node3D and _one("thigh_l") >= 0:
		var actor := _body.get_parent() as Node3D
		var hip := skeleton.global_transform * skeleton.get_bone_global_rest(_one("thigh_l")).origin
		_hip_h = hip.y - actor.global_position.y - _body.position.y
	return maxf(_hip_h - float(SIT[sit_style].hip), 0.0)


## Forward lean of the whole body (radians), from the gait plus any extra lean.
func body_lean() -> float:
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var run_lean := 0.0 if rt != null else lerpf(0.02, 0.1, r) * clampf(speed / walk_speed, 0.0, 1.0)
	return (run_lean + lean - 0.1 * fatigue * r) * (1.0 - crawl)


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
	if view_dir != Vector3.INF and _body != null:
		var v := _body.global_basis.inverse() * view_dir
		return clampf(atan2(v.x, v.z), -0.9, 0.9)
	if look_target != Vector3.INF and _body != null:
		var l := _body.global_transform.affine_inverse() * look_target
		return clampf(atan2(l.x, l.z), -0.9, 0.9)
	var idle := 1.0 - clampf(speed / walk_speed, 0.0, 1.0)
	return (0.35 * sin(_time * 0.37) + 0.15 * sin(_time * 0.91 + 1.0)) * idle


## The right hand holds the leash: two-bone IK puts the wrist on a point toward the leash.
## Slack leash: the elbow is softly bent and the hand rides the steps; taut leash: the arm
## straightens toward TOFU. The fingers close around the leash.
## Lying down, nothing goes into the ground: the fingers lie flat, and an arm or leg whose hand,
## elbow, foot or knee would sink is bent (two bones) to rest on the ground instead; paws and
## hands tip up off it. Sizes are shares of the height (limb thickness).
const CRAWL_FLOOR := {"hand": 0.025, "elbow": 0.035, "foot": 0.035, "knee": 0.035, "tip": 0.012}

func _crawl_ground() -> void:
	var k := smoothstep(0.0, 1.0, crawl)
	if k < 0.01 or _body == null or not (_body.get_parent() is Node3D):
		return
	for b in _finger_bones:
		skeleton.set_bone_pose_rotation(b, _q[b].slerp(skeleton.get_bone_rest(b).basis.get_rotation_quaternion(), k))
	var actor := _body.get_parent() as Node3D
	var floor_y := actor.global_position.y
	# This frame's body offset is set after this; count it in now.
	var corr: Vector3 = actor.global_basis * (body_offset(_height_hint) - _body.position)
	var sk_rot := skeleton.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var at := func(b: int) -> Vector3: return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin + corr
	var turn := func(b: int, q: Quaternion) -> void:
		var g := skeleton.get_bone_global_pose(b).basis.orthonormalized().get_rotation_quaternion()
		var qq := Quaternion.IDENTITY.slerp(q, k)
		_set_global_rot(b, (sk_rot.inverse() * qq * sk_rot) * g)
	var h := _height_hint
	for limb in [["upper_arm_l", "forearm_l", "hand_l", "elbow", "hand"], ["upper_arm_r", "forearm_r", "hand_r", "elbow", "hand"], ["thigh_l", "shin_l", "foot_l", "knee", "foot"], ["thigh_r", "shin_r", "foot_r", "knee", "foot"]]:
		var u := _one(limb[0])
		var m := _one(limb[1])
		var e := _one(limb[2])
		if u < 0 or m < 0 or e < 0:
			continue
		var r_mid: float = CRAWL_FLOOR[limb[3]] * h * crawl_thick
		var r_end: float = CRAWL_FLOOR[limb[4]] * h * crawl_thick
		var S: Vector3 = at.call(u)
		var M: Vector3 = at.call(m)
		var E: Vector3 = at.call(e)
		# Continuous: lifted exactly as far as it would sink, the knee / elbow kept where it is
		# otherwise (switched on at the floor with the knee pushed 2% of her height up, it popped
		# 11 cm in a frame each time a leg started to draw up: the player saw the legs jerk).
		if E.y < floor_y + r_end or M.y < floor_y + r_mid:
			var l1 := S.distance_to(M)
			var l2 := M.distance_to(E)
			var E2 := Vector3(E.x, maxf(E.y, floor_y + r_end), E.z)
			var pole := Vector3(M.x, maxf(M.y, floor_y + r_mid), M.z)
			var d := clampf(S.distance_to(E2), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
			var along := (E2 - S).normalized()
			var side := pole - S
			side = side - along * side.dot(along)
			if side.length() < 1e-5:
				continue
			side = side.normalized()
			var a := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
			var M2 := S + along * a + side * sqrt(maxf(l1 * l1 - a * a, 0.0))
			turn.call(u, _arc((M - S).normalized(), (M2 - S).normalized()))
			var M3: Vector3 = at.call(m)
			var E3: Vector3 = at.call(e)
			turn.call(m, _arc((E3 - M3).normalized(), (E2 - M3).normalized()))
		# The hand's fingers / the paw's toes: tipped up off the ground.
		var tip := -1
		if limb[4] == "hand":
			tip = find_bone(skeleton, "DEF-f_middle.03." + limb[2].right(1).to_upper())
		else:
			tip = find_bone(skeleton, "DEF-toe." + limb[2].right(1).to_upper())
		if tip >= 0:
			var E4: Vector3 = at.call(e)
			var T: Vector3 = at.call(tip)
			var lo := floor_y + CRAWL_FLOOR["tip"] * h
			if T.y < lo:
				var want := Vector3(T.x, lo, T.z) - E4
				turn.call(e, _arc((T - E4).normalized(), want.normalized()))


## Sitting (the sit button; the player chose the poses): the pelvis goes down to the ground, the
## legs and arms are put by two-bone IK to targets in the body's frame, blended in over SIT_TIME.
##   "w"   (the bunny, "frog" / W-sit): the butt on the ground between the feet, the knees in
##         front and close, the shins folded back and out so the paws lie beside the hips,
##         toes back; the hands rest on the thighs.
##   "dog" (TOFU, sitting like a dog): the butt on the ground, the knees up and apart, the feet
##         flat in front, the front paws on the ground between them, the back a little round,
##         the tail lying round on the ground.
const SIT_TIME := 0.7
const TAIL_SIT := [-1.3, 1.5]   ## dog sit: the tail down onto the ground and round to the side (radians over its bones)
const SIT := {
	"w": {"hip": 0.13, "pelvis": 0.10, "ankle": Vector3(0.28, 0.055, 0.04), "pole": Vector3(-0.15, -0.1, 0.6),
		"knee": Vector3(-0.12, 0.085, 1.0),
		"toe": Vector3(0.75, -0.12, -0.65), "hand": "thigh"},
	"dog": {"hip": 0.12, "pelvis": -0.28, "ankle": Vector3(0.13, 0.07, 0.22), "pole": Vector3(0.3, 0.7, 0.35),
		"toe": Vector3(0.25, -0.05, 1.0), "hand": Vector3(0.08, 0.055, 0.26)},
}   ## metres / radians: "hip" the hip joints' height sitting; "pelvis" tipped forward (+) or back;
    ## "ankle", "pole", "toe", "hand" in the body's frame (x out to the side, y up, z forward),
    ## the ankle from the hip joint, the hand from the hips' middle; the "pole" is where the knee goes;
    ## "knee" (W-sit): the thigh's way (x, z) and the knee's height (y) - put by hand, since an
    ## IK toward the ankle beside the hip swung the knees out to the sides.

var sitting := false        ## set by the game
var sit := 0.0              ## 0..1, eased
var sit_style := "w"        ## set by the actor ("sit" in its map)
var _hip_h := -1.0          ## the hip joints' height standing (metres), measured once


func _sit_pose(delta: float) -> void:
	sit = move_toward(sit, 1.0 if sitting and crawl < 0.05 else 0.0, delta / SIT_TIME)
	var k := smoothstep(0.0, 1.0, sit)
	if k < 0.001 or _body == null or not (_body.get_parent() is Node3D) or not SIT.has(sit_style):
		return
	var spec: Dictionary = SIT[sit_style]
	var actor := _body.get_parent() as Node3D
	var floor_y := actor.global_position.y
	var fwd := actor.global_basis.z.normalized()
	var left := actor.global_basis.x.normalized()
	var sk_rot := skeleton.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var corr: Vector3 = actor.global_basis * (body_offset(_height_hint) - _body.position)
	var at := func(b: int) -> Vector3: return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin + corr
	var turn := func(b: int, q: Quaternion) -> void:
		var g := skeleton.get_bone_global_pose(b).basis.orthonormalized().get_rotation_quaternion()
		_set_global_rot(b, (sk_rot.inverse() * q * sk_rot) * g)
	# The pelvis squares up to the body (standing, it shifts its weight and turns: the hips 6 cm
	# apart front to back folded one knee past its limit), then tips (the spine turns it back,
	# the chest stays upright).
	var pel := _one("pelvis")
	var tip: float = spec.pelvis * k
	if pel >= 0 and _one("thigh_l") >= 0 and _one("thigh_r") >= 0:
		var line: Vector3 = at.call(_one("thigh_l")) - at.call(_one("thigh_r"))
		line.y = 0.0
		if line.length() > 1e-4:
			turn.call(pel, Quaternion.IDENTITY.slerp(_arc(line.normalized(), left), k))
	if pel >= 0:
		turn.call(pel, Quaternion(left, tip))
		var sp := _ids("spine")
		if not sp.is_empty():
			turn.call(sp[0], Quaternion(left, -tip * 0.8))
	var frame := func(v: Vector3, out: Vector3) -> Vector3: return out * v.x + Vector3.UP * v.y + fwd * v.z
	var knees := []
	for side in [["l", 1.0], ["r", -1.0]]:
		var u := _one("thigh_" + side[0])
		var m := _one("shin_" + side[0])
		var e := _one("foot_" + side[0])
		if u < 0 or m < 0 or e < 0:
			continue
		var out: Vector3 = left * side[1]
		var H: Vector3 = at.call(u)
		var want: Vector3 = H + frame.call(spec.ankle, out)
		want.y = floor_y + float(spec.ankle.y)
		var E: Vector3 = at.call(e)
		if spec.has("knee"):
			# The thigh forward along the ground, the knee at its height; the shin back to the ankle.
			var M: Vector3 = at.call(m)
			var l1 := H.distance_to(M)
			var kd: Vector3 = spec.knee
			var flat: Vector3 = (out * kd.x + fwd * kd.z).normalized()
			var dy := clampf(floor_y + kd.y - H.y, -l1 * 0.9, l1 * 0.9)
			var K := H + flat * sqrt(l1 * l1 - dy * dy) + Vector3.UP * dy
			turn.call(u, Quaternion.IDENTITY.slerp(_arc((M - H).normalized(), (K - H).normalized()), k))
			var M2: Vector3 = at.call(m)
			var E2: Vector3 = at.call(e)
			turn.call(m, Quaternion.IDENTITY.slerp(_arc((E2 - M2).normalized(), (want - M2).normalized()), k))
		else:
			_ik_world(u, m, e, E.lerp(want, k), H + frame.call(spec.pole, out), turn, at)
		knees.append(at.call(m))
		# The paw along the ground.
		var toe := find_bone(skeleton, "DEF-toe." + side[0].to_upper())
		var d: Vector3 = (frame.call(spec.toe, out) as Vector3).normalized()
		var foot_now: Vector3 = (at.call(toe) - at.call(e)) if toe >= 0 else (skeleton.global_transform.basis * skeleton.get_bone_global_pose(e).basis.y)
		turn.call(e, Quaternion.IDENTITY.slerp(_arc(foot_now.normalized(), d), k))
		if toe >= 0:
			var t_now: Vector3 = skeleton.global_transform.basis * skeleton.get_bone_global_pose(toe).basis.y
			turn.call(toe, Quaternion.IDENTITY.slerp(_arc(t_now.normalized(), d), k))
	# The hands: on the thighs, or on the ground in front.
	var mid: Vector3 = (at.call(_one("thigh_l")) + at.call(_one("thigh_r"))) * 0.5 if _one("thigh_l") >= 0 and _one("thigh_r") >= 0 else actor.global_position
	var ki := 0
	for side in [["l", 1.0], ["r", -1.0]]:
		var u := _one("upper_arm_" + side[0])
		var m := _one("forearm_" + side[0])
		var e := _one("hand_" + side[0])
		if u < 0 or m < 0 or e < 0:
			continue
		var out: Vector3 = left * side[1]
		var want: Vector3
		if spec.hand is String:
			var H: Vector3 = at.call(_one("thigh_" + side[0]))
			var K: Vector3 = knees[ki] if ki < knees.size() else H + fwd * 0.3
			want = H.lerp(K, 0.6) + Vector3.UP * 0.075 * _height_hint / 1.6
		else:
			want = mid + frame.call(spec.hand, out)
			want.y = floor_y + float(spec.hand.y)
		ki += 1
		var S: Vector3 = at.call(u)
		var E: Vector3 = at.call(e)
		_ik_world(u, m, e, E.lerp(want, k), S - Vector3.UP * 0.3 + out * 0.3 - fwd * 0.2, turn, at)


## Jumping (the jump button; the player asked: the bunny's chest and hips moving with it, TOFU
## a jump of its own). A crouch, a ballistic flight, a landing that gives; the body goes up and
## down by body_offset, so the chest and flesh springs feel the take-off, the float and the
## landing by themselves. Limbs by two-bone IK to targets from the hips:
##   "hop"      (the bunny): crouch, arms swing back; take-off with the arms forward and up, the
##              legs trailing after the push, tucked up under her at the top, reaching down to
##              land; land into a soft squat.
##   "surprise" (TOFU, a red panda's "surprise!"): a low crouch with the tail swishing, then a
##              high leap with the front paws flung up and out, claws curled, the tail
##              streaming; land with a bounce (it turned round in the air: the player did not
##              want that).
const JUMP := {
	"hop": {"crouch": 0.16, "depth": 0.10, "height": 0.45, "land": 0.28, "squash": 0.08, "spin": 0.0,
		"arms_back": -0.6, "arms_up": 1.3, "arms_out": 0.0, "swish": 0.0,
		# Pushed off, trailing back; tucked up under her at the top; reaching down to land.
		"legs": [[0.0, Vector3(0.02, -0.44, -0.20)], [0.45, Vector3(0.03, -0.27, -0.06)], [0.85, Vector3(0.02, -0.42, 0.08)], [1.0, Vector3(0.02, -0.46, 0.03)]]},
	"surprise": {"crouch": 0.24, "depth": 0.12, "height": 0.55, "land": 0.32, "squash": 0.1, "spin": 0.0,
		"arms_back": -0.3, "arms_up": 0.0, "arms_out": 2.3, "swish": 0.9,
		"legs": [[0.0, Vector3(0.05, -0.36, -0.10)], [0.45, Vector3(0.07, -0.22, 0.06)], [0.85, Vector3(0.06, -0.33, 0.06)], [1.0, Vector3(0.06, -0.36, 0.03)]]},
}   ## seconds / metres / radians; "legs": the ankle through the flight from the hip (x out, y up,
    ## z forward) at shares of the flight, eased between (held in one tuck the whole flight, her
    ## legs flew stiff and the player found it odd); "spin" none for TOFU now (the player)
const LEG_LEAD := 0.04   ## the left leg runs this share of the flight ahead of the right
const GRAVITY := 9.8

var jump_style := "hop"     ## set by the actor ("jump" in its map)
var _jump_t := -1.0         ## seconds since the jump began; < 0: not jumping
var _jump_landed := false
var _rest_ankle := {}       ## side -> the ankle's place under the hip standing (body frame), measured once


## Starts a jump; false when it can't (already jumping, sitting, crawling).
func jump() -> bool:
	if _jump_t >= 0.0 or sit > 0.05 or crawl > 0.05 or not JUMP.has(jump_style):
		return false
	_jump_t = 0.0
	return true


func jumping() -> bool:
	return _jump_t >= 0.0


func _air_time() -> float:
	return 2.0 * sqrt(2.0 * float(JUMP[jump_style].height) / GRAVITY)


## In the air (between take-off and landing).
func airborne() -> bool:
	if _jump_t < 0.0:
		return false
	var j: Dictionary = JUMP[jump_style]
	return _jump_t > float(j.crouch) and _jump_t < float(j.crouch) + _air_time()


## [phase, 0..1]: "crouch", "air", "land".
func _jump_phase() -> Array:
	var j: Dictionary = JUMP[jump_style]
	var c := float(j.crouch)
	var a := _air_time()
	if _jump_t < c:
		return ["crouch", _jump_t / c]
	if _jump_t < c + a:
		return ["air", (_jump_t - c) / a]
	return ["land", clampf((_jump_t - c - a) / float(j.land), 0.0, 1.0)]


## The body's height from the jump (metres; negative crouching).
func jump_height() -> float:
	if _jump_t < 0.0:
		return 0.0
	var j: Dictionary = JUMP[jump_style]
	var ph := _jump_phase()
	var u: float = ph[1]
	match ph[0]:
		"crouch":
			return -float(j.depth) * smoothstep(0.0, 1.0, u)
		"air":
			return 4.0 * float(j.height) * u * (1.0 - u) - float(j.depth) * maxf(0.0, 1.0 - u / 0.12)
	return -float(j.squash) * sin(PI * u) * (1.0 - 0.3 * u)


## The turn in the air about the vertical (radians), for the actor's body.
func jump_spin() -> float:
	if _jump_t < 0.0:
		return 0.0
	var ph := _jump_phase()
	if ph[0] != "air":
		return 0.0
	var u: float = ph[1]
	return float(JUMP[jump_style].spin) * u * u * (3.0 - 2.0 * u)


func _jump_pose(delta: float) -> void:
	if _jump_t < 0.0 or _body == null or not (_body.get_parent() is Node3D):
		return
	var j: Dictionary = JUMP[jump_style]
	var was_air := airborne()
	_jump_t += delta
	if was_air and not airborne():
		_jump_landed = true
	if _jump_t > float(j.crouch) + _air_time() + float(j.land):
		_jump_t = -1.0
		return
	var ph := _jump_phase()
	var u: float = ph[1]
	var actor := _body.get_parent() as Node3D
	var floor_y := actor.global_position.y
	var fwd := actor.global_basis.z.normalized()
	var left := actor.global_basis.x.normalized()
	var sk_rot := skeleton.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var corr: Vector3 = actor.global_basis * (body_offset(_height_hint) - _body.position)
	var at := func(b: int) -> Vector3: return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin + corr
	var turn := func(b: int, q: Quaternion) -> void:
		var g := skeleton.get_bone_global_pose(b).basis.orthonormalized().get_rotation_quaternion()
		_set_global_rot(b, (sk_rot.inverse() * q * sk_rot) * g)
	# How much of the crouch / flight pose: in and out smoothly.
	var crouch := 0.0
	var air := 0.0
	match ph[0]:
		"crouch": crouch = smoothstep(0.0, 1.0, u)
		"air":
			air = smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.92, 1.0, u))
			crouch = 1.0 - smoothstep(0.0, 0.15, u)
		"land": crouch = sin(PI * u) * (1.0 - 0.3 * u)
	# The back bends into the crouch.
	var sp := _ids("spine")
	if not sp.is_empty():
		turn.call(sp[0], Quaternion(left, 0.3 * crouch))
	# Arms: back in the crouch, then up (forward) or flung up and out in the air.
	for side in [["l", 1.0], ["r", -1.0]]:
		var ua := _one("upper_arm_" + side[0])
		var fa := _one("forearm_" + side[0])
		if ua < 0:
			continue
		var q := Quaternion(left, -float(j.arms_up) * air) * Quaternion(left, -float(j.arms_back) * crouch)
		if float(j.arms_out) > 0.0:
			q = Quaternion(fwd, float(j.arms_out) * air * side[1]) * q
		turn.call(ua, q)
		if fa >= 0 and float(j.arms_out) > 0.0:
			turn.call(fa, Quaternion(left, -0.6 * air))   # claws up, elbows bent
	# Legs: on the ground the ankles stay where they stand (the knees bend as the hips go down);
	# in the air they tuck.
	for side in [["l", 1.0], ["r", -1.0]]:
		var u_ := _one("thigh_" + side[0])
		var m := _one("shin_" + side[0])
		var e := _one("foot_" + side[0])
		if u_ < 0 or m < 0 or e < 0:
			continue
		var out: Vector3 = left * side[1]
		var H: Vector3 = at.call(u_)
		if not _rest_ankle.has(side[0]):
			var hr := skeleton.global_transform * skeleton.get_bone_global_rest(u_).origin
			var ar := skeleton.global_transform * skeleton.get_bone_global_rest(e).origin
			var d := ar - hr
			_rest_ankle[side[0]] = Vector3(d.dot(out), ar.y - (actor.global_position.y + _body.position.y), d.dot(fwd))
		var ra: Vector3 = _rest_ankle[side[0]]
		var ground_ankle: Vector3 = H + out * ra.x + fwd * ra.z
		ground_ankle.y = floor_y + ra.y
		var tuck := _leg_path(j.legs, clampf(u + (LEG_LEAD if side[0] == "l" else 0.0), 0.0, 1.0)) if ph[0] == "air" else (j.legs[0][1] as Vector3)
		var air_ankle: Vector3 = H + out * tuck.x + Vector3.UP * tuck.y + fwd * tuck.z
		var want := ground_ankle.lerp(air_ankle, air)
		if ph[0] == "air" and air < 0.01:
			continue   # just off the ground / just about to land: the clip's legs
		var E: Vector3 = at.call(e)
		var k := maxf(crouch, air)
		_ik_world(u_, m, e, E.lerp(want, k), H + fwd * 0.6 + Vector3.UP * 0.1, turn, at)
	# TOFU's tail: swishing in the crouch, streaming behind in the air.
	if float(j.swish) > 0.0:
		for b in _ids("tail"):
			if ph[0] == "crouch":
				turn.call(b, Quaternion(Vector3.UP, float(j.swish) / 3.0 * sin(_jump_t * 28.0) * crouch))
			elif ph[0] == "air":
				turn.call(b, Quaternion(left, 0.35 * air))


## The ankle's place along a flight path of [share, Vector3] keys, eased between them.
static func _leg_path(keys: Array, u: float) -> Vector3:
	for i in range(1, keys.size()):
		if u <= float(keys[i][0]):
			var a: float = keys[i - 1][0]
			var t := (u - a) / maxf(float(keys[i][0]) - a, 1e-4)
			return (keys[i - 1][1] as Vector3).lerp(keys[i][1], t * t * (3.0 - 2.0 * t))
	return keys[-1][1]


## Two-bone IK in the world: `u` -> `m` -> `e` so the end reaches `target`, the middle joint
## bending toward `pole`. `turn`/`at`: as in _sit_pose.
func _ik_world(u: int, m: int, e: int, target: Vector3, pole: Vector3, turn: Callable, at: Callable) -> void:
	var S: Vector3 = at.call(u)
	var M: Vector3 = at.call(m)
	var E: Vector3 = at.call(e)
	var l1 := S.distance_to(M)
	var l2 := M.distance_to(E)
	var d := clampf(S.distance_to(target), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var along := (target - S).normalized()
	var side := pole - S
	side = side - along * side.dot(along)
	if side.length() < 1e-5:
		return
	side = side.normalized()
	var a := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var M2 := S + along * a + side * sqrt(maxf(l1 * l1 - a * a, 0.0))
	turn.call(u, _arc((M - S).normalized(), (M2 - S).normalized()))
	var M3: Vector3 = at.call(m)
	var E3: Vector3 = at.call(e)
	turn.call(m, _arc((E3 - M3).normalized(), (S + along * d - M3).normalized()))


## Pulled along, she can't keep up (the player asked): the body goes after the leash hand. The
## spine bends forward, the chest turns so the leash shoulder leads, the free arm swings back for
## balance; the whole body leans forward too (the game sets `lean`). Grows with the leash's pull.
const PULL_BEND := 0.22    ## spine forward, radians in all
const PULL_TWIST := 0.30   ## chest turned to lead with the leash shoulder, radians in all
const PULL_ARM_BACK := 0.45

var _drag_k := 0.0


func _pulled_along(delta: float) -> void:
	_drag_k = lerpf(_drag_k, (1.0 if dragged and hold_target != Vector3.INF and crawl < 0.01 else 0.0) * clampf(_pull, 0.0, 1.0), 1.0 - exp(-3.0 * delta))
	if _drag_k < 0.01:
		return
	var spine := _ids("spine")
	if spine.is_empty():
		return
	# Which way to turn about "up" so the right (leash) shoulder comes forward.
	var right := -_left_char
	var lead := signf(Vector3.UP.cross(right).dot(Vector3.BACK))   # forward is +Z in character space
	var n := float(spine.size())
	for b in spine:
		_pose(b, PULL_BEND * _drag_k / n, lead * PULL_TWIST * _drag_k / n, 0.0)
	_pose(_one("head"), -PULL_BEND * 0.5 * _drag_k, -lead * PULL_TWIST * 0.6 * _drag_k, 0.0)   # eyes stay on TOFU
	_pose(_one("upper_arm_l"), -PULL_ARM_BACK * _drag_k, 0.0, 0.0)


func _reach_for_leash(delta: float) -> void:
	# Slow, eased changes: the arm takes about half a second to come up or settle.
	_hold = move_toward(_hold, 1.0 if hold_target != Vector3.INF and crawl < 0.05 else 0.0, delta * 2.2)   # crawling, both arms pull
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


## The right paw on the second stick: the palm's middle goes to `paw_target` (PawReach already
## stopped it at whatever it meets). Through a quick, well damped spring the wrist is put by
## two-bone IK (the elbow down, out and back), then the hand is turned: in the air along the
## line to the target; on a surface (`paw_normal`) the palm against it and the fingers along it
## (`paw_tan`), curled round what falls away under them (`paw_curl`). Let go, the arm eases back
## to hanging in about 0.4 s. The fingers rest a little curled otherwise (both hands).
const PAW_EASE := 2.5      ## per second, in and out
const PAW_FREQ := 3.0      ## the wrist's spring, Hz (an arm moves, a cursor jumps)
const PAW_LIE := 6.0       ## per second, the hand turning to lie on a surface and back
const WRIST_LIFT := 0.008  ## lying on a surface, the wrist stands this far off it (a real hand's arch)
const FINGERS_REST := 0.35 ## radians the fingers curl at rest

var paw_normal := Vector3.ZERO   ## set by the game: the surface the paw lies on (from it toward the paw); ZERO: none
var paw_tan := Vector3.FORWARD   ## set by the game: the fingers' way along it
var paw_curl := 0.0              ## set by the game: how far the fingers curl round it
var paw_palm := 0.065            ## the palm's middle is this far past the wrist (metres)
var _paw := 0.0
var _lie := 0.0
var _lie_n := Vector3.UP
var _lie_t := Vector3.FORWARD
var _curl := FINGERS_REST
var _paw_point := Vector3.ZERO
var _paw_x := Vector3.ZERO
var _paw_v := Vector3.ZERO
var _paw_ready := false
var _finger_axes := {}           ## bone -> its curl axis (local)


func _paw_reach(delta: float) -> void:
	_paw = move_toward(_paw, 1.0 if paw_target != Vector3.INF and crawl < 0.05 else 0.0, delta * PAW_EASE)
	_lie = move_toward(_lie, 1.0 if paw_normal != Vector3.ZERO and paw_target != Vector3.INF else 0.0, delta * PAW_LIE)
	if paw_normal != Vector3.ZERO:
		_lie_n = paw_normal.normalized()
		_lie_t = paw_tan.normalized()
	var flat := 1.0 - smoothstep(0.0, 1.0, crawl)   # crawling, the paws lie flat on the ground
	var want_curl := lerpf(FINGERS_REST, paw_curl, _lie * _paw) * flat
	_curl = lerpf(_curl, want_curl, 1.0 - exp(-10.0 * delta))
	_curl_fingers("r", _curl)
	_curl_fingers("l", FINGERS_REST * flat)
	var ua := _one("upper_arm_r")
	var fa := _one("forearm_r")
	var hand := _one("hand_r")
	if _paw < 0.001 or ua < 0 or fa < 0 or hand < 0:
		_paw_ready = false
		return
	if paw_target != Vector3.INF:
		_paw_point = paw_target
	var to_sk := skeleton.global_transform.affine_inverse()
	var sk_b := skeleton.global_transform.basis
	var unit := 1.0 / sk_b.get_scale().x   # metres to the rig's units
	var g_ua := skeleton.get_bone_global_pose(ua)
	var g_fa := skeleton.get_bone_global_pose(fa)
	var wr := skeleton.get_bone_global_pose(hand).origin
	# The hand's way: along the line from the shoulder in the air, along the surface on one.
	var goal := to_sk * _paw_point
	var free_dir := (goal - g_ua.origin).normalized()
	var lie_n := (sk_b.inverse() * _lie_n).normalized()
	var lie_t := (sk_b.inverse() * _lie_t).normalized()
	var dir := free_dir.slerp(lie_t, _lie).normalized()
	var wrist_goal := goal - dir * paw_palm * unit + lie_n * WRIST_LIFT * unit * _lie
	if not _paw_ready:
		_paw_x = wr
		_paw_v = Vector3.ZERO
		_paw_ready = true
	# Critically damped (no overshoot into what it met), solved exactly: stable however long
	# the frame (an explicit step blew up on long frames).
	var wk := TAU * PAW_FREQ
	var dx := _paw_x - wrist_goal
	var k := (_paw_v + dx * wk) * delta
	var e := exp(-wk * delta)
	_paw_x = wrist_goal + (dx + k) * e
	_paw_v = (_paw_v - k * wk) * e
	var w := smoothstep(0.0, 1.0, _paw)
	_two_bone(ua, fa, g_ua, g_fa, wr, wr.lerp(_paw_x, w), -_up_sk - _side_sk * 0.6 - _fwd_sk * 0.3)
	# Turn the hand: its length along `dir`; lying on a surface, the palm to it.
	var g_h := skeleton.get_bone_global_pose(hand).basis.orthonormalized()
	var y_now := g_h.y.normalized()
	var palm_now := (g_h * _palm_local(hand, "r")).normalized()
	var palm_want := palm_now.slerp(-lie_n, _lie)
	var from_b := _hand_frame(y_now, palm_now)
	var to_b := _hand_frame(dir, palm_want)
	var q := Quaternion(to_b * from_b.inverse()).normalized()
	_set_global_rot(hand, Quaternion.IDENTITY.slerp(q, w) * g_h.get_rotation_quaternion())


## An orthonormal basis with `y` along `along` and z toward `toward` (made square to it).
static func _hand_frame(along: Vector3, toward: Vector3) -> Basis:
	var y := along.normalized()
	var z := toward - y * toward.dot(y)
	z = z.normalized() if z.length() > 1e-5 else y.cross(Vector3.RIGHT).normalized()
	return Basis(y.cross(z), y, z)


## The way a hand's palm faces, in the hand bone's own frame: inward at rest (toward the body's
## middle: +X for the right hand, -X for the left).
func _palm_local(b: int, s: String) -> Vector3:
	var rest := skeleton.get_bone_global_rest(b).basis.orthonormalized()
	return (rest.inverse() * (_side_sk * (-1.0 if s == "l" else 1.0))).normalized()


## Curls a paw's fingers (and less its thumb) toward the palm, `a` radians (bones "paw_fingers_*",
## "paw_thumb_*": TOFU only; the bunny's fingers are her own).
func _curl_fingers(s: String, a: float) -> void:
	for pair in [["paw_fingers_" + s, 1.0], ["paw_thumb_" + s, 0.6]]:
		var b := _one(pair[0])
		if b < 0:
			continue
		if not _finger_axes.has(b):
			var palm := _palm_local(b, s)
			_finger_axes[b] = Vector3.UP.cross(palm).normalized()
		skeleton.set_bone_pose_rotation(b, skeleton.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(_finger_axes[b], a * float(pair[1]) + (0.1 if pair[1] < 1.0 else 0.0)))


## How far the paw is out: 0 hanging .. 1 reaching.
func paw_out() -> float:
	return _paw


## How far the hand lies on a surface (0..1) and that surface's normal.
func paw_lying() -> float:
	return _lie * _paw


## Two-bone IK in skeleton space: turns `ua` and `fa` so the wrist (now at `wr`) reaches
## `target`, the elbow bending toward `pole`.
func _two_bone(ua: int, fa: int, g_ua: Transform3D, g_fa: Transform3D, wr: Vector3, target: Vector3, pole: Vector3) -> void:
	var sh := g_ua.origin
	var el := g_fa.origin
	var l1 := (el - sh).length()
	var l2 := (wr - el).length()
	var d := clampf((target - sh).length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var u := (target - sh).normalized()
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
	for seg in chain:
		_q[seg] = skeleton.get_bone_pose_rotation(seg)
	_palm_info[s] = [fa, hand, chain, idx, pinky, thumb, out_sk]
	_twist_palm(s)
	_q[fa] = skeleton.get_bone_pose_rotation(fa)
	for seg in chain:
		_q[seg] = skeleton.get_bone_pose_rotation(seg)


var _palm_info := {}   ## side -> [forearm, hand, twist chain, index, pinky, thumb, outward (skeleton space)]


## Twists the forearm (over its twist segments, from their base) so the palm faces the thigh,
## a little to the back. Run after anything that swings the arm, so the chest's turn or the
## swing never leaves the palm facing out.
func _twist_palm(s: String) -> void:
	var info: Array = _palm_info.get(s, [])
	if info.is_empty():
		return
	var fa: int = info[0]
	var hand: int = info[1]
	var chain: Array = info[2]
	for seg in chain:
		if seg != fa:
			skeleton.set_bone_pose_rotation(seg, _q[seg])
	var gp := func(i: int) -> Vector3: return skeleton.get_bone_global_pose(i).origin
	var axis: Vector3 = (gp.call(hand) - gp.call(fa)).normalized()
	var idx: int = info[3]
	var pinky: int = info[4]
	var thumb: int = info[5]
	var out_sk: Vector3 = info[6]
	# Palm normal now, and where it should face.
	var across: Vector3 = gp.call(idx) - gp.call(pinky)
	var normal := across.cross(axis).normalized()
	if normal.dot(gp.call(thumb) - (gp.call(idx) + gp.call(pinky)) * 0.5) < 0.0:
		normal = -normal
	var want := (-out_sk - _fwd_sk * 0.35).normalized().lerp(-_up_sk, smoothstep(0.3, 0.9, crawl))   # crawling: palm down on the ground
	want = (want - axis * want.dot(axis)).normalized()
	var have := (normal - axis * normal.dot(axis)).normalized()
	var angle := atan2(have.cross(want).dot(axis), have.dot(want))
	for seg in chain:
		var g := skeleton.get_bone_global_pose(seg).basis.orthonormalized()
		var turn := Quaternion((g.inverse() * axis).normalized(), angle / chain.size())
		skeleton.set_bone_pose_rotation(seg, skeleton.get_bone_pose_rotation(seg) * turn)


## A woman's walk on top of the clips (the clips are a man's; the player found her walk odd):
## the hips sway (the pelvis moves over the standing leg, its free side drops and swings
## forward with the stepping leg), the steps narrow toward one line, the chest is carried up
## and steady. The legs are turned at the hips so each foot stays where the clip put it (less
## the sway): planted feet do not slide. Less of it in a run. FEM_* set how much.
const FEM_SHIFT := 0.028   ## hips over the standing leg, metres (walking)
const FEM_ROLL := 0.10     ## free side of the pelvis drops, radians
const FEM_YAW := 0.12      ## pelvis turns with the stepping leg, radians
const FEM_NARROW := 0.035  ## each foot nearer the middle line, metres
const FEM_CHEST := 0.07    ## chest carried up, radians

var _feminine := 0.0
var _left_char := Vector3.RIGHT   ## the body's left, character space


func _feminine_walk() -> void:
	var pel := _one("pelvis")
	var spine := _ids("spine")
	var legs := [[_one("thigh_l"), _one("foot_l"), 1.0], [_one("thigh_r"), _one("foot_r"), -1.0]]
	if pel < 0 or spine.is_empty() or legs[0][0] < 0 or legs[1][0] < 0:
		return
	var move := smoothstep(0.05, walk_speed * 0.5, speed)
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var k := _feminine * move * (1.0 - 0.6 * r) * (1.0 - crawl)
	if k <= 0.001:
		return
	var ph := rt.phase * TAU          # 0 = the left foot lands; the left leg stands until 0.5
	var stand := sin(ph)               # +1 mid-stance on the left, -1 on the right
	# Character space -> skeleton space (directions; metres -> skeleton units).
	var to_sk := skeleton.global_transform.basis.inverse() * _body.global_basis
	var left_sk: Vector3 = (to_sk * _left_char)
	var feet := []
	for leg in legs:
		feet.append(skeleton.get_bone_global_pose(leg[1]).origin)
	# The pelvis: its free side drops and swings forward; the chest stays level and steady.
	var spin := Quaternion(_fwd_sk, FEM_ROLL * k * stand) * Quaternion(_up_sk, FEM_YAW * k * stand)
	var first: int = spine[0]
	var keep := skeleton.get_bone_global_pose(first).basis.orthonormalized().get_rotation_quaternion()
	var g_pel := skeleton.get_bone_global_pose(pel).basis.orthonormalized().get_rotation_quaternion()
	_set_global_rot(pel, spin * g_pel)
	_set_global_rot(first, Quaternion(_up_sk, FEM_YAW * k * stand * 0.35) * keep)   # a little of the turn goes up the spine
	# The hips over the standing leg.
	var shift := _left_char * (FEM_SHIFT * k * stand)
	_offset += shift
	var shift_sk: Vector3 = to_sk * shift
	# Each foot back where the clip put it (less the sway), a little nearer the middle line.
	for i in 2:
		var thigh: int = legs[i][0]
		var hip := skeleton.get_bone_global_pose(thigh).origin
		var now := skeleton.get_bone_global_pose(legs[i][1]).origin
		var want: Vector3 = feet[i] - shift_sk - left_sk * (legs[i][2] * FEM_NARROW * k)
		var q := _arc((now - hip).normalized(), (want - hip).normalized())
		var g := skeleton.get_bone_global_pose(thigh).basis.orthonormalized().get_rotation_quaternion()
		_set_global_rot(thigh, q * g)
	# The chest carried up, the head level.
	_pose(spine[spine.size() - 1], -FEM_CHEST * _feminine, 0.0, 0.0)
	_pose(_one("head"), FEM_CHEST * 0.6 * _feminine, 0.0, 0.0)


## Sets a bone's rotation in skeleton space (its children follow).
func _set_global_rot(b: int, q: Quaternion) -> void:
	var par := skeleton.get_bone_parent(b)
	var pr := Quaternion.IDENTITY
	if par >= 0:
		pr = skeleton.get_bone_global_pose(par).basis.orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(b, (pr.inverse() * q).normalized())


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
		_twist_palm(s[0])


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
			_finger_bones.append(b)
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
