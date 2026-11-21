class_name SkirtRig
extends RefCounted
## Bones for a skirt, made at load (the player saw her leg go through the sundress: it was skinned
## to her pelvis and the skin under it, so a thigh stepping forward went out through the cloth).
## The standard cheap way, as for her hair (VRM / VRChat skirts): a ring of short chains from the
## hip line down to the hem, on springs (HairSprings) that keep the skirt's shape, with her legs
## as capsules that push the chains aside. Below the hip line the cloth follows the nearest two
## chains (by the angle round her), above it its old weights, blended over a narrow band.
##   cfg: {"mesh", "pelvis", "thighs": [l, r], "legs": [[bone a, bone b, radius m], ...]}

const CHAINS := 20          ## chains round the skirt
const BAND := 0.03          ## skeleton units above the hip line where the old weights blend in
const FIT_MIN := 0.85        ## a leg capsule narrows at most this far to clear the dress at rest
const NEAR := 0.02          ## skeleton units: vertices this close to a height make its ring


static func build(actor: Node3D, skel: Skeleton3D, cfg: Dictionary) -> HairSprings:
	var m: MeshInstance3D = actor.find_child(cfg.mesh, true, false)
	var pel := Gait.find_bone(skel, cfg.pelvis)
	var tl := Gait.find_bone(skel, cfg.thighs[0])
	var tr := Gait.find_bone(skel, cfg.thighs[1])
	if m == null or m.skin == null or pel < 0 or tl < 0 or tr < 0:
		return null
	m.skin = m.skin.duplicate()   # her own: the file's skin is shared by every copy of her
	var pel_bind := HairRig._bind_of(m.skin, skel, pel)
	var to_sk: Transform3D = skel.get_bone_global_rest(pel) * m.skin.get_bind_pose(pel_bind)   # mesh -> skeleton space at rest
	var arr: Array = m.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bb.size() / vs.size()
	var hl := skel.get_bone_global_rest(tl).origin
	var hr := skel.get_bone_global_rest(tr).origin
	var hip_y := (hl.y + hr.y) * 0.5
	var c := (hl + hr) * 0.5
	# The skirt's vertices below the hip line, by their angle round her.
	var pts := []   # skeleton space
	pts.resize(vs.size())
	var bins := []
	for k in CHAINS:
		bins.append([])
	for v in vs.size():
		var p: Vector3 = to_sk * vs[v]
		pts[v] = p
		if p.y < hip_y + NEAR:
			bins[_bin(p, c)].append(v)
	# A chain per bin: on the cloth's outside at the hip line, halfway down and at the hem.
	var chains := []   # [{root, mid, tip, hem_y}] or null
	for k in CHAINS:
		var lo := INF
		for v in bins[k]:
			lo = minf(lo, pts[v].y)
		if lo > hip_y - 0.05:
			chains.append(null)   # no skirt there
			continue
		var az := (k + 0.5) / CHAINS * TAU
		var dir := Vector3(sin(az), 0.0, cos(az))
		var ring := func(y: float) -> Vector3:
			var r := 0.0
			for v in bins[k]:
				if absf(pts[v].y - y) < NEAR:
					var d: Vector3 = pts[v] - c
					r = maxf(r, Vector2(d.x, d.z).length())
			return Vector3(c.x, y, c.z) + dir * r
		chains.append({"root": ring.call(hip_y), "mid": ring.call((hip_y + lo) * 0.5), "tip": ring.call(lo + NEAR * 0.5), "hem_y": lo})
	# Bones: root -> mid -> tip under the pelvis, each with its Y along the cloth.
	var bones := []   # per chain: [[bone, bind] x3] or null
	var pel_rest := skel.get_bone_global_rest(pel)
	for k in CHAINS:
		var ch = chains[k]
		if ch == null:
			bones.append(null)
			continue
		var ids := []
		var parent := pel
		var parent_global := pel_rest
		for j in 3:
			var at: Vector3 = [ch.root, ch.mid, ch.tip][j]
			var next: Vector3 = ch.tip + (ch.tip - ch.mid) * 0.3 if j == 2 else [ch.mid, ch.tip][j]
			var g := Transform3D(HairRig._toward(next - at), at)
			var name := "skirt_%d_%d" % [k, j]
			var b := skel.add_bone(name)
			skel.set_bone_parent(b, parent)
			skel.set_bone_rest(b, parent_global.affine_inverse() * g)
			skel.reset_bone_pose(b)
			m.skin.add_named_bind(name, g.affine_inverse() * to_sk)
			ids.append([b, m.skin.get_bind_count() - 1])
			parent = b
			parent_global = g
		bones.append(ids)
	# Weights: the two chains either side of the vertex's angle, the upper bone down to the
	# middle and the lower one below it (blended round the middle joint); above the hip line
	# the old weights come back over BAND.
	for v in vs.size():
		var p: Vector3 = pts[v]
		if p.y > hip_y + BAND:
			continue
		var f: float = (atan2(p.x - c.x, p.z - c.z) / TAU) * CHAINS - 0.5
		f = fposmod(f, CHAINS)
		var k0 := int(floor(f)) % CHAINS
		var k1 := (k0 + 1) % CHAINS
		var a1: float = f - floor(f)
		var pair := [[k0, 1.0 - a1], [k1, a1]]
		pair = pair.filter(func(e): return bones[e[0]] != null)
		if pair.is_empty():
			continue
		var tot := 0.0
		for e in pair:
			tot += e[1]
		if tot <= 1e-6:
			pair = [pair[0]]
			pair[0][1] = 1.0
			tot = 1.0
		var hem := 0.0
		for e in pair:
			hem += chains[e[0]].hem_y * e[1] / tot
		var t := clampf((hip_y - p.y) / maxf(hip_y - hem, 1e-4), 0.0, 1.0)
		var u := smoothstep(0.35, 0.65, t)
		var mix := {}
		for e in pair:
			var w: float = e[1] / tot
			mix[bones[e[0]][0][1]] = mix.get(bones[e[0]][0][1], 0.0) + w * (1.0 - u)
			mix[bones[e[0]][1][1]] = mix.get(bones[e[0]][1][1], 0.0) + w * u
		var keep := smoothstep(hip_y, hip_y + BAND, p.y)   # the old weights, above the hip line
		if keep > 0.0:
			for x in mix:
				mix[x] *= 1.0 - keep
			for q in per:
				var wq := ww[v * per + q]
				if wq > 0.0:
					mix[bb[v * per + q]] = mix.get(bb[v * per + q], 0.0) + wq * keep
		var order := mix.keys()
		order.sort_custom(func(x, y): return mix[x] > mix[y])
		var kept := 0.0
		for q in mini(per, order.size()):
			kept += mix[order[q]]
		for q in per:
			bb[v * per + q] = order[q] if q < order.size() else 0
			ww[v * per + q] = mix[order[q]] / kept if q < order.size() and kept > 0.0 else 0.0
	arr[Mesh.ARRAY_BONES] = bb
	arr[Mesh.ARRAY_WEIGHTS] = ww
	var mesh := ArrayMesh.new()
	var flags: int = m.mesh.surface_get_format(0) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
	mesh.add_surface_from_arrays(m.mesh.surface_get_primitive_type(0), arr, [], {}, flags)
	mesh.surface_set_material(0, m.mesh.surface_get_material(0))
	var over := m.get_surface_override_material(0)
	m.mesh = mesh
	if over != null:
		m.set_surface_override_material(0, over)
	var ids := []
	for ch in bones:
		if ch != null:
			ids.append(ch.map(func(x): return x[0]))
	var s := HairSprings.new(skel, ids, [])
	s.set_capsules(cfg.get("legs", []))
	s.out_from = pel
	s.joint_r = 0.008
	_fit_capsules(s, skel, chains)
	s.stiffness = 10.0
	s.drag = 0.25
	s.gravity = 1.0
	s.max_angle = deg_to_rad(85.0)
	s.inertia = 0.3
	return s


## Narrows each leg capsule where the dress already lies closer at rest (her T-pose), so standing
## still the skirt keeps the shape it was fitted with and only a leg moving into it pushes it.
static func _fit_capsules(s: HairSprings, skel: Skeleton3D, chains: Array) -> void:
	var unit := skel.global_transform.basis.get_scale().x   # metres per skeleton unit
	for cap in s.capsules:
		if cap[0] < 0 or cap[1] < 0:
			continue
		var a := skel.get_bone_global_rest(cap[0]).origin
		var b := skel.get_bone_global_rest(cap[1]).origin
		var k := 1.0
		for ch in chains:
			if ch == null:
				continue
			for p: Vector3 in [ch.mid, ch.tip]:
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
				var d := (p - (a + ab * t)).length() * unit - s.joint_r - 0.003
				var r: float = lerpf(cap[2], cap[3], t)
				if r > 0.0:
					k = minf(k, maxf(d, 0.0) / r)
		for j in [2, 3, 4, 5]:
			cap[j] *= maxf(k, FIT_MIN)


static func _bin(p: Vector3, c: Vector3) -> int:
	var f := atan2(p.x - c.x, p.z - c.z) / TAU
	return int(floor(fposmod(f, 1.0) * CHAINS)) % CHAINS
