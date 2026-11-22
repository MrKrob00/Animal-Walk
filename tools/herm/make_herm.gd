extends SceneTree
## Packs tools/herm/build_herm.py's output (herm.json and its grids) into assets/herm/herm.res.
## godot --headless --path . --script tools/herm/make_herm.gd -- <dir with herm.json>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "res://assets/herm"
	var d := HermData.new()
	d.meta = JSON.parse_string(FileAccess.get_file_as_string(dir + "/herm.json"))
	d.height = FileAccess.get_file_as_bytes(dir + "/herm_height.bin").to_float32_array()
	d.shore = FileAccess.get_file_as_bytes(dir + "/herm_shore.bin").to_float32_array()
	d.kind = FileAccess.get_file_as_bytes(dir + "/herm_kind.bin")
	var n := int(d.meta.nx) * int(d.meta.nz)
	if d.height.size() != n or d.shore.size() != n or d.kind.size() != n:
		push_error("grid sizes do not match %d" % n)
		quit(1)
		return
	var err := ResourceSaver.save(d, "res://assets/herm/herm.res", ResourceSaver.FLAG_COMPRESS)
	print("saved assets/herm/herm.res: ", err, " cells ", n, " paths ", d.meta.paths.size(), " places ", d.meta.places.size())
	quit()
