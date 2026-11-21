extends SceneTree
## Army crawl ("по-пластунски", the player chose it; no free clip has one), posed on the clip
## library's own skeleton so both characters get it through the same retarget:
##   Crawl_Fwd  - lying on the belly, the upper body on the forearms (the chest clear of the
##                ground), one forearm reaching forward while the opposite knee draws up to the
##                side, then pulling and pushing the body on; the other pair follows half a cycle
##                later. The head is up, looking ahead; hips and chest roll a little with the pull.
##   Crawl_Idle - lying still on the forearms, breathing.
## Limbs are placed by targets on the ground (two-bone IK). Writes res://assets/anim/crawl.res.
##   godot --headless --path . --script tools/make_crawl.gd

const OUT := "res://assets/anim/crawl.res"
const CYCLE := 1.7          ## seconds per full crawl cycle (both arms once)
const FRAMES := 32
const STRIDE := 0.64        ## metres the body moves per cycle (clip's own size): each forearm pulls 0.32 m
const HIPS_Y := 0.16        ## hips above the ground, lying
const ARCH := [0.10, 0.16, 0.18]   ## spine.001-.003 bent up (chest on the forearms), radians
const HEAD_UP := [0.45, 0.5]       ## neck, head lifted to look ahead
const HIP_ROLL := 0.22      ## radians the pelvis rolls: the side whose knee draws up lifts, the weight
                            ## goes onto the other hip (the player asked to study the hips: 0.07, and a
                            ## quarter cycle late, read as stiff)
const CHEST_KEEP := 0.6     ## share of that roll the ribcage turns back (the shoulders stay level)

var sk: Skeleton3D
var up := Vector3.UP
var fwd := Vector3.BACK     ## +Z
var left := Vector3.RIGHT   ## +X


var to_w := Transform3D.IDENTITY   ## skeleton space -> world (Y up, +Z forward, metres)


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: Node = load(ClipSource.PATH).instantiate()
	root.add_child(scene)
	await process_frame
	sk = scene.find_children("*", "Skeleton3D", true, false)[0]
	to_w = sk.global_transform
	var lib := AnimationLibrary.new()
	lib.add_animation("Crawl_Fwd", _record(func(p: float) -> void: _pose(p, 1.0), CYCLE, FRAMES))
	lib.add_animation("Crawl_Idle", _record(func(p: float) -> void: _pose(0.0, 0.0, p), 3.0, 12))
	var err := ResourceSaver.save(lib, OUT)
	print("wrote ", OUT, " err ", err)
	quit()


func _b(n: String) -> int:
	return sk.find_bone(n)


## A bone's position in the world.
func _at(n: String) -> Vector3:
	return to_w * sk.get_bone_global_pose(_b(n)).origin


## A bone's rotation in skeleton space.
func _rot(b: int) -> Quaternion:
	return sk.get_bone_global_pose(b).basis.orthonormalized().get_rotation_quaternion()


func _set_rot(b: int, q: Quaternion) -> void:
	var p := sk.get_bone_parent(b)
	var pr := Quaternion.IDENTITY if p < 0 else _rot(p)
	sk.set_bone_pose_rotation(b, (pr.inverse() * q).normalized())


## Turns bone `b` (and all it carries) by `q`, a turn in the world.
func _turn(b: int, q: Quaternion) -> void:
	var w := to_w.basis.orthonormalized().get_rotation_quaternion()
	_set_rot(b, (w.inverse() * q * w) * _rot(b))


## Turns bone `b` so the line from it to `child` points along `want` (world).
func _aim(b: int, child: int, want: Vector3) -> void:
	var now := to_w * sk.get_bone_global_pose(child).origin - to_w * sk.get_bone_global_pose(b).origin
	if now.length() > 1e-6 and want.length() > 1e-6:
		_turn(b, _arc(now.normalized(), want.normalized()))


## Two-bone reach: `upper` -> `lower` -> `end`, the end at `target`, the middle joint toward `pole`.
func _ik(upper: String, lower: String, end: String, target: Vector3, pole: Vector3) -> void:
	var s := _at(upper)
	var l1 := s.distance_to(_at(lower))
	var l2 := _at(lower).distance_to(_at(end))
	var d := clampf(s.distance_to(target), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var along := (target - s).normalized()
	var side := pole - s
	side = (side - along * side.dot(along)).normalized()
	var a := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var mid := s + along * a + side * sqrt(maxf(l1 * l1 - a * a, 0.0))
	_aim(_b(upper), _b(lower), mid - s)
	_aim(_b(lower), _b(end), target - _at(lower))


## 0..1 smooth step there and back: the limb's stance (on the ground, sliding back as the body
## moves on) for `stance` of the cycle, then its swing (lifted, forward).
static func _cycle(p: float, stance: float) -> Array:
	p = fposmod(p, 1.0)
	if p < stance:
		var t := p / stance
		return [1.0 - t, 0.0]                               # 1 = forward .. 0 = back, on the ground
	var t := (p - stance) / (1.0 - stance)
	var e := t * t * (3.0 - 2.0 * t)
	return [e, sin(t * PI)]                                 # back -> forward, lifted


func _pose(p: float, move: float, breath := 0.0) -> void:
	sk.reset_bone_poses()
	# Lying face down, along +Z: tip the hips forward a quarter turn and set them low.
	var hips := _b("DEF-hips")
	var prone := Quaternion(left, PI * 0.5)
	# The right knee is drawn up furthest at p = 0, the left at p = 0.5: that side's hip lifts.
	var roll := -HIP_ROLL * move * cos(p * TAU)
	_set_rot(hips, Quaternion(fwd, roll) * prone * _rot(hips))
	var par := sk.get_bone_parent(hips)
	var to_par := (to_w * (Transform3D.IDENTITY if par < 0 else sk.get_bone_global_pose(par))).affine_inverse()
	sk.set_bone_pose_position(hips, to_par * Vector3(0.0, HIPS_Y + 0.004 * sin(breath * TAU), 0.0))
	# The spine arches up onto the forearms; the chest turns a little toward the reaching arm.
	var spine := ["DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]
	for k in spine.size():
		var b := _b(spine[k])
		_turn(b, Quaternion(left, -float(ARCH[k]) - 0.01 * sin(breath * TAU)))
		_turn(b, Quaternion(up, 0.05 * move * sin(p * TAU)))
		if k == 0:
			_turn(b, Quaternion(fwd, -roll * CHEST_KEEP))   # the ribcage turns most of the hips' roll back
	_turn(_b("DEF-neck"), Quaternion(left, -float(HEAD_UP[0])))
	_turn(_b("DEF-head"), Quaternion(left, -float(HEAD_UP[1])))
	# Arms: the forearm lies on the ground, the hand ahead of the elbow, a little inward.
	for s in [["L", 1.0, 0.0], ["R", -1.0, 0.5]]:
		var c := _cycle(p + s[2], 0.6) if move > 0.0 else [0.55, 0.0]
		var f: float = c[0]
		var lift: float = c[1] * 0.07 * move
		var sh := _at("DEF-upper_arm." + s[0])
		var out: Vector3 = left * s[1]
		var elbow := Vector3(sh.x, 0.0, sh.z) + out * 0.17 + fwd * lerpf(-0.14, 0.18, f) + up * (0.05 + lift)
		var hand := elbow + fwd * 0.24 - out * 0.08 + up * (-0.02 + lift * 0.5)
		_ik("DEF-upper_arm." + s[0], "DEF-forearm." + s[0], "DEF-hand." + s[0], hand, elbow + out * 0.3 - up * 0.1)
		_aim(_b("DEF-hand." + s[0]), _b("DEF-f_middle.01." + s[0]), hand - _at("DEF-forearm." + s[0]))
	# Legs: the knee opposite the reaching arm draws up to the side; the other lies stretched back.
	for s in [["L", 1.0, 0.5], ["R", -1.0, 0.0]]:
		var c := _cycle(p + s[2], 0.6) if move > 0.0 else [0.2, 0.0]
		var f: float = c[0]        # 1 = drawn up, 0 = stretched back
		var lift: float = c[1] * 0.05 * move
		var hip := _at("DEF-thigh." + s[0])
		var out: Vector3 = left * s[1]
		var base := Vector3(hip.x, 0.0, hip.z)
		# Drawn up, the thigh lies on its inner side: knee and foot low by the ground.
		var knee := base + out * lerpf(0.06, 0.32, f) + fwd * lerpf(-0.42, 0.02, f) + up * (lerpf(0.07, 0.045, f) + lift)
		var foot := base + out * lerpf(0.07, 0.22, f) + fwd * lerpf(-0.84, -0.36, f) + up * (lerpf(0.09, 0.06, f) + lift)
		_ik("DEF-thigh." + s[0], "DEF-shin." + s[0], "DEF-foot." + s[0], foot, knee + up * 0.05)
		# The foot: toes back and down when stretched, on its inner side when drawn up.
		var toe_dir := (-fwd * 0.9 - up * 0.3).lerp(-fwd * 0.4 - out * 0.7 - up * 0.2, f)   # paws nearly flat, not dug in
		_aim(_b("DEF-foot." + s[0]), _b("DEF-toe." + s[0]), toe_dir)


## Samples `pose(t)` (t 0..1) into a looping animation of local bone rotations (and the hips' position).
func _record(pose: Callable, length: float, frames: int) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	var tracks := {}
	var hips := _b("DEF-hips")
	for i in sk.get_bone_count():
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("Skeleton3D:" + sk.get_bone_name(i)))
		tracks[i] = t
	var tp := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(tp, NodePath("Skeleton3D:" + sk.get_bone_name(hips)))
	for k in frames + 1:
		var u := float(k % frames) / frames
		pose.call(u)
		var time := length * float(k) / frames
		for i in sk.get_bone_count():
			anim.rotation_track_insert_key(tracks[i], time, sk.get_bone_pose_rotation(i))
		anim.position_track_insert_key(tp, time, sk.get_bone_pose_position(hips))
	return anim


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Quaternion(c.normalized(), atan2(c.length(), d))
