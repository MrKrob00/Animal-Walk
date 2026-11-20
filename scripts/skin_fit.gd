class_name SkinFit
extends RefCounted
## Tight clothes follow the skin under them: each cloth vertex takes the bone weights of the
## nearest body vertices (inverse-distance blend of the closest three). The model's own cloth
## weights differ from the skin's (Chobby's top hangs mostly on the spine while her chest skin
## follows the chest bones), so when the chest moves a gap opens between the top and the skin.
## Both meshes must share one skin and one transform (they do in a single-rig model).

const CELL := 0.04   ## hash cell, in the mesh's units (raw Chobby is about 4 tall)
const NEAREST := 3
const INFLATE := 0.012   ## the cloth stands this far off the skin (mesh units: Chobby is ~4 tall, so ~5 mm), so skin never shows through


## `skip`: bone name prefixes whose skin the cloth must not copy (an arm hanging against the
## top would otherwise drag the armhole along with it).
static func follow_body(body: MeshInstance3D, cloth: MeshInstance3D, skip: Array = []) -> void:
	if body.skin != cloth.skin or not body.transform.is_equal_approx(cloth.transform):
		push_warning("SkinFit: %s and %s do not share a skin" % [body.name, cloth.name])
		return
	var src: Array = body.mesh.surface_get_arrays(0)
	var b_verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var b_bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var b_weights: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var per := b_bones.size() / b_verts.size()
	var skipped := {}
	for bind in body.skin.get_bind_count():
		var n := String(body.skin.get_bind_name(bind))
		for pre in skip:
			if n.begins_with(pre):
				skipped[bind] = true
	var grid := {}
	for i in b_verts.size():
		var off := 0.0
		for k in per:
			if skipped.has(b_bones[i * per + k]):
				off += b_weights[i * per + k]
		if off > 0.3:
			continue
		var key := Vector3i((b_verts[i] / CELL).floor())
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(i)
	var old: Mesh = cloth.mesh
	var mesh := ArrayMesh.new()
	for sf in old.get_surface_count():
		var arr: Array = old.surface_get_arrays(sf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var c_per: int = (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() / verts.size()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(verts.size() * c_per)
		weights.resize(verts.size() * c_per)
		for v in verts.size():
			var near := _nearest(verts[v], b_verts, grid)
			var mix := {}
			var wsum := 0.0
			for n in near:
				var w := 1.0 / maxf(verts[v].distance_to(b_verts[n]), 0.002)
				wsum += w
				for k in per:
					var bw := b_weights[n * per + k]
					if bw > 0.0:
						var bone := b_bones[n * per + k]
						mix[bone] = mix.get(bone, 0.0) + bw * w
			var order := mix.keys()
			order.sort_custom(func(x, y): return mix[x] > mix[y])
			var kept := 0.0
			for k in mini(c_per, order.size()):
				kept += mix[order[k]]
			for k in c_per:
				var at := v * c_per + k
				if k < order.size() and kept > 0.0:
					bones[at] = order[k]
					weights[at] = mix[order[k]] / kept
				else:
					bones[at] = 0
					weights[at] = 0.0
		var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		if normals.size() == verts.size():
			for v in verts.size():
				verts[v] += normals[v] * INFLATE
			arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(old.surface_get_primitive_type(sf), arr)
		mesh.surface_set_material(sf, old.surface_get_material(sf))
	cloth.mesh = mesh


static func _nearest(p: Vector3, verts: PackedVector3Array, grid: Dictionary) -> Array:
	var c := Vector3i((p / CELL).floor())
	var best := []   # [distance, index], sorted, at most NEAREST
	for reach in [1, 2, 3]:
		for x in range(-reach, reach + 1):
			for y in range(-reach, reach + 1):
				for z in range(-reach, reach + 1):
					if maxi(absi(x), maxi(absi(y), absi(z))) != reach and reach > 1:
						continue   # only the new shell when searching wider
					var cell: PackedInt32Array = grid.get(c + Vector3i(x, y, z), PackedInt32Array())
					for i in cell:
						var d := p.distance_squared_to(verts[i])
						if best.size() < NEAREST or d < best[-1][0]:
							var at := best.size()
							while at > 0 and best[at - 1][0] > d:
								at -= 1
							best.insert(at, [d, i])
							if best.size() > NEAREST:
								best.pop_back()
		if best.size() >= NEAREST:
			break
	var out := []
	for b in best:
		out.append(b[1])
	return out
