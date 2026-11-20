extends SceneTree
## Chobby Bun in a T-pose with a clean skeleton (the player asked: her bones were poor).
## The Sketchfab file keeps rigify's 658 bones in a V-sign rest; only 94 deform bones carry
## weights. This joins those (and the fingertip "_end" bones) into one clean hierarchy, poses
## them into a T-pose (pelvis and shoulders level, arms straight out, palms down, elbows back,
## fingers straight along the palm, legs straight down, feet flat and forward), bakes the
## meshes in that pose and writes a model whose rest IS the T-pose.
##   godot --headless --path . --script tools/tpose_bunny.gd -- [preview.png prefix]
## Writes res://assets/chobby_tpose.glb.

const SRC := "res://assets/free_download_-_chobby_bun.glb"
const OUT := "res://assets/chobby_tpose.glb"

var sk: Skeleton3D
var keep := {}            ## bone index -> true
var up := Vector3.UP      ## character axes in skeleton space
var fwd := Vector3.BACK
var left := Vector3.RIGHT
var place := Transform3D.IDENTITY   ## skeleton space -> the new model's space (Y up, about metres)
var place_rot := Basis()


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: Node3D = load(SRC).instantiate()
	root.add_child(scene)
	await process_frame
	sk = scene.find_children("*", "Skeleton3D", true, false)[0]
	var meshes: Array[MeshInstance3D] = []
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.skin != null and mi.name != "Icosphere":
			meshes.append(mi)
	# Her top and shorts follow all the skin under them while the arms go up (or the raised
	# arms tear the top off her back and the skin of her shoulder blades comes through it).
	var c: Dictionary = Actor.BUNNY.cloth
	var body_mi: MeshInstance3D = scene.find_child(c.body, true, false)
	for n in c.items:
		SkinFit.follow_body(body_mi, scene.find_child(n, true, false))
	_body_mi = body_mi
	_pick_bones(meshes)
	_join()
	_axes()
	# The new model: Y up like the old one's skeleton placed it, scaled to about 1.6 m.
	place_rot = sk.global_transform.basis.orthonormalized()
	var tall: float = (_at("DEF-head") - _at("DEF-foot.L")).dot(up) * 1.1
	place = Transform3D(place_rot.scaled(Vector3.ONE * (1.6 / tall)), Vector3.ZERO)
	_pose_t()
	var baked := {}
	for m in meshes:
		baked[m.name] = _bake(m)
	var out := _build(meshes, baked)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(out, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT, " err ", err, " bones ", out.get_child(0).get_bone_count())
	quit()


## The bones that carry weight, plus their fingertip ends.
func _pick_bones(meshes: Array[MeshInstance3D]) -> void:
	for m in meshes:
		for sf in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(sf)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for i in bones.size():
				if w[i] > 0.0:
					keep[_bind_bone(m.skin, bones[i])] = true
	for i in sk.get_bone_count():
		var n := _clean(sk.get_bone_name(i))
		if n.ends_with("_end") and (n.begins_with("DEF-f_") or n.begins_with("DEF-thumb")):
			keep[i] = true


func _bind_bone(skin: Skin, bind: int) -> int:
	var b := skin.get_bind_bone(bind)
	return b if b >= 0 else sk.find_bone(skin.get_bind_name(bind))


## "DEF-thigh.L_0255" -> "DEF-thigh.L"
static func _clean(n: String) -> String:
	var at := n.rfind("_")
	if at > 0 and n.substr(at + 1).is_valid_int():
		return n.substr(0, at)
	return n


func _bone(n: String) -> int:
	for i in sk.get_bone_count():
		if _clean(sk.get_bone_name(i)) == n:
			return i
	return -1


## One hierarchy of kept bones: each hangs from the nearest kept ancestor, or from the DEF bone
## named like a helper ancestor (ORG-hand.L -> DEF-hand.L), or as the game's "reparent" says.
func _join() -> void:
	var map: Dictionary = Actor.BUNNY.bones.reparent
	var order := []
	for i in sk.get_bone_count():
		order.append(i)
	for i in order:
		if not keep.has(i):
			continue
		var n := _clean(sk.get_bone_name(i))
		var to := -1
		if map.has(n):
			to = _bone(map[n])
		else:
			var a := sk.get_bone_parent(i)
			while a >= 0 and to < 0:
				if keep.has(a):
					to = a
				else:
					var an := _clean(sk.get_bone_name(a))
					for pre in ["ORG-", "MCH-", "DEF-"]:
						if an.begins_with(pre):
							var d := _bone("DEF-" + an.substr(pre.length()))
							if d >= 0 and keep.has(d) and d != i:
								to = d
					a = sk.get_bone_parent(a)
		if to < 0 and n != "DEF-spine":
			to = _bone("DEF-spine")
		if to >= 0 and to != sk.get_bone_parent(i):
			Gait.reparent_bone(sk, sk.get_bone_name(i), sk.get_bone_name(to))
	for i in sk.get_bone_count():
		sk.set_bone_pose(i, sk.get_bone_rest(i))


func _axes() -> void:
	var inv := sk.global_transform.basis.inverse()
	up = (inv * Vector3.UP).normalized()
	fwd = (inv * Vector3.BACK).normalized()
	left = (_at("DEF-thigh.L") - _at("DEF-thigh.R"))
	left = (left - up * left.dot(up)).normalized()
	fwd = up.cross(left).normalized() if up.cross(left).dot(fwd) > 0.0 else -up.cross(left).normalized()


func _at(n: String) -> Vector3:
	return sk.get_bone_global_pose(_bone(n)).origin


func _rot(b: int) -> Quaternion:
	return sk.get_bone_global_pose(b).basis.orthonormalized().get_rotation_quaternion()


func _set_rot(b: int, q: Quaternion) -> void:
	var p := sk.get_bone_parent(b)
	var pr := Quaternion.IDENTITY if p < 0 else _rot(p)
	sk.set_bone_pose_rotation(b, (pr.inverse() * q).normalized())


## Turns bone `b` (with all it carries) by `q`, in skeleton space.
func _turn(b: int, q: Quaternion) -> void:
	_set_rot(b, q * _rot(b))


## Turns bone `b` so the line from it to `child` points along `want`.
func _aim(b: int, child: int, want: Vector3) -> void:
	var now := sk.get_bone_global_pose(child).origin - sk.get_bone_global_pose(b).origin
	if now.length() < 1e-6:
		return
	_turn(b, _arc(now.normalized(), want.normalized()))


func _pose_t() -> void:
	var feet_rest := {}
	for s in ["L", "R"]:
		for n in ["DEF-foot.", "DEF-toe."]:
			feet_rest[n + s] = _rot(_bone(n + s))
	# Pelvis level and square (its lean as modelled).
	var hips := _at("DEF-thigh.L") - _at("DEF-thigh.R")
	_turn(_bone("DEF-spine"), _arc(hips.normalized(), left))
	# The spine and neck straight up seen from the front (her rest bends them sideways: the
	# chest sat 4 cm to her right); their lean forward and back stays as modelled.
	var chain := ["DEF-spine.001", "DEF-spine.002", "DEF-spine.003", "DEF-neck", "DEF-head"]
	for k in chain.size() - 1:
		var d := _at(chain[k + 1]) - _at(chain[k])
		_aim(_bone(chain[k]), _bone(chain[k + 1]), d - left * d.dot(left))
	# Chest: shoulders level and square.
	var sh := _at("DEF-upper_arm.L") - _at("DEF-upper_arm.R")
	_turn(_bone("DEF-spine.003"), _arc(sh.normalized(), left))
	# The neck and head upright again over the chest, the head level (her rest tilts it).
	for k in [3]:
		var d := _at(chain[k + 1]) - _at(chain[k])
		_aim(_bone(chain[k]), _bone(chain[k + 1]), d - left * d.dot(left))
	var ears := _at("DEF-ear01.L") - _at("DEF-ear01.R")
	_turn(_bone("DEF-head"), _arc(ears.normalized(), left))
	_stand_up()
	for s in [["L", 1.0], ["R", -1.0]]:
		var side: Vector3 = left * s[1]
		var ua := _bone("DEF-upper_arm." + s[0])
		var fa := _bone("DEF-forearm." + s[0])
		var hand := _bone("DEF-hand." + s[0])
		# Elbow back: turn the upper arm about itself so the rest pose's elbow bend would bring
		# the forearm forward (only when the rest arm is bent enough to tell).
		var u := (_at("DEF-forearm." + s[0]) - _at("DEF-upper_arm." + s[0])).normalized()
		var f := (_at("DEF-hand." + s[0]) - _at("DEF-forearm." + s[0])).normalized()
		var hinge := u.cross(f)
		_aim(ua, fa, side)
		if hinge.length() > 0.2:
			var hinge_now: Vector3 = _arc(u, side) * hinge.normalized()
			# the hinge that swings the forearm forward from pointing along `side`:
			var want := side.cross(fwd).normalized()
			var h := (hinge_now - side * hinge_now.dot(side)).normalized()
			var ang := atan2(h.cross(want).dot(side), h.dot(want))
			_turn(ua, Quaternion(side, ang))
		_aim(fa, hand, side)
		_aim(hand, _bone("DEF-f_middle.01." + s[0]), side)
		# Palm down: turn the forearm (and the hand) about the arm.
		var across := _at("DEF-f_index.01." + s[0]) - _at("DEF-f_pinky.01." + s[0])
		var normal := across.cross(side).normalized()
		var thumb := _at("DEF-thumb.01." + s[0]) - (_at("DEF-f_index.01." + s[0]) + _at("DEF-f_pinky.01." + s[0])) * 0.5
		if normal.dot(thumb) < 0.0:
			normal = -normal      # toward the palm side (where the thumb sits)
		var have := (normal - side * normal.dot(side)).normalized()
		var ang2 := atan2(have.cross(-up).dot(side), have.dot(-up))
		_turn(fa, Quaternion(side, ang2))
		# Fingers straight along their palm bones.
		var palm := {"index": "01", "middle": "02", "ring": "03", "pinky": "04"}
		for fname in palm:
			var p0 := _bone("DEF-palm.%s.%s" % [palm[fname], s[0]])
			var f1 := _bone("DEF-f_%s.01.%s" % [fname, s[0]])
			if p0 < 0 or f1 < 0:
				continue
			var dir := (sk.get_bone_global_pose(f1).origin - sk.get_bone_global_pose(p0).origin).normalized()
			_straighten(["DEF-f_%s.01.%s" % [fname, s[0]], "DEF-f_%s.02.%s" % [fname, s[0]], "DEF-f_%s.03.%s" % [fname, s[0]], "DEF-f_%s.03.%s_end" % [fname, s[0]]], dir)
		# The thumb straight along its first bone.
		var t1 := _bone("DEF-thumb.01." + s[0])
		var t2 := _bone("DEF-thumb.02." + s[0])
		if t1 >= 0 and t2 >= 0:
			var tdir := (sk.get_bone_global_pose(t2).origin - sk.get_bone_global_pose(t1).origin).normalized()
			_straighten(["DEF-thumb.02." + s[0], "DEF-thumb.03." + s[0], "DEF-thumb.03.%s_end" % s[0]], tdir)
	# Legs straight down, feet flat (as modelled) and forward.
	for s in ["L", "R"]:
		_aim(_bone("DEF-thigh." + s), _bone("DEF-shin." + s), -up)
		_aim(_bone("DEF-shin." + s), _bone("DEF-foot." + s), -up)
		var toe := _at("DEF-toe." + s) - _at("DEF-foot." + s)
		var flat := Vector2(toe.dot(left), toe.dot(fwd))
		var yaw := Quaternion(up, -atan2(flat.x, flat.y)) if flat.length() > 1e-5 else Quaternion.IDENTITY
		_set_rot(_bone("DEF-foot." + s), yaw * feet_rest["DEF-foot." + s])
		_set_rot(_bone("DEF-toe." + s), yaw * feet_rest["DEF-toe." + s])
	# Her rest stands on the left leg with the right paw on its toes: the right paw and toes take
	# the left ones' set, mirrored.
	for n in ["DEF-foot.", "DEF-toe."]:
		_set_rot(_bone(n + "R"), _mirror_rot(_rot(_bone(n + "L"))))
	var dl := _at("DEF-toe.L") - _at("DEF-foot.L")
	_aim(_bone("DEF-foot.R"), _bone("DEF-toe.R"), dl - left * 2.0 * dl.dot(left))   # exactly the left paw's slope, mirrored
	_rabbit_legs()


## Her rest leans the upper body back (neck and shoulders 12 cm behind the hips, the belly and
## chest pushed out; the player showed a woman's T-pose from the side): the lower back bends
## forward until the neck is over the hip joints; the ribcage keeps its tilt (tipping it hung
## her chest). The neck and head
## keep their turn, so she still looks ahead.
const NECK_OVER_HIPS := 0.0   ## metres forward of the hip joints (side view)

func _stand_up() -> void:
	var bones := [_bone("DEF-spine.001"), _bone("DEF-spine.002"), _bone("DEF-spine.003")]
	var share := [0.5, 0.5, -1.0]   # the lower back bends; the ribcage moves forward without tipping (its breasts keep their set)
	var neck := _bone("DEF-neck")
	var head := _bone("DEF-head")
	var start := []
	for b in bones:
		start.append(_rot(b))
	var neck_rot := _rot(neck)
	var head_rot := _rot(head)
	var axis := up.cross(fwd).normalized()      # turning about it tips "up" toward "fwd"
	var metre := 1.0 / place.basis.get_scale().x   # skeleton units per metre (set before posing)
	var offset := func() -> float:
		var hips := (_at("DEF-thigh.L") + _at("DEF-thigh.R")) * 0.5
		return (_at("DEF-neck") - hips).dot(fwd) / metre
	var lo := -0.5
	var hi := 0.5
	for _i in 30:
		var a := (lo + hi) * 0.5
		var sum := 0.0
		for k in bones.size():
			sum += share[k]
			_set_rot(bones[k], Quaternion(axis, a * sum) * start[k])   # parents first: the bends add up
		_set_rot(neck, neck_rot)
		_set_rot(head, head_rot)
		if offset.call() < NECK_OVER_HIPS:
			lo = a
		else:
			hi = a
	print("spine bent forward %.1f deg; neck %.3f m from over the hips" % [rad_to_deg((lo + hi) * 0.5), offset.call()])


## The mirror image (across her middle) of a left bone's rotation, as a right bone's: the
## right bones' own axes are the left ones' mirrored with one axis flipped, found once from a
## pair that is symmetric in her rest (the breasts).
var _flip := Basis()
var _flip_known := false

func _mirror_rot(q: Quaternion) -> Quaternion:
	var m := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	m = Basis(Vector3(1, 0, 0) - left * 2.0 * left.x, Vector3(0, 1, 0) - left * 2.0 * left.y, Vector3(0, 0, 1) - left * 2.0 * left.z)
	if not _flip_known:
		var bl := sk.get_bone_global_rest(_bone("DEF-breast01.L")).basis.orthonormalized()
		var br := sk.get_bone_global_rest(_bone("DEF-breast01.R")).basis.orthonormalized()
		var d := (m * bl).inverse() * br   # ~ a diagonal of +-1
		_flip = Basis(Vector3(signf(d.x.x), 0, 0), Vector3(0, signf(d.y.y), 0), Vector3(0, 0, signf(d.z.z)))
		_flip_known = true
	return (m * Basis(q) * _flip).orthonormalized().get_rotation_quaternion()


## A rabbit's leg (the player chose it): she stands on the front of her paws, the heel raised
## (HEEL_UP, the paw turning about its ball, which stays where it was, toes flat), and the leg
## folds like a Z: the knee KNEE_FWD in front of the hip-ankle line. Her paw is short, so the
## hips come down a little to make room for the fold (both legs alike).
const HEEL_UP := deg_to_rad(25.0)
const KNEE_FWD := 0.12   ## metres (of this tool; the game fits her a little smaller)

func _rabbit_legs() -> void:
	var axis := up.cross(fwd).normalized()          # turning about it tips "up" toward "fwd"
	var lift := Quaternion(axis, HEEL_UP)             # the heel goes up
	var legs := {}
	for s in ["L", "R"]:
		var ball := _at("DEF-toe." + s)
		var ankle := _at("DEF-foot." + s)
		var knee := _at("DEF-shin." + s)
		var hip := _at("DEF-thigh." + s)
		legs[s] = {"ball": ball, "heel": ball + lift * (ankle - ball), "l1": hip.distance_to(knee), "l2": knee.distance_to(ankle), "toe_rot": _rot(_bone("DEF-toe." + s))}
	# The right paw stands exactly as the left, mirrored across her middle.
	var mid := (_at("DEF-thigh.L") + _at("DEF-thigh.R")) * 0.5
	var mirror := func(p: Vector3) -> Vector3: return p - left * 2.0 * (p - mid).dot(left)
	legs["R"]["ball"] = mirror.call(legs["L"]["ball"])
	legs["R"]["heel"] = mirror.call(legs["L"]["heel"])
	# How far hip and heel must be for the knee to stand KNEE_FWD off their line.
	var L: Dictionary = legs["L"]
	var metre := 1.0 / place.basis.get_scale().x
	var k := KNEE_FWD * metre
	var lo: float = absf(L.l1 - L.l2) + 1e-4
	var hi: float = L.l1 + L.l2 - 1e-4
	for _i in 40:
		var d := (lo + hi) * 0.5
		var a: float = (L.l1 * L.l1 + d * d - L.l2 * L.l2) / (2.0 * d)
		var h := sqrt(maxf(L.l1 * L.l1 - a * a, 0.0))
		if h > k:
			lo = d
		else:
			hi = d
	var want_d := (lo + hi) * 0.5
	# Lower the hips (the whole body above the legs) until the left hip is that far from its heel.
	var root := _bone("DEF-spine")
	var start := sk.get_bone_pose_position(root)
	var par := sk.get_bone_parent(root)
	var to_par := Basis() if par < 0 else sk.get_bone_global_pose(par).basis.inverse()
	var dlo := 0.0
	var dhi := 0.6 * metre
	for _i in 40:
		var drop := (dlo + dhi) * 0.5
		sk.set_bone_pose_position(root, start + to_par * (-up * drop))
		if _at("DEF-thigh.L").distance_to(L.heel) > want_d:
			dlo = drop
		else:
			dhi = drop
	print("rabbit legs: hips down %.3f m" % ((dlo + dhi) * 0.5 / metre))
	for s in ["L", "R"]:
		_fold_leg(s, legs[s])


func _fold_leg(s: String, g: Dictionary) -> void:
	var thigh := _bone("DEF-thigh." + s)
	var shin := _bone("DEF-shin." + s)
	var foot := _bone("DEF-foot." + s)
	var hip := _at("DEF-thigh." + s)
	var heel: Vector3 = g.heel
	var d := clampf(hip.distance_to(heel), absf(g.l1 - g.l2) + 1e-4, g.l1 + g.l2 - 1e-4)
	var along := (heel - hip).normalized()
	var bend := (fwd - along * fwd.dot(along)).normalized()   # the knee goes forward
	var a: float = (g.l1 * g.l1 + d * d - g.l2 * g.l2) / (2.0 * d)
	var knee_at: Vector3 = hip + along * a + bend * sqrt(maxf(g.l1 * g.l1 - a * a, 0.0))
	_aim(thigh, shin, knee_at - hip)
	_aim(shin, foot, heel - _at("DEF-shin." + s))
	# The paw: from the raised heel down to its ball, then the toes flat again.
	_turn(foot, _arc((_at("DEF-toe." + s) - _at("DEF-foot." + s)).normalized(), (g.ball - heel).normalized()))
	_set_rot(_bone("DEF-toe." + s), g.toe_rot)


var _body_mi: MeshInstance3D

## The lowest point (along "up", skeleton space) of a paw's skin in the current pose.
func _paw_low(s: String) -> float:
	var skin := _body_mi.skin
	var arr := _body_mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var paw := {}
	for bind in skin.get_bind_count():
		var n := _clean(sk.get_bone_name(_bind_bone(skin, bind)))
		if n == "DEF-foot." + s or n == "DEF-toe." + s:
			paw[bind] = true
	var low := INF
	for i in verts.size():
		var on := 0.0
		for k in 4:
			if paw.has(bones[i * 4 + k]):
				on += w[i * 4 + k]
		if on < 0.5:
			continue
		var p := Vector3.ZERO
		for k in 4:
			var wt := w[i * 4 + k]
			if wt > 0.0:
				var b := bones[i * 4 + k]
				p += (sk.get_bone_global_pose(_bind_bone(skin, b)) * skin.get_bind_pose(b) * verts[i]) * wt
		low = minf(low, p.dot(up))
	return low


## Points each bone of a chain along `dir` (the last name is the tip, only aimed at).
func _straighten(names: Array, dir: Vector3) -> void:
	for k in names.size() - 1:
		var b := _bone(names[k])
		var c := _bone(names[k + 1])
		if b >= 0 and c >= 0:
			_aim(b, c, dir)


## The mesh's vertices (and normals, tangents, blend shapes) skinned in the current pose,
## in skeleton space: [arrays per surface, blend shape arrays per surface].
func _bake(m: MeshInstance3D) -> Array:
	var out := []
	var skin := m.skin
	var mats := {}
	for bind in skin.get_bind_count():
		mats[bind] = sk.get_bone_global_pose(_bind_bone(skin, bind)) * skin.get_bind_pose(bind)
	for sf in m.mesh.get_surface_count():
		var arr: Array = m.mesh.surface_get_arrays(sf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var tans: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		var vx := []
		vx.resize(verts.size())
		for i in verts.size():
			var t := Transform3D(Basis() * 0.0, Vector3.ZERO)
			var tb := Basis() * 0.0
			var to := Vector3.ZERO
			for k in per:
				var wt := w[i * per + k]
				if wt <= 0.0:
					continue
				var mm: Transform3D = mats[bones[i * per + k]]
				tb = Basis(tb.x + mm.basis.x * wt, tb.y + mm.basis.y * wt, tb.z + mm.basis.z * wt)
				to += mm.origin * wt
			vx[i] = Transform3D(tb, to)
		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		var nt := PackedFloat32Array()
		nv.resize(verts.size())
		nn.resize(verts.size())
		nt.resize(tans.size())
		for i in verts.size():
			var x: Transform3D = vx[i]
			nv[i] = place * (x * verts[i])
			if norms.size() == verts.size():
				nn[i] = (place_rot * (x.basis * norms[i])).normalized()
			if tans.size() == verts.size() * 4:
				var tv := (place_rot * (x.basis * Vector3(tans[i * 4], tans[i * 4 + 1], tans[i * 4 + 2]))).normalized()
				nt[i * 4] = tv.x
				nt[i * 4 + 1] = tv.y
				nt[i * 4 + 2] = tv.z
				nt[i * 4 + 3] = tans[i * 4 + 3]
		arr[Mesh.ARRAY_VERTEX] = nv
		if norms.size() == verts.size():
			arr[Mesh.ARRAY_NORMAL] = nn
		if tans.size() == verts.size() * 4:
			arr[Mesh.ARRAY_TANGENT] = nt
		# Her two blend shapes are broken in the file (100x off, never used): left out.
		var shapes := []
		out.append([arr, shapes, m.mesh.surface_get_primitive_type(sf), m.mesh.surface_get_material(sf)])
	return out


## A new scene: a clean skeleton whose rest is the T-pose, the baked meshes skinned to it.
func _build(meshes: Array[MeshInstance3D], baked: Dictionary) -> Node3D:
	var root3 := Node3D.new()
	root3.name = "ChobbyBun"
	var nsk := Skeleton3D.new()
	nsk.name = "Skeleton3D"
	root3.add_child(nsk)
	var index := {}
	var order := []
	var placed := {}
	while order.size() < keep.size():
		for b in keep:
			if placed.has(b):
				continue
			var p := sk.get_bone_parent(b)
			if p < 0 or placed.has(p) or not keep.has(p):
				order.append(b)
				placed[b] = true
	var glob := {}
	for b in order:
		var g := sk.get_bone_global_pose(b)
		glob[b] = Transform3D(place_rot * g.basis.orthonormalized(), place * g.origin)
	# Symmetric: each right bone is its left one mirrored, the middle ones sit on the middle.
	var plane_c: Vector3 = place * ((_at("DEF-thigh.L") + _at("DEF-thigh.R")) * 0.5)
	var plane_n: Vector3 = (place_rot * left).normalized()
	_plane_c = plane_c
	_plane_n = plane_n
	var by_name := {}
	for b in order:
		by_name[_clean(sk.get_bone_name(b))] = b
	for b in order:
		var nm := _clean(sk.get_bone_name(b))
		var other := _swap_side(nm)
		if other == nm:
			var g: Transform3D = glob[b]
			glob[b] = Transform3D(g.basis, g.origin - plane_n * (g.origin - plane_c).dot(plane_n))
		elif nm.contains(".R") and by_name.has(other):
			glob[b] = _mirror_xf(glob[by_name[other]])
	for b in order:
		var i := nsk.get_bone_count()
		nsk.add_bone(_clean(sk.get_bone_name(b)))
		index[b] = i
		var p := sk.get_bone_parent(b)
		if p >= 0 and index.has(p):
			nsk.set_bone_parent(i, index[p])
			nsk.set_bone_rest(i, (glob[p] as Transform3D).affine_inverse() * glob[b])
		else:
			nsk.set_bone_rest(i, glob[b])
	nsk.reset_bone_poses()
	var skin := Skin.new()
	var bind_of := {}
	for b in order:
		bind_of[b] = skin.get_bind_count()
		skin.add_named_bind(_clean(sk.get_bone_name(b)), (glob[b] as Transform3D).affine_inverse())
	for m in meshes:
		var mesh := ArrayMesh.new()
		var first: Array = baked[m.name]
		for s in first:
			var arr: Array = s[0]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var nb := PackedInt32Array()
			nb.resize(bones.size())
			for i in bones.size():
				var ob := _bind_bone(m.skin, bones[i])
				nb[i] = bind_of.get(ob, 0)
			arr[Mesh.ARRAY_BONES] = nb
			_symmetrize(arr, skin, m.name)
			mesh.add_surface_from_arrays(s[2], arr, s[1])
			mesh.surface_set_material(mesh.get_surface_count() - 1, s[3])
		var mi := MeshInstance3D.new()
		mi.name = m.name
		mi.mesh = mesh
		mi.skin = skin
		nsk.add_child(mi)
		mi.skeleton = NodePath("..")
	for n in [nsk] + nsk.get_children():
		n.owner = root3
	return root3


var _plane_c := Vector3.ZERO   ## her middle plane in the new model's space
var _plane_n := Vector3.RIGHT

## "DEF-thigh.R" <-> "DEF-thigh.L", "DEF-upper_arm.R.001" <-> ".L.001", "DEF-f_index.03.R_end" <-> ".L_end".
static func _swap_side(n: String) -> String:
	var re := RegEx.create_from_string("\\.([LR])(\\.|_|$)")
	var m := re.search(n)
	if m == null:
		return n
	var side := "L" if m.get_string(1) == "R" else "R"
	return n.substr(0, m.get_start(1)) + side + n.substr(m.get_end(1))


func _mirror_p(p: Vector3) -> Vector3:
	return p - _plane_n * 2.0 * (p - _plane_c).dot(_plane_n)


func _mirror_v(v: Vector3) -> Vector3:
	return v - _plane_n * 2.0 * v.dot(_plane_n)


## A left bone's placement mirrored as a right bone's (one local axis flipped to stay right-handed).
func _mirror_xf(t: Transform3D) -> Transform3D:
	var b := Basis(_mirror_v(t.basis.x) * -1.0, _mirror_v(t.basis.y), _mirror_v(t.basis.z))
	return Transform3D(b, _mirror_p(t.origin))


## The right half made the mirror of the left (below the neck; her face and hair are drawn
## asymmetric on purpose). Vertices are grouped by the bone that carries most of them; each right
## group is first shifted onto its left group's mirror (it may sit a little off), then each right
## vertex takes the position, normal and weights (sides swapped) of the mirrored left vertex it
## lands on. A right vertex with no partner moves with its group's shift.
const PAIR := 0.006   ## metres: closer than this, a right vertex and a mirrored left one are a pair
const KEEP_AS_IS := ["DEF-head", "DEF-neck", "DEF-ear"]

func _symmetrize(arr: Array, skin: Skin, mesh_name: String) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var tan: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / v.size()
	var names := []
	var bind_of_name := {}
	for i in skin.get_bind_count():
		names.append(String(skin.get_bind_name(i)))
		bind_of_name[names[i]] = i
	var swap := []
	for i in names.size():
		swap.append(bind_of_name.get(_swap_side(names[i]), i))
	var top := func(i: int) -> int:
		var best := 0
		for k in per:
			if w[i * per + k] > w[i * per + best]:
				best = k
		return bones[i * per + best]
	var groups_r := {}
	var groups_l := {}
	for i in v.size():
		var d := (v[i] - _plane_c).dot(_plane_n)
		var b: int = top.call(i)
		var skip := false
		for pre in KEEP_AS_IS:
			if names[b].begins_with(pre):
				skip = true
		if skip or absf(d) < 0.002:
			continue
		if d > 0.0:
			if not groups_l.has(b): groups_l[b] = []
			groups_l[b].append(i)
		else:
			if not groups_r.has(b): groups_r[b] = []
			groups_r[b].append(i)
	var paired := 0
	var moved := 0
	var nv := v.duplicate()
	var nn := nrm.duplicate()
	var nt := tan.duplicate()
	var nb := bones.duplicate()
	var nw := w.duplicate()
	for b in groups_r:
		var lb: int = swap[b]
		if not groups_l.has(lb):
			continue
		var targets: Array = groups_l[lb]
		var grid := {}
		var tp := PackedVector3Array()
		for j in targets:
			var q := _mirror_p(v[j])
			tp.append(q)
			var key := Vector3i((q / 0.02).floor())
			if not grid.has(key): grid[key] = []
			grid[key].append(tp.size() - 1)
		var near := func(p: Vector3) -> int:
			var c := Vector3i((p / 0.02).floor())
			var best := -1
			var bd := INF
			for x in [-1, 0, 1]:
				for y in [-1, 0, 1]:
					for z in [-1, 0, 1]:
						for k in grid.get(c + Vector3i(x, y, z), []):
							var dd := p.distance_squared_to(tp[k])
							if dd < bd:
								bd = dd
								best = k
			return best
		var shift := Vector3.ZERO
		for _it in 8:
			var sum := Vector3.ZERO
			var cnt := 0
			for i in groups_r[b]:
				var k: int = near.call(v[i] + shift)
				if k >= 0 and (v[i] + shift).distance_to(tp[k]) < 0.03:
					sum += tp[k] - (v[i] + shift)
					cnt += 1
			if cnt == 0:
				break
			shift += sum / cnt
		for i in groups_r[b]:
			var k: int = near.call(v[i] + shift)
			if k >= 0 and (v[i] + shift).distance_to(tp[k]) < PAIR:
				var j: int = targets[k]
				nv[i] = tp[k]
				if nrm.size() == v.size():
					nn[i] = _mirror_v(nrm[j])
				if tan.size() == v.size() * 4:
					var t := _mirror_v(Vector3(tan[j * 4], tan[j * 4 + 1], tan[j * 4 + 2]))
					nt[i * 4] = t.x
					nt[i * 4 + 1] = t.y
					nt[i * 4 + 2] = t.z
				for kk in per:
					nb[i * per + kk] = swap[bones[j * per + kk]]
					nw[i * per + kk] = w[j * per + kk]
				paired += 1
			else:
				nv[i] = v[i] + shift
				moved += 1
	arr[Mesh.ARRAY_VERTEX] = nv
	if nrm.size() == v.size():
		arr[Mesh.ARRAY_NORMAL] = nn
	if tan.size() == v.size() * 4:
		arr[Mesh.ARRAY_TANGENT] = nt
	arr[Mesh.ARRAY_BONES] = nb
	arr[Mesh.ARRAY_WEIGHTS] = nw
	print("symmetric %s: %d right vertices take their left pair, %d only shifted" % [mesh_name, paired, moved])


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Quaternion(c.normalized(), atan2(c.length(), d))
