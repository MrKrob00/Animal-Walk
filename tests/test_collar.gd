extends SceneTree
## TOFU wears a collar on the neck; the leash clips to its ring at the front.

func _initialize() -> void:
	_run()


func _run() -> void:
	var t := Actor.new()
	t.setup(Actor.TOFU)
	root.add_child(t)
	await process_frame
	var ring := t.add_collar()
	await process_frame
	var sk := t.skeleton
	var neck: Vector3 = sk.global_transform * sk.get_bone_global_pose(Gait.find_bone(sk, "neck")).origin
	var local := t.global_transform.affine_inverse() * ring.global_position
	var neck_local := t.global_transform.affine_inverse() * neck
	Check.ok(t.find_children("Collar", "MeshInstance3D", true, false).size() == 1, "TOFU has a collar")
	Check.ok(absf(local.y - neck_local.y) < 0.12, "the ring is at neck height")
	Check.ok(local.z > neck_local.z, "the ring is at the front of the neck")
	Check.finish(self)
