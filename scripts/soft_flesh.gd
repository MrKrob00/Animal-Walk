class_name SoftFlesh
extends RefCounted
## Soft flesh with no bones of its own (the player: her hips, butt and thighs are big; soft and
## springy like her chest, and her belly too): each skin vertex gets a share in three regions -
## her left butt-and-thigh, her right one, her belly - stored in the mesh (CUSTOM0 r, g, b).
## Gait runs one spring per region (`Gait.flesh_*`), and the soft-press shader moves each vertex
## by its regions' springs, so the flesh lags, jiggles and gives where a paw presses it, while
## the bones (and the legs' motion) are untouched. Her shorts get the same shares from the same
## weights (SkinFit gave them the skin's), so they move with the skin under them.
## Shares come from the bone weights: the butt bones, the thighs (their lower half at half),
## the pelvis' back on each side, and the lower spine's front for the belly.

const REGIONS := ["L", "R", "belly"]
const LOWER_THIGH := 0.5   ## share of the thigh's lower half (toward the knee)
const SIDE_FADE := 0.06    ## metres either side of the middle where left fades into right
const ANCHOR := ["DEF-spine", "DEF-spine", "DEF-spine.001"]   ## the bone each region's spring rides on


## Writes the shares into every skinned mesh under `model` that has any; returns the regions:
## [{"bone": int, "local": Vector3 (the region's centre in the bone's frame, rest),
##   "radius": float (metres from the centre to its skin)}].
static func apply(model: Node3D, skel: Skeleton3D, fwd_sk: Vector3, side_sk: Vector3, only: Array = []) -> Array:
	var id := func(n: String) -> int: return Gait.find_bone(skel, n)
	var bones := {
		"butt_l": id.call("DEF-butt.L"), "butt_r": id.call("DEF-butt.R"),
		"thigh_l": id.call("DEF-thigh.L"), "thigh_r": id.call("DEF-thigh.R"),
		"thigh2_l": id.call("DEF-thigh.L.001"), "thigh2_r": id.call("DEF-thigh.R.001"),
		"pelvis": id.call("DEF-spine"), "spine1": id.call("DEF-spine.001"), "spine2": id.call("DEF-spine.002"),
	}
	var sum := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var wsum := [0.0, 0.0, 0.0]
	var pts := [[], [], []]   # strongly held points, for the radius
	var scale := skel.global_transform.basis.get_scale().x
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.skin == null or m.mesh == null or (not only.is_empty() and not (m.name in only)):
			continue   # (her top stays out: given the belly's share, its hem turned inside out)
		var bind_bone := PackedInt32Array()
		var bind_xf := []
		for b in m.skin.get_bind_count():
			var bone := m.skin.get_bind_bone(b)
			if bone < 0:
				bone = skel.find_bone(m.skin.get_bind_name(b))
			bind_bone.append(bone)
			bind_xf.append((skel.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY) * m.skin.get_bind_pose(b))
		var mesh := ArrayMesh.new()
		var any := false
		for sf in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(sf)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bb.size() / maxi(vs.size(), 1)
			var custom := PackedFloat32Array()
			custom.resize(vs.size() * 4)
			for v in vs.size():
				var w := {}
				var p := Vector3.ZERO
				var n := Vector3.ZERO
				for k in per:
					var wt := ww[v * per + k]
					if wt <= 0.0:
						continue
					var bind := bb[v * per + k]
					var xf: Transform3D = bind_xf[bind]
					p += (xf * vs[v]) * wt
					if ns.size() == vs.size():
						n += (xf.basis * ns[v]) * wt
					var bone := bind_bone[bind]
					w[bone] = w.get(bone, 0.0) + wt
				n = n.normalized() if n.length() > 1e-6 else Vector3.ZERO
				var front := n.dot(fwd_sk)
				var side := (p - skel.get_bone_global_rest(bones.pelvis).origin).dot(side_sk) * scale   # metres, + = her left
				var back := smoothstep(0.0, 0.5, -front)
				var pel: float = w.get(bones.pelvis, 0.0)
				var l: float = w.get(bones.butt_l, 0.0) + w.get(bones.thigh_l, 0.0) + LOWER_THIGH * w.get(bones.thigh2_l, 0.0) + pel * back * smoothstep(-SIDE_FADE, SIDE_FADE, side)
				var r: float = w.get(bones.butt_r, 0.0) + w.get(bones.thigh_r, 0.0) + LOWER_THIGH * w.get(bones.thigh2_r, 0.0) + pel * back * smoothstep(-SIDE_FADE, SIDE_FADE, -side)
				var belly: float = (w.get(bones.spine1, 0.0) + 0.6 * pel) * smoothstep(0.1, 0.6, front)
				var share := [minf(l, 1.0), minf(r, 1.0), minf(belly, 1.0)]
				for k in 3:
					custom[v * 4 + k] = share[k]
					if share[k] > 0.05:
						any = true
						sum[k] += p * share[k] * share[k]
						wsum[k] += share[k] * share[k]
						if share[k] > 0.7:
							pts[k].append(p)
			arr[Mesh.ARRAY_CUSTOM0] = custom
			var flags: int = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (m.mesh.surface_get_format(sf) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			mesh.add_surface_from_arrays(m.mesh.surface_get_primitive_type(sf), arr, [], {}, flags)
			mesh.surface_set_material(sf, m.mesh.surface_get_material(sf))
			mesh.surface_set_name(sf, m.mesh.surface_get_name(sf))
		if any:
			m.mesh = mesh
	var out := []
	for k in 3:
		var bone: int = id.call(ANCHOR[k])
		var c: Vector3 = sum[k] / maxf(wsum[k], 1e-6)
		var ds := []
		for p in pts[k]:
			ds.append((p as Vector3).distance_to(c) * scale)
		ds.sort()
		var rad: float = ds[ds.size() / 2] if not ds.is_empty() else 0.08
		out.append({"bone": bone, "local": skel.get_bone_global_rest(bone).affine_inverse() * c, "radius": rad})
	return out
