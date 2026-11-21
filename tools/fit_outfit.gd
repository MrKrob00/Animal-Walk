extends SceneTree
## Takes Agnes' clothes (assets/agnes.glb; her body and hair are not used: the player keeps the
## bunny's own) and fits them to the bunny as a second outfit, saved in assets/outfits/agnes/.
##   godot --headless --path . --script tools/fit_outfit.gd
## 1. Both are in a T-pose. Each of Agnes' bones is laid onto the bunny's matching one: moved to
##    its joint, turned along it, stretched to its length, and widened round it by how much
##    thicker the bunny's skin sits round that bone (her hips, thighs and chest are wider).
##    A garment follows Agnes' bones by its own weights (so a sleeve goes with the arm).
## 2. Pushed out of the bunny's body to stand GAP off the skin everywhere, the push smoothed over
##    the cloth (so the dress lies over her chest rather than being pierced by it).
## 3. Reweighted from the nearest bunny skin (as her own top and shorts are); a skirt below the
##    hips half on the pelvis, or it would split between her legs.
## 4. Textures down to 1024 (phone), drawn unshaded like the bunny.

const OUT := "res://assets/outfits/agnes/"
const GARMENTS := {   # Agnes' mesh -> [file name, slot]
	"Agnes_doll_shirt": ["blouse", "upper"],
	"Agnes_doll_sundress": ["sundress", "dress"],
}
const GAP := 0.006          ## metres (the bunny's file units are ~1.48 m per game metre; see SCALE)
const TEX := 1024
## [Agnes bone, its far joint, the bunny's bone, its far joint]
const PAIRS := [
	["Hips", "Spine", "DEF-spine", "DEF-spine.001"],
	["Spine", "Spine1", "DEF-spine.001", "DEF-spine.002"],
	["Spine1", "Spine2", "DEF-spine.002", "DEF-spine.003"],
	["Spine2", "Neck", "DEF-spine.003", "DEF-neck"],
	["Neck", "Head", "DEF-neck", "DEF-head"],
	["LeftShoulder", "LeftArm", "DEF-shoulder.L", "DEF-upper_arm.L"],
	["LeftArm", "LeftForeArm", "DEF-upper_arm.L", "DEF-forearm.L"],
	["LeftForeArm", "LeftHand", "DEF-forearm.L", "DEF-hand.L"],
	["LeftHand", "LeftHandMiddle1", "DEF-hand.L", "DEF-f_middle.01.L"],
	["LeftUpLeg", "LeftLeg", "DEF-thigh.L", "DEF-shin.L"],
	["LeftLeg", "LeftFoot", "DEF-shin.L", "DEF-foot.L"],
	["LeftFoot", "LeftToeBase", "DEF-foot.L", "DEF-toe.L"],
	["RightShoulder", "RightArm", "DEF-shoulder.R", "DEF-upper_arm.R"],
	["RightArm", "RightForeArm", "DEF-upper_arm.R", "DEF-forearm.R"],
	["RightForeArm", "RightHand", "DEF-forearm.R", "DEF-hand.R"],
	["RightHand", "RightHandMiddle1", "DEF-hand.R", "DEF-f_middle.01.R"],
	["RightUpLeg", "RightLeg", "DEF-thigh.R", "DEF-shin.R"],
	["RightLeg", "RightFoot", "DEF-shin.R", "DEF-foot.R"],
	["RightFoot", "RightToeBase", "DEF-foot.R", "DEF-toe.R"],
]

var ska: Skeleton3D
var skc: Skeleton3D
var body_a: MeshInstance3D
var body_c: MeshInstance3D
var maps := {}      ## Agnes bone -> {"a0","x","y","z" (source frame), "c0","rot","sy","sr"}
var skirt := {}     ## the skirt's map: from between Agnes' hip joints to between the bunny's
var hip_a := 0.0    ## Agnes' hip joints' height: a dress below it hangs from the hips only


func _initialize() -> void:
	_run()


func _run() -> void:
	var a: Node3D = load("res://assets/agnes.glb").instantiate()
	var c: Node3D = load("res://assets/chobby_tpose.glb").instantiate()
	root.add_child(a)
	root.add_child(c)
	await process_frame
	ska = a.find_children("*", "Skeleton3D", true, false)[0]
	skc = c.find_children("*", "Skeleton3D", true, false)[0]
	body_a = a.find_child("Agnes_doll_body", true, false)
	body_c = c.find_child("Object_11", true, false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build_maps()
	var cbody := _body_points()
	for n in GARMENTS:
		var g: MeshInstance3D = a.find_child(n, true, false)
		if g == null:
			push_warning("no " + n)
			continue
		var t0 := Time.get_ticks_msec()
		if GARMENTS[n][1] == "dress":
			_measure_hip_line(g)
		var mesh := _fit(g, cbody, GARMENTS[n][1])
		# What is fitted becomes something the next garment lies over (the dress over the blouse:
		# pushed out to the same distance they mixed into dark patches).
		_add_layer(cbody, mesh)
		ResourceSaver.save(mesh, OUT + GARMENTS[n][0] + ".res")
		print("fitted ", GARMENTS[n][0], " in ", Time.get_ticks_msec() - t0, " ms")
	quit()


func _ga(n: String) -> Vector3:
	return ska.get_bone_global_rest(ska.find_bone("mixamorig_" + n)).origin


func _gc(n: String) -> Vector3:
	return skc.get_bone_global_rest(Gait.find_bone(skc, n)).origin


## The bone-to-bone maps, with each bone's widening from the two bodies' skins.
func _build_maps() -> void:
	var ra := _radii(body_a, ska, true)
	var rc := _radii(body_c, skc, false)
	for p in PAIRS:
		var a0 := _ga(p[0])
		var a1 := _ga(p[1])
		var c0 := _gc(p[2])
		var c1 := _gc(p[3])
		var y := (a1 - a0).normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		var rot := Gait._arc(y, (c1 - c0).normalized())
		var r_a: float = ra.get(p[0], 0.0)
		var r_c: float = rc.get(p[2], 0.0)
		var sr := clampf(r_c / r_a, 0.6, 2.6) if r_a > 1e-4 and r_c > 1e-4 else (c1 - c0).length() / (a1 - a0).length()
		maps[p[0]] = {"a0": a0, "x": x, "y": y, "z": z, "c0": c0, "rot": rot, "sy": (c1 - c0).length() / (a1 - a0).length(), "sr": sr, "a1": a1, "c1": c1}
		print(p[0], " -> ", p[2], " length x", snapped(maps[p[0]].sy, 0.01), " girth x", snapped(sr, 0.01))
	# The skirt hangs from the hips: from between the hip joints, its length by the whole figure's
	# scale, its width by the hips' (by the pelvis bone, whose lengths differ threefold, and by
	# the legs, it was stretched into a cone down to her ankles).
	var ha := (_ga("LeftUpLeg") + _ga("RightUpLeg")) * 0.5
	var hc := (_gc("DEF-thigh.L") + _gc("DEF-thigh.R")) * 0.5
	var fig := (_gc("DEF-head").y - minf(_gc("DEF-toe.L").y, 0.0)) / (_ga("Head").y - minf(_ga("LeftToeBase").y, 0.0))
	hip_a = ha.y
	# Its width by how far apart the hip joints are (by the skin's girth round the pelvis bone,
	# x1.84, it stood out like a bell: the player found it ugly); the thighs push it out where
	# they need room.
	var wide := (_gc("DEF-thigh.L") - _gc("DEF-thigh.R")).length() / (_ga("LeftUpLeg") - _ga("RightUpLeg")).length()
	skirt = {"a0": ha, "x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK, "c0": hc, "rot": Quaternion.IDENTITY, "sy": fig, "sr": wide}
	print("skirt: length x", snapped(fig, 0.01), " width x", snapped(wide, 0.01), " (girth x", snapped(maps.Hips.sr, 0.01), ")")
	# The pelvis goes by it too, for every garment: by the pelvis bone (three times longer on her)
	# a dress's waist and skirt pulled apart from what hangs on the spine.
	maps["Hips"] = skirt


## Median distance of a body's skin from each bone's line (verts mostly on that bone).
func _radii(mi: MeshInstance3D, sk: Skeleton3D, agnes: bool) -> Dictionary:
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bb.size() / vs.size()
	var lists := {}
	for p in PAIRS:
		var name: String = p[0] if agnes else p[2]
		var b := sk.find_bone("mixamorig_" + name) if agnes else Gait.find_bone(sk, name)
		lists[b] = [name, (_ga(p[0]) if agnes else _gc(p[2])), (_ga(p[1]) if agnes else _gc(p[3])), []]
	for v in vs.size():
		var best := 0
		for k in per:
			if ww[v * per + k] > ww[v * per + best]:
				best = k
		if ww[v * per + best] < 0.6:
			continue
		var bone := _bind_bone(mi, sk, bb[v * per + best])
		if lists.has(bone):
			var l: Array = lists[bone]
			var p := _rest_pos(mi, sk, vs[v], bb, ww, per, v)
			l[3].append(_seg_dist(p, l[1], l[2]))
	var out := {}
	for b in lists:
		var ds: Array = lists[b][3]
		if ds.size() < 10:
			continue
		ds.sort()
		out[lists[b][0]] = ds[ds.size() / 2]
	return out


func _bind_bone(mi: MeshInstance3D, sk: Skeleton3D, bind: int) -> int:
	var b := mi.skin.get_bind_bone(bind)
	return b if b >= 0 else sk.find_bone(mi.skin.get_bind_name(bind))


## A vertex where the rest pose puts it (skeleton space).
func _rest_pos(mi: MeshInstance3D, sk: Skeleton3D, v: Vector3, bb: PackedInt32Array, ww: PackedFloat32Array, per: int, i: int) -> Vector3:
	var p := Vector3.ZERO
	var tot := 0.0
	for k in per:
		var w := ww[i * per + k]
		if w <= 0.0:
			continue
		var bone := _bind_bone(mi, sk, bb[i * per + k])
		p += (sk.get_bone_global_rest(bone) * mi.skin.get_bind_pose(bb[i * per + k]) * v) * w
		tot += w
	return p / maxf(tot, 1e-6)


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Where Agnes' bone `name` puts a rest point `p` on the bunny ("skirt": the skirt's map: what
## flares out beyond the hip line is kept to FLARE of it, so on her wide hips the skirt hangs
## rather than standing out like a bell, which the player found ugly).
const FLARE := 0.35
func _map_point(name: String, p: Vector3) -> Vector3:
	var m: Dictionary = skirt if name == "skirt" else maps[name]
	var d: Vector3 = p - m.a0
	var sr: float = m.sr
	if name == "skirt" and m.has("ax") and d.y < 0.0:
		var h := Vector2(d.x, d.z)
		var r := h.length()
		if r > 1e-5:
			var dir := h / r
			var rb := 1.0 / sqrt(pow(dir.x / m.ax, 2.0) + pow(dir.y / m.az, 2.0))   # the hip line's ellipse
			if r > rb:
				var k := clampf(-d.y / 0.04, 0.0, 1.0)
				var r2 := rb + (r - rb) * lerpf(1.0, FLARE, k)
				d = Vector3(dir.x * r2, d.y, dir.y * r2)
	var lx: float = d.dot(m.x) * sr
	var ly: float = d.dot(m.y) * m.sy
	var lz: float = d.dot(m.z) * sr
	return m.c0 + (m.rot as Quaternion) * (m.x * lx + m.y * ly + m.z * lz)


## The nearest mapped bone up Agnes' hierarchy (fingers ride the hand, the hair the head...).
func _mapped(bone: int) -> String:
	var b := bone
	while b >= 0:
		var n := ska.get_bone_name(b).trim_prefix("mixamorig_")
		if maps.has(n):
			return n
		b = ska.get_bone_parent(b)
	return "Hips"


## The bunny's body skin (rest, skeleton space) in a grid: [positions, normals, weights, grid].
func _body_points() -> Dictionary:
	var arr := body_c.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bb.size() / vs.size()
	var head := Gait.find_bone(skc, "DEF-head")
	var grid := {}
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var idx := PackedInt32Array()
	pos.resize(vs.size())
	nor.resize(vs.size())
	for v in vs.size():
		var p := _rest_pos(body_c, skc, vs[v], bb, ww, per, v)
		pos[v] = p
		nor[v] = ns[v]
		# The head (and the hair, ears) is not something to dress round.
		var hw := 0.0
		for k in per:
			if _bind_bone(body_c, skc, bb[v * per + k]) == head:
				hw += ww[v * per + k]
		if hw > 0.5:
			continue
		var key := Vector3i((p / 0.03).floor())
		var cell: PackedInt32Array = grid.get(key, PackedInt32Array())
		cell.append(v)
		grid[key] = cell
	return {"pos": pos, "nor": nor, "bones": bb, "weights": ww, "per": per, "grid": grid, "skin_n": vs.size(), "skin_grid": grid.duplicate(true)}


func _nearest(cb: Dictionary, p: Vector3, count: int, skin_only := false) -> Array:
	var key := Vector3i((p / 0.03).floor())
	var best := []
	var grid: Dictionary = cb.skin_grid if skin_only else cb.grid
	for r in [1, 2, 3, 4, 5, 6]:
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				for z in range(-r, r + 1):
					if r > 1 and maxi(absi(x), maxi(absi(y), absi(z))) != r:
						continue
					for i in grid.get(key + Vector3i(x, y, z), PackedInt32Array()):
						var d: float = p.distance_squared_to(cb.pos[i])
						if best.size() < count or d < best[-1][0]:
							var at := best.size()
							while at > 0 and best[at - 1][0] > d:
								at -= 1
							best.insert(at, [d, i])
							if best.size() > count:
								best.pop_back()
		if best.size() >= count:
			break
	return best


func _fit(g: MeshInstance3D, cb: Dictionary, slot: String) -> ArrayMesh:
	var arr := g.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var per := bb.size() / vs.size()
	# 1. Onto her bones.
	var out := PackedVector3Array()
	var nout := PackedVector3Array()
	out.resize(vs.size())
	nout.resize(vs.size())
	for v in vs.size():
		var p := Vector3.ZERO
		var nrm := Vector3.ZERO
		var tot := 0.0
		for k in per:
			var w := ww[v * per + k]
			if w <= 0.0:
				continue
			var bind := bb[v * per + k]
			var bone := _bind_bone(g, ska, bind)
			var rest := ska.get_bone_global_rest(bone) * g.skin.get_bind_pose(bind)
			var name := _mapped(bone)
			var rp: Vector3 = rest * vs[v]
			# A dress: all it hangs on the pelvis and legs by goes by the skirt's map, whatever the
			# height (by the pelvis bone above the hip line and the skirt's map below, it stepped
			# out in a shelf at the hip line: the player saw it).
			if slot == "dress" and (name.contains("Leg") or name == "Hips"):
				name = "skirt"
			p += _map_point(name, rp) * w
			nrm += (((skirt if name == "skirt" else maps[name]).rot as Quaternion) * (rest.basis * ns[v])) * w
			tot += w
		out[v] = p / maxf(tot, 1e-6)
		nout[v] = nrm.normalized()
	if OS.has_environment("FIT_DEBUG"):
		var lo := INF
		for v in vs.size():
			lo = minf(lo, out[v].y)
		print(slot, " after the bones: lowest ", snapped(lo, 0.001))
	# 2. Out of her body, the push smoothed over the cloth.
	var nbr := _neighbours(vs.size(), idx, vs)
	for round_ in 3:
		var need := PackedVector3Array()
		need.resize(vs.size())
		for v in vs.size():
			var near := _nearest(cb, out[v], 1)
			if near.is_empty():
				continue
			var q: Vector3 = cb.pos[near[0][1]]
			var n: Vector3 = cb.nor[near[0][1]]
			var s := (out[v] - q).dot(n)
			if near[0][1] >= cb.skin_n and s < -0.015:
				continue   # a garment's inner face (two-sided cloth): its normal points in
			if s < GAP:
				need[v] = n * (GAP - s)
		var d := need.duplicate()
		for it in 12:
			var nd := PackedVector3Array()
			nd.resize(vs.size())
			for v in vs.size():
				var avg := Vector3.ZERO
				var ns_: Array = nbr[v]
				for u in ns_:
					avg += d[u]
				avg = avg / ns_.size() if ns_.size() > 0 else d[v]
				var m := d[v].lerp(avg, 0.5)
				# Never less than it needs along its own push.
				if need[v] != Vector3.ZERO and m.dot(need[v].normalized()) < need[v].length():
					m += need[v].normalized() * (need[v].length() - m.dot(need[v].normalized()))
				nd[v] = m
			d = nd
		for v in vs.size():
			out[v] += d[v]
	if OS.has_environment("FIT_DEBUG"):
		var lo2 := INF
		for v in vs.size():
			lo2 = minf(lo2, out[v].y)
		print(slot, " after the push: lowest ", snapped(lo2, 0.001))
	# 3. Her skin's weights (three nearest), a skirt below the hips half on the pelvis.
	var pelvis_bind := _bind_index(body_c.skin, skc, Gait.find_bone(skc, "DEF-spine"))
	var hip_y := minf(_gc("DEF-thigh.L").y, _gc("DEF-thigh.R").y)
	var crotch_y := hip_y - 0.12
	var nb := PackedInt32Array()
	var nw := PackedFloat32Array()
	nb.resize(vs.size() * 4)
	nw.resize(vs.size() * 4)
	for v in vs.size():
		var near := _nearest(cb, out[v], 3, true)
		var mix := {}
		var tot := 0.0
		for e in near:
			if e[1] >= cb.skin_n:
				continue   # a garment under it: no weights there
			var w := 1.0 / maxf(sqrt(e[0]), 0.002)
			tot += w
			for k in cb.per:
				var bw: float = cb.weights[e[1] * cb.per + k]
				if bw > 0.0:
					var bi: int = cb.bones[e[1] * cb.per + k]
					mix[bi] = mix.get(bi, 0.0) + bw * w
		if slot == "dress" and out[v].y < hip_y:
			var k := smoothstep(hip_y, crotch_y, out[v].y) * 0.5
			var sum := 0.0
			for bi in mix:
				sum += mix[bi]
			for bi in mix:
				mix[bi] *= 1.0 - k
			mix[pelvis_bind] = mix.get(pelvis_bind, 0.0) + sum * k
		if mix.is_empty():
			mix[pelvis_bind] = 1.0   # never weightless: such a vertex falls to the origin
		var order := mix.keys()
		order.sort_custom(func(x, y): return mix[x] > mix[y])
		var kept := 0.0
		for k in mini(4, order.size()):
			kept += mix[order[k]]
		for k in 4:
			nb[v * 4 + k] = order[k] if k < order.size() else 0
			nw[v * 4 + k] = mix[order[k]] / kept if k < order.size() and kept > 0.0 else 0.0
	# Into the bunny's mesh space (her rest * bind is the identity: skeleton space).
	var new_arr := []
	new_arr.resize(Mesh.ARRAY_MAX)
	new_arr[Mesh.ARRAY_VERTEX] = out
	new_arr[Mesh.ARRAY_NORMAL] = nout
	new_arr[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
	new_arr[Mesh.ARRAY_INDEX] = idx
	new_arr[Mesh.ARRAY_BONES] = nb
	new_arr[Mesh.ARRAY_WEIGHTS] = nw
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arr)
	mesh.surface_set_material(0, _material(g.mesh.surface_get_material(0) if g.get_surface_override_material(0) == null else g.get_surface_override_material(0), GARMENTS[g.name][0]))
	return mesh


## The skirt's own width at Agnes' hip line (an ellipse round between her hip joints).
func _measure_hip_line(g: MeshInstance3D) -> void:
	var arr := g.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bb.size() / vs.size()
	var ax := 0.0
	var az := 0.0
	for v in vs.size():
		var p := _rest_pos(g, ska, vs[v], bb, ww, per, v)
		if absf(p.y - hip_a) < 0.02:
			ax = maxf(ax, absf(p.x - skirt.a0.x))
			az = maxf(az, absf(p.z - skirt.a0.z))
	skirt.ax = maxf(ax, 0.05)
	skirt.az = maxf(az, 0.05)
	print("skirt at the hip line: ", snapped(ax, 0.001), " x ", snapped(az, 0.001))


## Adds a fitted garment's surface to what later garments are pushed out of (no weights: those
## come from her skin only).
func _add_layer(cb: Dictionary, mesh: ArrayMesh) -> void:
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var pos: PackedVector3Array = cb.pos
	var nor: PackedVector3Array = cb.nor
	for v in vs.size():
		var i := pos.size()
		pos.append(vs[v])
		nor.append(ns[v])
		var key := Vector3i((vs[v] / 0.03).floor())
		var cell: PackedInt32Array = cb.grid.get(key, PackedInt32Array())
		cell.append(i)
		cb.grid[key] = cell
	cb.pos = pos
	cb.nor = nor


func _bind_index(skin: Skin, sk: Skeleton3D, bone: int) -> int:
	for i in skin.get_bind_count():
		if skin.get_bind_bone(i) == bone or sk.find_bone(skin.get_bind_name(i)) == bone:
			return i
	return 0


## Each vertex's neighbours over the triangles (and the same position across seams).
func _neighbours(n: int, idx: PackedInt32Array, vs: PackedVector3Array) -> Array:
	var sets := []
	sets.resize(n)
	for i in n:
		sets[i] = {}
	for t in idx.size() / 3:
		for e in 3:
			var a := idx[t * 3 + e]
			var b := idx[t * 3 + (e + 1) % 3]
			sets[a][b] = true
			sets[b][a] = true
	var weld := {}
	for v in n:
		var key := Vector3i((vs[v] * 5000.0).round())
		if weld.has(key):
			var u: int = weld[key]
			sets[v][u] = true
			sets[u][v] = true
			for x in sets[u]:
				sets[v][x] = true
		else:
			weld[key] = v
	var out := []
	out.resize(n)
	for i in n:
		out[i] = sets[i].keys()
	return out


## Her albedo, scaled down for the phone, drawn unshaded like the bunny.
func _material(src: Material, name: String) -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
		var img := (src as BaseMaterial3D).albedo_texture.get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(TEX, TEX, Image.INTERPOLATE_LANCZOS)
		var path := OUT + name + "_albedo.png"
		if ResourceLoader.exists(path):
			mat.albedo_texture = load(path)   # imported (second run): referenced, not copied in
		else:
			img.save_png(ProjectSettings.globalize_path(path))
			mat.albedo_texture = ImageTexture.create_from_image(img)
			print("wrote ", path, ": import and run again to reference it")
		if (src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return mat
