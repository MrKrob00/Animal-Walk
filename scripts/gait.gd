class_name Gait
extends RefCounted
## Walk and run without baked clips: turns the leg, arm, tail and ear bones of any
## humanoid skeleton every frame. The step follows the real speed, so feet do not slide.
## Rotations are made about the character's own side axis (its +X) and up axis (+Y),
## converted once into each bone's rest frame, so bone roll and file axes do not matter.

var skeleton: Skeleton3D
var stride := 1.0          ## metres covered by one full cycle (two steps)
var walk_speed := 1.5      ## m/s at which the walk is at full swing
var run_speed := 3.5       ## m/s at which the run is at full swing
var phase := 0.0
var lean := 0.0            ## extra lean, radians: + forward, - backward (being dragged)

var _bones := {}           ## role -> bone index
var _side := {}            ## bone index -> rotation axis in the bone's rest frame (side axis)
var _up := {}              ## bone index -> rotation axis in the bone's rest frame (up axis)
var _rest := {}            ## bone index -> rest rotation (with the base pose folded in)
var _time := 0.0
var _last_sign := 0
var _side_sk := Vector3.RIGHT

const ROLES := ["thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r",
	"upper_arm_l", "forearm_l", "upper_arm_r", "forearm_r"]


## `map`: role -> bone name, plus "tail" and "ears": Array of names.
## `body` is the node that faces the character's forward (+Z) direction.
func setup(skel: Skeleton3D, map: Dictionary, body: Node3D) -> void:
	skeleton = skel
	var rel := body.global_transform.basis.inverse() * skel.global_transform.basis
	var side_sk := (rel.inverse() * Vector3.RIGHT).normalized()
	_side_sk = side_sk
	var up_sk := (rel.inverse() * Vector3.UP).normalized()
	for role in map:
		if not (map[role] is Array or map[role] is String):
			continue
		var names: Array = map[role] if map[role] is Array else [map[role]]
		var ids := []
		for n in names:
			var b := find_bone(skel, n)
			if b < 0:
				push_warning("Gait: no bone %s" % n)
				continue
			ids.append(b)
			var g := skel.get_bone_global_rest(b).basis
			_side[b] = (g.inverse() * side_sk).normalized()
			_up[b] = (g.inverse() * up_sk).normalized()
			_rest[b] = skel.get_bone_rest(b).basis.get_rotation_quaternion()
		_bones[role] = ids if map[role] is Array else (ids[0] if ids.size() > 0 else -1)
	if map.get("arms_down", false):
		var fwd_sk := (rel.inverse() * Vector3.BACK).normalized()
		for sd in [["l", 1.0], ["r", -1.0]]:
			_arm_down(sd[0], side_sk * sd[1], up_sk, fwd_sk)


## Base pose for models whose rest pose has the arms up: hang each arm down at the side,
## elbow a little bent. Folded into the rest rotation, so the swing is added on top.
func _arm_down(s: String, out_sk: Vector3, up_sk: Vector3, fwd_sk: Vector3) -> void:
	var ua: int = _bones.get("upper_arm_" + s, -1)
	var fa: int = _bones.get("forearm_" + s, -1)
	var hand: int = _bones.get("hand_" + s, -1)
	if ua < 0 or fa < 0 or hand < 0:
		return
	var p_ua := skeleton.get_bone_global_rest(ua).origin
	var p_fa := skeleton.get_bone_global_rest(fa).origin
	var p_h := skeleton.get_bone_global_rest(hand).origin
	var g_ua := skeleton.get_bone_global_rest(ua).basis.orthonormalized()
	var g_fa := skeleton.get_bone_global_rest(fa).basis.orthonormalized()
	# Upper arm: from its rest direction to down and slightly out.
	var q1 := _arc((p_fa - p_ua).normalized(), (-up_sk + out_sk * 0.18).normalized())
	_rest[ua] = _rest[ua] * Quaternion(g_ua.inverse() * Basis(q1) * g_ua)
	# Forearm: its direction after the upper arm moved, to down and a little forward.
	var q2 := _arc(q1 * (p_h - p_fa).normalized(), (-up_sk + fwd_sk * 0.12 + out_sk * 0.05).normalized())
	var g_fa_now := Basis(q1) * g_fa
	_rest[fa] = _rest[fa] * Quaternion(g_fa_now.inverse() * Basis(q2) * g_fa_now)
	# The swing axes now live in the moved frames.
	_side[ua] = (Basis(q1) * g_ua).inverse() * (_side_sk)
	_side[fa] = (Basis(q2) * g_fa_now).inverse() * (_side_sk)
	_side[ua] = _side[ua].normalized()
	_side[fa] = _side[fa].normalized()


## Shortest rotation taking direction a to direction b.
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Quaternion(c.normalized(), atan2(c.length(), d))


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


static func _escape(s: String) -> String:
	for c in ["\\", ".", "+", "*", "?", "(", ")", "[", "]", "{", "}", "^", "$", "|"]:
		s = s.replace(c, "\\" + c)
	return s


func has_role(role: String) -> bool:
	return _bones.has(role) and (_bones[role] is Array or _bones[role] >= 0)


## Advances the cycle by the distance walked and poses the bones.
## Returns +1 / -1 when the left / right foot lands this frame, else 0.
func update(delta: float, speed: float) -> int:
	_time += delta
	phase = fmod(phase + speed / stride * TAU * delta, TAU)
	var w := clampf(speed / walk_speed, 0.0, 1.0)
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var s := sin(phase)
	var thigh := lerpf(0.42, 0.78, r) * w
	var knee := lerpf(0.55, 1.25, r) * w
	var arm := lerpf(0.32, 0.55, r) * w
	var elbow := 0.05 + lerpf(0.12, 1.0, r) * w
	for side in [["l", 0.0], ["r", PI]]:
		var ph: float = phase + side[1]
		_turn("thigh_" + side[0], -thigh * sin(ph))
		_turn("shin_" + side[0], (0.06 + knee * maxf(0.0, cos(ph))) * maxf(w, 0.0))
		_turn("foot_" + side[0], -0.3 * w * sin(ph))
		_turn("upper_arm_" + side[0], arm * sin(ph) + 0.03 * sin(_time * 1.6))
		_turn("forearm_" + side[0], -elbow)
	if has_role("tail"):
		var k := 0
		for b in _bones["tail"]:
			var sway := sin(phase - k * 0.7) * 0.22 * w + sin(_time * 1.4 - k * 0.6) * 0.12 * (1.0 - w)
			_pose(b, Quaternion(_up[b], sway) * Quaternion(_side[b], -0.08 * w))
			k += 1
	if has_role("ears"):
		for b in _bones["ears"]:
			_pose(b, Quaternion(_side[b], sin(phase * 2.0) * 0.12 * w + sin(_time * 2.1) * 0.03))
	var sign := 1 if s > 0.0 else -1
	var landed := 0
	if w > 0.15 and sign != _last_sign:
		landed = sign
	_last_sign = sign
	return landed


## Vertical bob of the whole body, metres per metre of height: lowest when the feet land.
func bob(speed: float) -> float:
	var w := clampf(speed / walk_speed, 0.0, 1.0)
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	return lerpf(0.018, 0.045, r) * w * (1.0 - absf(sin(phase)))


## Forward lean of the whole body (radians), from the gait plus any extra lean.
func body_lean(speed: float) -> float:
	var r := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	return lerpf(0.03, 0.14, r) * clampf(speed / walk_speed, 0.0, 1.0) + lean


func foot_position(left: bool) -> Vector3:
	var b: int = _bones.get("foot_l" if left else "foot_r", -1)
	if b < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin


func _turn(role: String, angle: float) -> void:
	var b: int = _bones.get(role, -1)
	if b >= 0:
		_pose(b, Quaternion(_side[b], angle))


func _pose(b: int, extra: Quaternion) -> void:
	skeleton.set_bone_pose_rotation(b, _rest[b] * extra)
