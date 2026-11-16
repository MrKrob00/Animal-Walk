extends SceneTree
## Prints what each model file contains: bones, animations, triangles, size.
## godot --headless --path . --script tools/inspect_models.gd -- file1.glb file2.fbx ...

func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var doc: GLTFDocument = FBXDocument.new() if path.get_extension().to_lower() == "fbx" else GLTFDocument.new()
		var state: GLTFState = FBXState.new() if doc is FBXDocument else GLTFState.new()
		var err := doc.append_from_file(path, state)
		if err != OK:
			print(path.get_file(), ": load error ", err)
			continue
		var root := doc.generate_scene(state)
		var info := {"bones": 0, "skeletons": 0, "tris": 0, "meshes": 0, "mats": {}, "anims": []}
		var aabb := AABB()
		var first := true
		for n in _all(root):
			if n is Skeleton3D:
				info.skeletons += 1
				info.bones += n.get_bone_count()
			if n is MeshInstance3D and n.mesh != null:
				info.meshes += 1
				for s in n.mesh.get_surface_count():
					var arr: Array = n.mesh.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					info.tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
					var m = n.get_active_material(s)
					if m != null:
						info.mats[m.resource_name] = true
				var b: AABB = n.global_transform * n.mesh.get_aabb() if n.is_inside_tree() else n.transform * n.mesh.get_aabb()
				aabb = b if first else aabb.merge(b)
				first = false
			if n is AnimationPlayer:
				for a in n.get_animation_list():
					info.anims.append("%s(%.1fs)" % [a, n.get_animation(a).length])
		print("%s: skel=%d bones=%d meshes=%d tris=%d mats=%d size=%s anims=%s" % [path.get_file(), info.skeletons, info.bones, info.meshes, info.tris, info.mats.size(), aabb.size, info.anims])
		if info.skeletons > 0:
			for n in _all(root):
				if n is Skeleton3D:
					var names := []
					for i in mini(n.get_bone_count(), 60):
						names.append(n.get_bone_name(i))
					print("   bones: ", ", ".join(names))
		root.free()
	quit()


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
