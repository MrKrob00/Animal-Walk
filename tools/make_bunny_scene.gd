extends SceneTree
## Writes scenes/bunny.tscn: the bunny's model (its own nodes editable in the editor) with Agnes'
## fitted clothes as separate nodes under her skeleton (the player asked for a bunny scene to
## adjust, the clothes apart). The game loads this scene (Actor.BUNNY.path); Wardrobe shows one
## item per slot. The clothes carry no skin here (the editor shows them on her T-pose); the
## game skins them to her skeleton. Written as text: packed with the model editable, its meshes
## and skin were copied in (1.25 MB); not editable, the clothes under its skeleton were dropped.
##   godot --headless --path . --script tools/make_bunny_scene.gd

const OUT := "res://scenes/bunny.tscn"
const MODEL := "res://assets/chobby_tpose.glb"
const CLOTHES := {"Blouse": "res://assets/outfits/agnes/blouse.res", "Sundress": "res://assets/outfits/agnes/sundress.res"}   # no shoes (the player)


func _initialize() -> void:
	var t := "[gd_scene load_steps=%d format=3]\n\n" % (CLOTHES.size() + 2)
	t += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"model\"]\n" % MODEL
	for n in CLOTHES:
		t += "[ext_resource type=\"ArrayMesh\" path=\"%s\" id=\"%s\"]\n" % [CLOTHES[n], n.to_lower()]
	t += "\n[node name=\"Bunny\" type=\"Node3D\"]\n\n"
	t += "[node name=\"ChobbyBun\" parent=\".\" instance=ExtResource(\"model\")]\n\n"
	for n in CLOTHES:
		t += "[node name=\"%s\" type=\"MeshInstance3D\" parent=\"ChobbyBun/Skeleton3D\"]\nvisible = false\nmesh = ExtResource(\"%s\")\n\n" % [n, n.to_lower()]
	t += "[editable path=\"ChobbyBun\"]\n"
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(t)
	f.close()
	var ps: PackedScene = ResourceLoader.load(OUT, "", ResourceLoader.CACHE_MODE_IGNORE)
	var inst := ps.instantiate()
	print("wrote ", OUT, ": ", inst.find_child("Blouse", true, false) != null, " ", inst.find_child("Object_11", true, false) != null)
	inst.free()
	quit()
