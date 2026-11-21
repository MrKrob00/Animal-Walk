extends SceneTree
## TOFU's face rides on its head as one piece (the player saw its brows wrongly bound): the eyes,
## brows and nose are rigid on the head, and the face skin was blended neck and head over the
## snout's whole height, so a nod slid them off it. Now everything above the collar is wholly on
## the head (tools/blender/rig_tofu.py, 3c), so nodding moves the brows exactly with the face.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Actor.new()
	a.setup(Actor.TOFU)
	root.add_child(a)
	await process_frame
	var sk := a.skeleton
	var hb := Gait.find_bone(sk, "head")
	var off := 0
	var face := 0
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.skin == null:
			continue
		var hbind := HairRig._bind_of(m.skin, sk, hb)
		var arr := m.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bb.size() / v.size()
		for i in v.size():
			if v[i].y < 3.36:   # model units: the collar is at about 3.28
				continue
			face += 1
			var wh := 0.0
			for k in per:
				if bb[i * per + k] == hbind:
					wh += ww[i * per + k]
			if wh < 0.999:
				off += 1
	Check.ok(face > 1000 and off == 0, "all of TOFU's face above the collar is on its head (%d of %d are not)" % [off, face])
	Check.finish(self)
