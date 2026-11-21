extends SceneTree
## Her clothes (the player asked for outfits; Agnes' blouse and sundress fitted to her by
## tools/fit_outfit.gd): one item per slot, her own top and shorts unless chosen otherwise, the
## choice kept; Agnes' clothes are skinned to her and stay on her body running.

func _initialize() -> void:
	_run()


func _visible(a: Actor, node: String) -> bool:
	var n := a.find_child(node, true, false)
	return n != null and (n as Node3D).visible


## How far the dress's vertices stand off her skin while she runs (the 90th percentile, cm).
func _off_skin(a: Actor, garment: String) -> float:
	var sk := a.skeleton
	var body: MeshInstance3D = a.find_child("Object_11", true, false)
	var g: MeshInstance3D = a.find_child(garment, true, false)
	var pts := []
	for m: MeshInstance3D in [body, g]:
		var arr := m.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := b.size() / v.size()
		var mats := {}
		for k in m.skin.get_bind_count():
			var bone := m.skin.get_bind_bone(k)
			if bone < 0:
				bone = sk.find_bone(m.skin.get_bind_name(k))
			if bone >= 0:
				mats[k] = sk.global_transform * sk.get_bone_global_pose(bone) * m.skin.get_bind_pose(k)
		var out := []
		var step := 1 if m == g else 2
		for j in range(0, v.size(), step):
			var p := Vector3.ZERO
			for k in per:
				var wt := w[j * per + k]
				if wt > 0.0 and mats.has(b[j * per + k]):
					p += (mats[b[j * per + k]] * v[j]) * wt
			out.append(p)
		pts.append(out)
	var grid := {}
	for p in pts[0]:
		var key := Vector3i((p / 0.04).floor())
		if not grid.has(key):
			grid[key] = []
		grid[key].append(p)
	var ds := []
	for i in range(0, pts[1].size(), 7):
		var p: Vector3 = pts[1][i]
		var key := Vector3i((p / 0.04).floor())
		var best := 99.0
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					for q in grid.get(key + Vector3i(x, y, z), []):
						best = minf(best, p.distance_to(q))
		if best < 99.0:
			ds.append(best)
	ds.sort()
	return ds[int(ds.size() * 0.9)] * 100.0


func _run() -> void:
	Wardrobe.save_choice(Wardrobe.DEFAULT)
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	await process_frame
	a.set_process(false)
	Check.ok(_visible(a, "Object_670") and _visible(a, "Object_672") and not _visible(a, "Blouse") and not _visible(a, "Sundress"), "she wears her own top and shorts unless chosen")
	var dress: MeshInstance3D = a.find_child("Sundress", true, false)
	Check.ok(dress.skin != null and dress.get_node_or_null(dress.skeleton) is Skeleton3D, "Agnes' clothes are skinned to her skeleton")
	a.set_outfit(Wardrobe.SETS["Agnes"])
	Check.ok(_visible(a, "Blouse") and _visible(a, "Sundress") and not _visible(a, "Object_670") and not _visible(a, "Object_672"), "the Agnes set: blouse and sundress, her own off")
	a.animate(1.0 / 60.0, 0.0)
	var still := {"Sundress": _off_skin(a, "Sundress"), "Blouse": _off_skin(a, "Blouse")}
	for i in 90:
		a.animate(1.0 / 60.0, 3.0)
	for gname in still:
		var off := _off_skin(a, gname)
		Check.ok(off - still[gname] < 1.5, "running, the %s moves with her (90%% within %.1f cm of her skin, %.1f standing)" % [gname, off, still[gname]])
	Wardrobe.save_choice({"upper": "blouse", "lower": "shorts"})
	var c := Wardrobe.load_choice()
	Check.ok(c.upper == "blouse" and c.lower == "shorts", "the choice is kept")
	Wardrobe.save_choice({"upper": "", "lower": "sundress"})
	Check.ok(Wardrobe.load_choice().upper != "", "top and bottom are never left empty")
	Wardrobe.save_choice(Wardrobe.DEFAULT)
	Check.finish(self)
