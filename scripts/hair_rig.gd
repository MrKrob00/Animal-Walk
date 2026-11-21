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
const WIDE := 0.15          ## metres: a wider island is cut into left and right chains
const CAP_HIGH := 0.17      ## an island all above this over the head bone is the scalp cap (rigid)
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
	var side_axis := Vector3.RIGHT   # the skeleton's own: she faces +Z, her left is +X
	var chains := []   # [{verts, root, mid, tip}]
	for isl in islands:
		var pts := []
		var lo := INF
		var w_min := INF
		var w_max := -INF
		for v in isl:
			var p: Vector3 = to_sk * vs[v]
			pts.append(p)
			lo = minf(lo, (p - head_rest.origin).y * scale)
			w_min = minf(w_min, p.dot(side_axis))
			w_max = maxf(w_max, p.dot(side_axis))
		if lo > CAP_HIGH:
			continue   # the scalp cap
		var groups := [isl]
		if (w_max - w_min) * scale > WIDE:
			var left := []
			var right := []
			for v in isl:
				if (to_sk * vs[v]).dot(side_axis) >= (skull.dot(side_axis)):
					left.append(v)
				else:
					right.append(v)
			groups = [left, right]
		for g in groups:
			if g.size() < 20:
				continue
			var near: Vector3 = to_sk * vs[g[0]]
			var far: Vector3 = near
			for v in g:
				var p: Vector3 = to_sk * vs[v]
				if p.distance_to(skull) < near.distance_to(skull):
					near = p
				if p.distance_to(skull) > far.distance_to(skull):
					far = p
			if near.distance_to(far) * scale < 0.04:
				continue
			# The middle joint: the strand's middle, where it is halfway from root to tip.
			var mid := Vector3.ZERO
			var n := 0
			var axis := far - near
			for v in g:
				var p: Vector3 = to_sk * vs[v]
				var t := (p - near).dot(axis) / axis.length_squared()
				if absf(t - 0.5) < 0.12:
					mid += p
					n += 1
			mid = mid / n if n > 0 else near.lerp(far, 0.5)
			chains.append({"verts": g, "root": near, "mid": mid, "tip": far})
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
	# Weights along each strand: the head at the root, then its two bones.
	for c in chains.size():
		var ch: Dictionary = chains[c]
		var axis: Vector3 = ch.tip - ch.root
		for v in ch.verts:
			var p: Vector3 = to_sk * vs[v]
			var t := clampf((p - ch.root).dot(axis) / axis.length_squared(), 0.0, 1.0)
			var s := smoothstep(0.05, 0.4, t)
			var u := smoothstep(0.4, 0.8, t)
			var ws := [1.0 - s, s * (1.0 - u), s * u]
			var bs := [head_bind, bones[c][0][1], bones[c][1][1]]
			for k in per:
				bb[v * per + k] = bs[k] if k < 3 else 0
				ww[v * per + k] = ws[k] if k < 3 else 0.0
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
