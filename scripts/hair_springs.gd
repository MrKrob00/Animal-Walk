class_name HairSprings
extends RefCounted
## Her hair's chains on springs (the VRM spring-bone way): each joint after a chain's root keeps
## its own speed (verlet, with drag), is pulled back toward where the hairdo has it (stiffness),
## sags a little (gravity), keeps its bone's length, slides round spheres on the head, face, neck
## and shoulders, and never turns further than MAX_ANGLE from the hairdo's own line, so a strand
## can't flip over. All in world metres: Godot's SpringBoneSimulator3D misbehaves on a scaled
## skeleton (ours is scaled to her height): moving, its strands swung 30 cm.

const STIFFNESS := 9.0     ## per second: how fast a joint goes back to the hairdo's place
const DRAG := 0.35         ## share of its speed a joint loses each 1/60 s
const GRAVITY := 0.6       ## m/s^2 of sag (small: a bob keeps its shape)
const MAX_ANGLE := deg_to_rad(40.0)
const JOINT_R := 0.012     ## metres: a hair joint's own thickness against the spheres
const STEP := 1.0 / 60.0
const INERTIA := 0.25      ## share of the body's own travel the hair feels (UniVRM's "center"): with
                           ## all of it, drag against the world held a walking bob 6 cm off its shape

var skel: Skeleton3D
var chains := []    ## [[bone ids root .. tip]]
var spheres := []   ## [bone, offset (bone frame, metres), radius]
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
	while x >= 0 and skel.get_bone_name(x).begins_with("hair_"):
		t = skel.get_bone_rest(x) * t
		x = skel.get_bone_parent(x)
	return (skel.get_bone_global_pose(x) if x >= 0 else Transform3D.IDENTITY) * t


## Steps the springs and poses the hair bones. `fix`: the body's motion eased between physics
## ticks (Gait.motion_fix), so stepped motion does not hit the hair like a blow. `root`: where
## the body is (the hair is carried along with all but INERTIA of its travel).
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
	var carry := (root - _root) * (1.0 - INERTIA)
	_root = root
	for c in _pos.size():
		for i in _pos[c].size():
			_pos[c][i] += carry
			_prev[c][i] += carry
	_acc = minf(_acc + delta, STEP * 4.0)
	var balls := _world_spheres(fix)
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
				var v: Vector3 = (p - prev[i]) * (1.0 - DRAG)
				prev[i] = p
				p += v + (want[i] - p) * (1.0 - exp(-STIFFNESS * STEP)) + Vector3.DOWN * GRAVITY * STEP * STEP
				# The bone's length from its parent joint, no further than MAX_ANGLE off the hairdo.
				var par: Vector3 = row[i - 1]
				var length: float = (want[i] - want[i - 1]).length()
				var d := p - par
				var rest_d: Vector3 = (want[i] - want[i - 1]).normalized()
				if d.length() < 1e-6:
					d = rest_d
				d = d.normalized()
				var ang := d.angle_to(rest_d)
				if ang > MAX_ANGLE:
					d = rest_d.slerp(d, MAX_ANGLE / ang).normalized()
				p = par + d * length
				for s in balls:
					var off: Vector3 = p - s[0]
					var r: float = s[1] + JOINT_R
					if off.length() < r:
						p = s[0] + (off.normalized() if off.length() > 1e-6 else rest_d) * r
						p = par + (p - par).normalized() * length
				row[i] = p
	_pose(tg)


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
