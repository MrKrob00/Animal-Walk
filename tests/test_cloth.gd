extends SceneTree
## The bunny's top stays on the skin under it while she runs (no gap opens at the chest):
## both are skinned on the CPU here, and each top vertex's distance to the skin point under it
## may change only a little from rest.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	a.set_process(false)
	var sk := a.skeleton
	var top: MeshInstance3D = a.find_child(Actor.BUNNY.cloth.items[0], true, false)
	var skin_mi: MeshInstance3D = a.find_child(Actor.BUNNY.cloth.body, true, false)
	var t_arr := top.mesh.surface_get_arrays(0)
	var b_arr := skin_mi.mesh.surface_get_arrays(0)
	var t_v: PackedVector3Array = t_arr[Mesh.ARRAY_VERTEX]
	var b_v: PackedVector3Array = b_arr[Mesh.ARRAY_VERTEX]
	# The skin under each top vertex (its six nearest skin points at rest), every 4th vertex.
	var pairs := []
	for i in range(0, t_v.size(), 4):
		var near := []
		for j in b_v.size():
			if _on_arm(skin_mi, b_arr, j):
				continue
			var d := t_v[i].distance_squared_to(b_v[j])
			if near.size() < 6 or d < near[-1][0]:
				near.append([d, j])
				near.sort_custom(func(x, y): return x[0] < y[0])
				if near.size() > 6:
					near.pop_back()
		var ids := []
		for n in near:
			ids.append(n[1])
		pairs.append([i, ids])
	var rest := _gaps(sk, top, skin_mi, t_arr, b_arr, pairs)
	var worst := 0.0
	var all := []
	for f in 150:
		a.position += a.global_basis.z * 3.6 / 60.0
		a.animate(1.0 / 60.0, 3.6)
		if f % 10 == 0:
			var now := _gaps(sk, top, skin_mi, t_arr, b_arr, pairs)
			for k in now.size():
				worst = maxf(worst, absf(now[k] - rest[k]))
				all.append(absf(now[k] - rest[k]))
	all.sort()
	var p95: float = all[int(all.size() * 0.95)]
	# With the model's own top weights it was 20 mm and 57 mm (to the single nearest skin point).
	Check.ok(p95 < 0.008, "running, the top stays on the skin (95%% of it within %.1f mm)" % (p95 * 1000.0))
	Check.ok(worst < 0.02, "and nowhere pulls far off it (at most %.1f mm)" % (worst * 1000.0))
	Check.finish(self)


func _on_arm(mi: MeshInstance3D, arr: Array, i: int) -> bool:
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var off := 0.0
	for k in per:
		var n := String(mi.skin.get_bind_name(bones[i * per + k]))
		for pre in Actor.BUNNY.cloth.skip:
			if n.begins_with(pre):
				off += weights[i * per + k]
	return off > 0.3



## Distance (metres) from each top vertex to the skin under it (the nearest of its skin points),
## both skinned.
func _gaps(sk: Skeleton3D, top: MeshInstance3D, body: MeshInstance3D, t_arr: Array, b_arr: Array, pairs: Array) -> Array:
	var out := []
	for p in pairs:
		var tp := _skinned(sk, top, t_arr, p[0])
		var best := INF
		for j in p[1]:
			best = minf(best, tp.distance_to(_skinned(sk, body, b_arr, j)))
		out.append(best)
	return out


func _skinned(sk: Skeleton3D, mi: MeshInstance3D, arr: Array, i: int) -> Vector3:
	var v: Vector3 = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var p := Vector3.ZERO
	for k in per:
		var w := weights[i * per + k]
		if w <= 0.0:
			continue
		var bind := bones[i * per + k]
		var bone := mi.skin.get_bind_bone(bind)
		if bone < 0:
			bone = sk.find_bone(mi.skin.get_bind_name(bind))
		p += (sk.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * v) * w
	return sk.global_transform * p
