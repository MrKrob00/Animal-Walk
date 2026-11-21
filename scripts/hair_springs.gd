class_name HairSprings
extends RefCounted
## Her hair's chains on springs (the VRM spring-bone way): each joint after a chain's root keeps
## its own speed (verlet, with drag), is pulled back toward where the hairdo has it (stiffness),
## sags a little (gravity), keeps its bone's length, slides round spheres on the head, face, neck
## and shoulders, and never turns further than max_angle from the hairdo's own line, so a strand
## can't flip over. All in world metres: Godot's SpringBoneSimulator3D misbehaves on a scaled
## skeleton (ours is scaled to her height): moving, its strands swung 30 cm.

const STEP := 1.0 / 60.0

# The hair's numbers (a skirt sets its own: SkirtRig).
var stiffness := 9.0       ## per second: how fast a joint goes back to the hairdo's place
var drag := 0.35           ## share of its speed a joint loses each 1/60 s
var gravity := 0.6         ## m/s^2 of sag (small: a bob keeps its shape)
var max_angle := deg_to_rad(40.0)
var joint_r := 0.012       ## metres: a hair joint's own thickness against the spheres
var inertia := 0.25        ## share of the body's own travel the hair feels (UniVRM's "center"): with
                           ## all of it, drag against the world held a walking bob 6 cm off its shape

var skel: Skeleton3D
var chains := []    ## [[bone ids root .. tip]]
var spheres := []   ## [bone, offset (bone frame, metres), radius]
var capsules := []  ## [bone a, bone b, radius at a, radius at b (metres)]: from one bone's head to the other's (legs)
var _ours := {}     ## the simulated bones
var out_from := -1  ## a skirt: its middle's bone (the pelvis); out of a capsule, a joint goes outward
                    ## from it (over the leg, not between the legs)
var _pos := []      ## per chain, per joint: world position now
var _prev := []
var _ready := false
var _acc := 0.0
var _root := Vector3.INF   ## where the body was last step


func _init(s: Skeleton3D, c: Array, sph: Array) -> void:
	skel = s
	chains = c
	for x in sph:
		spheres.append([Gait.find_bone(s, x[0]), x[1], float(x[2])])
	for ch in c:
		for b in ch:
			_ours[b] = true


## Capsules the joints slide round: [[bone a, bone b, radius at a, radius at b (metres; one
## radius: the same at both), and to the sides at a and b (`side`: oval, a thigh is thinner that
## way)]], narrowing from one end to the other (a thigh toward the knee).
func set_capsules(caps: Array) -> void:
	capsules = []
	for x in caps:
		var ra := float(x[2])
		var rb := float(x[3] if x.size() > 3 else x[2])
		capsules.append([Gait.find_bone(skel, x[0]), Gait.find_bone(skel, x[1]), ra, rb, float(x[4] if x.size() > 4 else ra), float(x[5] if x.size() > 5 else rb)])


## Where the hairdo puts every joint now (riding rigidly on the head's pose).
func _targets() -> Array:
	var out := []
	var g := skel.global_transform
	for ch in chains:
		var row := []
		for b in ch:
			row.append(g * _rest_global_on_pose(b).origin)
		out.append(row)
	return out


## A hair bone's global transform with every hair bone at rest, riding on its (posed) head.
func _rest_global_on_pose(b: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x := b
	while x >= 0 and _ours.has(x):
		t = skel.get_bone_rest(x) * t
		x = skel.get_bone_parent(x)
	return (skel.get_bone_global_pose(x) if x >= 0 else Transform3D.IDENTITY) * t


## Steps the springs and poses the hair bones. `fix`: the body's motion eased between physics
## ticks (Gait.motion_fix), so stepped motion does not hit the hair like a blow. `root`: where
## the body is (the hair is carried along with all but `inertia` of its travel).
func step(delta: float, fix: Vector3, root: Vector3) -> void:
	var tg := _targets()
	for row in tg:
		for i in row.size():
			row[i] += fix
	root += fix
	if not _ready:
		_pos = tg.duplicate(true)
		_prev = tg.duplicate(true)
		_ready = true
		_root = root
	var carry := (root - _root) * (1.0 - inertia)
	_root = root
	for c in _pos.size():
		for i in _pos[c].size():
			_pos[c][i] += carry
			_prev[c][i] += carry
	_acc = minf(_acc + delta, STEP * 4.0)
	var balls := _world_spheres(fix)
	var sticks := _world_capsules(fix)
	if out_from >= 0:
		_mid = skel.global_transform * skel.get_bone_global_pose(out_from).origin + fix
		_side = (skel.global_transform.basis * skel.get_bone_global_pose(out_from).basis.x).normalized()
	var keep := 1.0 - exp(-stiffness * STEP)
	while _acc >= STEP:
		_acc -= STEP
		for c in chains.size():
			var row: Array = _pos[c]
			var prev: Array = _prev[c]
			var want: Array = tg[c]
			row[0] = want[0]
			prev[0] = want[0]
			for i in range(1, row.size()):
				var p: Vector3 = row[i]
				var v: Vector3 = (p - prev[i]) * (1.0 - drag)
				prev[i] = p
				p += v + (want[i] - p) * keep + Vector3.DOWN * gravity * STEP * STEP
				# The bone's length from its parent joint, no further than max_angle off the hairdo.
				var par: Vector3 = row[i - 1]
				var length: float = (want[i] - want[i - 1]).length()
				var d := p - par
				var rest_d: Vector3 = (want[i] - want[i - 1]).normalized()
				if d.length() < 1e-6:
					d = rest_d
				d = d.normalized()
				var ang := d.angle_to(rest_d)
				if ang > max_angle:
					d = rest_d.slerp(d, max_angle / ang).normalized()
				p = par + d * length
				for s in balls:
					var off: Vector3 = p - s[0]
					var r: float = s[1] + joint_r
					if off.length() < r:
						p = s[0] + (off.normalized() if off.length() > 1e-6 else rest_d) * r
						p = par + (p - par).normalized() * length
				var away := Vector3.ZERO
				if out_from >= 0:
					away = want[i] - _mid
					away.y = 0.0
					# Outward and up: square to a leg hanging down that is outward, to a thigh
					# raised forward it is over its top (cloth drapes over a knee, not under it).
					away = (away.normalized() + Vector3.UP) if away.length() > 1e-5 else Vector3.ZERO
				for s in sticks:
					p = _out_of_capsule(p, s, par, length, away)
				row[i] = p
	_pose(tg)


## Pushes a joint at `p` out of capsule `s` [a, b, r] (world), keeping its bone's length from `par`
## (a few passes: keeping the length can bring it back in a little). `away`: the outward way (a
## skirt's: from its middle) the joint leaves by, whichever side of the leg it was caught on.
var _mid := Vector3.ZERO
var _side := Vector3.ZERO   ## a skirt: her side (world), where a thigh capsule is thinner

func _out_of_capsule(p: Vector3, s: Array, par: Vector3, length: float, away := Vector3.ZERO) -> Vector3:
	var a: Vector3 = s[0]
	var ab: Vector3 = s[1] - a
	for k in 3:
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var q := a + ab * t
		var off := p - q
		var d := off.length()
		var r: float = lerpf(s[2], s[3], t)
		if _side != Vector3.ZERO and d > 1e-6:
			var sd := _side - ab.normalized() * _side.dot(ab.normalized())
			var sn := (off / d).dot(sd.normalized()) if sd.length() > 1e-4 else 0.0
			var rs: float = lerpf(s[4], s[5], t)
			r = 1.0 / sqrt((1.0 - sn * sn) / (r * r) + sn * sn / (rs * rs))   # round an oval
		r += joint_r
		if d >= r - 1e-5:
			break
		var n := off / d if d > 1e-6 else (p - par).normalized()
		if away != Vector3.ZERO:
			var ax := ab.normalized()
			var o := away - ax * away.dot(ax)   # outward, square to the leg
			if o.length() > 0.2:
				n = (n * maxf(n.dot(o.normalized()), 0.0) + o.normalized()).normalized()
		p = q + n * r
		p = par + (p - par).normalized() * length
	return p


func _world_capsules(fix: Vector3) -> Array:
	var out := []
	var g := skel.global_transform
	for s in capsules:
		if s[0] < 0 or s[1] < 0:
			continue
		out.append([g * skel.get_bone_global_pose(s[0]).origin + fix, g * skel.get_bone_global_pose(s[1]).origin + fix, float(s[2]), float(s[3]), float(s[4]), float(s[5])])
	return out


func _world_spheres(fix: Vector3) -> Array:
	var out := []
	var g := skel.global_transform
	for s in spheres:
		if s[0] < 0:
			continue
		var bg := g * skel.get_bone_global_pose(s[0])
		out.append([bg.origin + bg.basis.orthonormalized() * (s[1] as Vector3) + fix, float(s[2])])
	return out


## Turns each hair bone so it points at its simulated child.
func _pose(tg: Array) -> void:
	var g_rot := skel.global_transform.basis.orthonormalized().get_rotation_quaternion()
	for c in chains.size():
		var ch: Array = chains[c]
		for i in ch.size() - 1:
			var b: int = ch[i]
			var want_dir: Vector3 = (tg[c][i + 1] - tg[c][i]).normalized()
			var sim_dir: Vector3 = (_pos[c][i + 1] - _pos[c][i]).normalized()
			var turn := Gait._arc(want_dir, sim_dir)   # world turn from the hairdo to now
			var par := skel.get_bone_parent(b)
			var par_rot := skel.get_bone_global_pose(par).basis.orthonormalized().get_rotation_quaternion()
			var rest_global := _rest_global_on_pose(b).basis.orthonormalized().get_rotation_quaternion()   # the hairdo's, not its turned parent's
			var now := (g_rot.inverse() * turn * g_rot) * rest_global
			skel.set_bone_pose_rotation(b, (par_rot.inverse() * now).normalized())


## Lays the hair at rest again (after a teleport).
func reset() -> void:
	_ready = false
