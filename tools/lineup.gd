extends SceneTree
## Puts the downloaded models side by side in the game scene and saves a screenshot.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 --script tools/lineup.gd -- out.png

const MODELS := [
	# file, height in metres (a guess for the preview), label
	["res://assets/free_download_-_chobby_bun.glb", 1.6, "Chobby Bun", "rest"],
	["res://assets/tofu_stylized_3d_fox_character.glb", 1.0, "TOFU"],
	["res://assets/border_collie_scientist.glb", 1.7, "Collie"],
	["res://assets/farmer_dog.glb", 1.7, "Farmer Dog"],
	["res://assets/otter-chan.glb", 1.65, "Otter"],
	["res://assets/stylized_bunny_character.glb", 1.8, "Bunny"],
	["res://assets/stylized_deer_character.glb", 1.85, "Deer"],
	["JACOB", 1.8, "Jacob"],
]

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var jacob: String = args[1] if args.size() > 1 else ""
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for n in [main.player, main.kit, main.leash]:
		n.process_mode = Node.PROCESS_MODE_DISABLED
		n.visible = false
	# A flat stage, so the ground does not hide feet.
	var base := -INF
	for gx in range(-6, 7):
		for gz in range(-2, 9):
			base = maxf(base, Terrain.height(gx, gz))
	var stage := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 9.0
	disc.bottom_radius = 9.0
	disc.height = 0.1
	stage.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#f4f6fb")
	stage.material_override = sm
	stage.position = Vector3(0, base - 0.05, 3.0)
	main.add_child(stage)
	var idx := 0
	for m in MODELS:
		var ang := deg_to_rad(-48.0 + idx * (96.0 / (MODELS.size() - 1)))
		var x := sin(ang) * 4.2
		var zz := 1.5 - cos(ang) * 4.2 + 4.2
		idx += 1
		var path: String = jacob if m[0] == "JACOB" else m[0]
		var node := _load(path)
		if node == null:
			print("failed: ", path)
			continue
		if m.size() > 3:
			node.set_meta("rest_pose", true)
		_fit(node, m[1])
		node.position += Vector3(x, base, zz)
		node.rotation.y = -ang * 0.6
		main.add_child(node)
	var cam := Camera3D.new()
	cam.fov = 50
	main.add_child(cam)
	cam.position = Vector3(0, base + 2.2, 8.5)
	cam.look_at(Vector3(0, base + 0.8, 2.5))
	cam.make_current()
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


func _load(path: String) -> Node3D:
	var doc: GLTFDocument = FBXDocument.new() if path.get_extension() == "fbx" else GLTFDocument.new()
	var st: GLTFState = FBXState.new() if doc is FBXDocument else GLTFState.new()
	if path.get_extension() == "fbx":
		st.base_path = path.get_base_dir()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return null
	var scene := doc.generate_scene(st)
	if path.get_extension() == "fbx":
		_fix_jacob(scene, path.get_base_dir())
	var holder := Node3D.new()
	holder.add_child(scene)
	return holder


## Jacob's FBX does not carry its textures: hook them up by material name,
## make the outline an unshaded inverted hull, drop the sword and the display rocks.
func _fix_jacob(scene: Node, dir: String) -> void:
	var tex := {
		"Jacob_Body": ImageTexture.create_from_image(Image.load_from_file(dir + "/textures/T_JacobColor.png")),
		"Jacob_PropsAtlas": ImageTexture.create_from_image(Image.load_from_file(dir + "/textures/T_PropsAtlas.png")),
	}
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.albedo_color = Color("#2a1f1c")
	outline.cull_mode = BaseMaterial3D.CULL_BACK
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.name.contains("Claymore") or mi.name == "Rocks":
			mi.visible = false
			continue
		for s in mi.mesh.get_surface_count():
			var m = mi.get_active_material(s)
			if m == null:
				continue
			if m.resource_name == "Outline":
				mi.set_surface_override_material(s, outline)
			elif tex.has(m.resource_name):
				var nm := StandardMaterial3D.new()
				nm.albedo_texture = tex[m.resource_name]
				nm.roughness = 1.0
				mi.set_surface_override_material(s, nm)


## Scales the model to `height` metres and stands it on y = 0, centred.
## Skinned models are measured by their posed bones (the mesh AABB is the bind pose
## and often ignores the armature scale); static ones by their meshes.
func _fit(holder: Node3D, height: float) -> void:
	var tmp := Node3D.new()
	get_root().add_child(tmp)
	tmp.add_child(holder)
	# Pose first: some files animate the root (scale, offset), so measure the posed model.
	for ap in holder.find_children("*", "AnimationPlayer", true, false):
		var list: PackedStringArray = ap.get_animation_list()
		if list.size() > 0 and not holder.has_meta("rest_pose"):
			ap.play(list[0])
			ap.seek(0.5, true)
			ap.pause()
	# Sketchfab scenes may carry a backdrop sphere and a ground disc: not part of the character.
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("Sphere_Material_006") or mi.name.begins_with("DOWNPLACE"):
			mi.queue_free()
			mi.get_parent().remove_child(mi)
	var pts := _posed_points(holder)
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var h := box.size.y * (1.1 if holder.find_children("*", "Skeleton3D", true, false).size() > 0 else 1.0)
	print(holder.get_child(0).name, " raw size ", box.size, " lights ", holder.find_children("*", "Light3D", true, false).size())
	var s := height / maxf(h, 0.001)
	tmp.remove_child(holder)
	tmp.queue_free()
	holder.scale = Vector3.ONE * s
	holder.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s


## Measuring points: posed deform bones for rigged models (rigify control bones
## skipped), mesh corners for static ones.
func _posed_points(holder: Node3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for sk in holder.find_children("*", "Skeleton3D", true, false):
		var has_def := false
		for i in sk.get_bone_count():
			has_def = has_def or sk.get_bone_name(i).begins_with("DEF-")
		for i in sk.get_bone_count():
			if has_def and not sk.get_bone_name(i).begins_with("DEF-"):
				continue
			pts.append((sk.global_transform * sk.get_bone_global_pose(i)).origin)
	if pts.is_empty():
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			pts.append(b.position)
			pts.append(b.end)
	return pts


func _xf(n: Node3D, top: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != top and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
