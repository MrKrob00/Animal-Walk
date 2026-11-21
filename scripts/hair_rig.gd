class_name HairRig
extends RefCounted
## Bones for her hair, made at load (the player asked how to give hair a skeleton properly and
## cheaply). The model's hair is ~15 shells all skinned rigidly to the head. The cheap, standard
## way (VRM spring bones, VRChat phys bones) is a short chain per strand on springs that return
## it to its shape, with a few spheres it slides round (skull, neck, shoulders): Godot's own
## SpringBoneSimulator3D does it in native code.
##   1. Hair: the head's mesh islands (welded by position) that are mostly hair-red in the
##      texture and big (the small red ones are brows and lashes; the scalp cap stays rigid).
##   2. A chain per island: two bones from the point nearest the skull's middle to the point
##      furthest from it (a strand hangs, a curl stands up); an island wider than WIDE is cut
##      into its left and right halves, each with its chain.
##   3. Weights: the head near the root, the chain's bones along the strand (eased), so the
##      strand bends rather than swings as a stick.
##   4. HairSprings drives the chains (the spring-bone method in world metres: Godot's
##      SpringBoneSimulator3D swung the strands 30 cm moving, on our scaled skeleton), with
##      spheres on the head, face, neck, shoulders and upper back.

const HAIR_SHARE := 0.9     ## an island this much hair-red is hair
const MIN_VERTS := 100      ## smaller red islands are brows, lashes and the like
const SKULL := Vector3(0.0, 0.12, 0.0)   ## the skull's middle from the head bone (metres)


## Builds it all for `actor` (its map's "hair": {"mesh", "head", "spheres"}). Returns the springs.
static func build(actor: Node3D, skel: Skeleton3D, cfg: Dictionary) -> HairSprings:
	var m: MeshInstance3D = actor.find_child(cfg.mesh, true, false)
	var head := Gait.find_bone(skel, cfg.head)
	if m == null or head < 0:
		return null
	var scale := skel.global_transform.basis.get_scale().x   # metres per skeleton unit
	m.skin = m.skin.duplicate()   # her own: the file's skin is shared by every copy of her (the dressing room's too)
	var arr: Array = m.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bb.size() / vs.size()
	var head_bind := _bind_of(m.skin, skel, head)
	var to_sk: Transform3D = skel.get_bone_global_rest(head) * m.skin.get_bind_pose(head_bind)   # mesh -> skeleton space at rest
	var head_rest := skel.get_bone_global_rest(head)
	var islands := _hair_islands(m, arr, per, head_bind)
	var skull := head_rest.origin + head_rest.basis.orthonormalized() * (SKULL / scale)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var chains := []   # [{island, root, mid, tip}]
	var island_chains := []   # per island: the chains' indices
	for isl in islands:
		var mine := []
		for sp in _spikes(isl, vs, idx, to_sk, skull, scale):
			mine.append(chains.size())
			chains.append(sp)
		island_chains.append(mine)
	# Bones: root -> mid -> tip under the head, each turned so its Y points along the strand.
	var bones := []
	for c in chains.size():
		var ch: Dictionary = chains[c]
		var ids := []
		var parent := head
		var parent_global := head_rest
		for j in 3:
			var at: Vector3 = [ch.root, ch.mid, ch.tip][j]
			var next: Vector3 = ch.tip + (ch.tip - ch.mid) * 0.3 if j == 2 else [ch.mid, ch.tip][j]
			var g := Transform3D(_toward(next - at), at)
			var b := skel.add_bone("hair_%d_%d" % [c, j])
			skel.set_bone_parent(b, parent)
			skel.set_bone_rest(b, parent_global.affine_inverse() * g)
			skel.reset_bone_pose(b)
			m.skin.add_named_bind("hair_%d_%d" % [c, j], g.affine_inverse() * to_sk)
			ids.append([b, m.skin.get_bind_count() - 1])
			parent = b
			parent_global = g
		bones.append(ids)
	# Weights: each hair vertex follows the nearest one or two of its island's strands (so the
	# strands of one piece swing apart, blending smoothly between), from the head at the root to
	# the strand's two bones along it.
	for i in islands.size():
		var mine: Array = island_chains[i]
		if mine.is_empty():
			continue
		for v in islands[i]:
			var p: Vector3 = to_sk * vs[v]
			var near := []   # [distance, chain, t]
			for c in mine:
				var ch: Dictionary = chains[c]
				var d1 := _seg_t(p, ch.root, ch.mid)
				var d2 := _seg_t(p, ch.mid, ch.tip)
				var d: float
				var t: float
				if d1[0] <= d2[0]:
					d = d1[0]
					t = d1[1] * 0.5
				else:
					d = d2[0]
					t = 0.5 + d2[1] * 0.5
				near.append([d, c, t])
			near.sort_custom(func(x, y): return x[0] < y[0])
			var mix := {}
			var use := near.slice(0, 2)
			var tot := 0.0
			for n in use:
				tot += 1.0 / maxf(n[0] * n[0], 1e-6)
			for n in use:
				var a := (1.0 / maxf(n[0] * n[0], 1e-6)) / tot
				var s_ := smoothstep(0.05, 0.4, n[2])
				var u := smoothstep(0.4, 0.8, n[2])
				mix[head_bind] = mix.get(head_bind, 0.0) + a * (1.0 - s_)
				mix[bones[n[1]][0][1]] = mix.get(bones[n[1]][0][1], 0.0) + a * s_ * (1.0 - u)
				mix[bones[n[1]][1][1]] = mix.get(bones[n[1]][1][1], 0.0) + a * s_ * u
			var order := mix.keys()
			order.sort_custom(func(x, y): return mix[x] > mix[y])
			var kept := 0.0
			for k in mini(per, order.size()):
				kept += mix[order[k]]
			for k in per:
				bb[v * per + k] = order[k] if k < order.size() else 0
				ww[v * per + k] = mix[order[k]] / kept if k < order.size() and kept > 0.0 else 0.0
	arr[Mesh.ARRAY_BONES] = bb
	arr[Mesh.ARRAY_WEIGHTS] = ww
	var mesh := ArrayMesh.new()
	var flags: int = m.mesh.surface_get_format(0) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
	mesh.add_surface_from_arrays(m.mesh.surface_get_primitive_type(0), arr, [], {}, flags)
	mesh.surface_set_material(0, m.mesh.surface_get_material(0))
	var keep := m.get_surface_override_material(0)
	m.mesh = mesh
	if keep != null:
		m.set_surface_override_material(0, keep)
	var ids := []
	for ch in bones:
		ids.append(ch.map(func(x): return x[0]))
	return HairSprings.new(skel, ids, cfg.get("spheres", []))


## Chains across a hair piece, like the sticks in a rigged hairdo the player showed: one every
## SPACING metres round the head (by the angle about the skull's upright axis), each from the
## piece's top (nearest the skull) to its tip (furthest) within its slice. Her hair is ~15 shells
## that are mostly one strand each, but wide: one chain per piece swung it as a stiff plate.
const SPACING := 0.045     ## metres between chains round the head
const MAX_PER := 5
static func _spikes(isl: Array, vs: PackedVector3Array, idx: PackedInt32Array, to_sk: Transform3D, skull: Vector3, scale: float) -> Array:
	var h := {}
	var ang := {}
	var lo := INF
	var hi := -INF
	var mean := Vector2.ZERO
	for v in isl:
		var p: Vector3 = to_sk * vs[v]
		h[v] = p.distance_to(skull)
		lo = minf(lo, h[v])
		hi = maxf(hi, h[v])
		mean += Vector2(p.x - skull.x, p.z - skull.z).normalized()
	if (hi - lo) * scale < 0.04:
		return []   # no length from the scalp: the cap
	var a0 := mean.angle()
	var a_lo := INF
	var a_hi := -INF
	var rad := 0.0
	for v in isl:
		var p: Vector3 = to_sk * vs[v]
		var d := Vector2(p.x - skull.x, p.z - skull.z)
		ang[v] = angle_difference(a0, d.angle())
		a_lo = minf(a_lo, ang[v])
		a_hi = maxf(a_hi, ang[v])
		rad += d.length() / isl.size()
	var width := (a_hi - a_lo) * rad * scale
	var n := clampi(roundi(width / SPACING), 1, MAX_PER)
	var out := []
	for k in n:
		var c := lerpf(a_lo, a_hi, (k + 0.5) / n)
		var half := (a_hi - a_lo) / n * 0.5
		var slice := []
		for v in isl:
			if absf(ang[v] - c) <= half + 1e-4:
				slice.append(v)
		if slice.size() < 6:
			continue
		var root_v: int = slice[0]
		var tip_v: int = slice[0]
		for v in slice:
			if h[v] < h[root_v]:
				root_v = v
			if h[v] > h[tip_v]:
				tip_v = v
		var root: Vector3 = to_sk * vs[root_v]
		var tip: Vector3 = to_sk * vs[tip_v]
		if root.distance_to(tip) * scale < 0.035:
			continue
		var mid := Vector3.ZERO
		var m := 0
		for v in slice:
			var st := _seg_t(to_sk * vs[v], root, tip)
			if absf(st[1] - 0.5) < 0.15:
				mid += to_sk * vs[v]
				m += 1
		mid = mid / m if m > 0 else root.lerp(tip, 0.5)
		out.append({"root": root, "mid": mid, "tip": tip})
	return out


## [distance from `p` to the segment a-b, how far along it (0..1)].
static func _seg_t(p: Vector3, a: Vector3, b: Vector3) -> Array:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return [p.distance_to(a + ab * t), t]


static func _bind_of(skin: Skin, skel: Skeleton3D, bone: int) -> int:
	for i in skin.get_bind_count():
		if skin.get_bind_bone(i) == bone or skel.find_bone(skin.get_bind_name(i)) == bone:
			return i
	return -1


## A basis whose Y points along `d`.
static func _toward(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y).normalized() * -1.0).orthonormalized()


## The head's islands that are hair: mostly hair-red in the texture, and big.
static func _hair_islands(m: MeshInstance3D, arr: Array, per: int, head_bind: int) -> Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var mat := m.mesh.surface_get_material(0) as BaseMaterial3D
	var img: Image = mat.albedo_texture.get_image() if mat != null and mat.albedo_texture != null else null
	if img == null:
		return []
	if img.is_compressed():
		img.decompress()
	var size := img.get_size()
	var kind := PackedByteArray()   # 0 not head, 2 head, 3 head and hair-red
	kind.resize(vs.size())
	for v in vs.size():
		var hw := 0.0
		for k in per:
			if bb[v * per + k] == head_bind:
				hw += ww[v * per + k]
		if hw < 0.5:
			continue
		var px := Vector2i(int(fposmod(uv[v].x, 1.0) * size.x), int(fposmod(uv[v].y, 1.0) * size.y)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
		var c := img.get_pixelv(px)
		kind[v] = 3 if c.r > 0.45 and c.g < c.r * 0.6 and c.b < c.r * 0.55 else 2
	var parent := PackedInt32Array()
	parent.resize(vs.size())
	for v in vs.size():
		parent[v] = v
	var root_of := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	var weld := {}
	for v in vs.size():
		if kind[v] < 2:
			continue
		var key := Vector3i((vs[v] * 2000.0).round())
		if weld.has(key):
			parent[root_of.call(v)] = root_of.call(weld[key])
		else:
			weld[key] = v
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		if kind[a] >= 2 and kind[b] >= 2 and kind[c] >= 2:
			parent[root_of.call(b)] = root_of.call(a)
			parent[root_of.call(c)] = root_of.call(a)
	var groups := {}
	for v in vs.size():
		if kind[v] < 2:
			continue
		var r: int = root_of.call(v)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(v)
	var out := []
	for g in groups.values():
		if g.size() < MIN_VERTS:
			continue
		var red := 0
		for v in g:
			if kind[v] == 3:
				red += 1
		if float(red) / g.size() >= HAIR_SHARE:
			out.append(g)
	return out
