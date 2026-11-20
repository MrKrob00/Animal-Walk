extends SceneTree
## TOFU wears a collar on the neck; the leash clips to its ring, which starts at the front and
## slides round toward the leash.

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
	# The leash goes off behind TOFU (the bunny is there): the ring slides round to the back.
	var behind := t.global_position + t.body.global_basis.z * -3.0 + Vector3(0.4, 0.8, 0)
	t.aim_collar(behind, 1.0 / 60.0)
	Check.ok(absf(t.ring_angle()) < 0.5, "the ring slides, it does not jump")
	for i in 120:
		t.aim_collar(behind, 1.0 / 60.0)
	await process_frame
	var back := t.global_transform.affine_inverse() * ring.global_position
	Check.ok(back.z < neck_local.z, "with the leash behind, the ring is at the back of the neck")
	var to_ring := ring.global_position - neck
	var to_leash := behind - neck
	Check.ok(Vector2(to_ring.x, to_ring.z).angle_to(Vector2(to_leash.x, to_leash.z)) < 0.35, "and on the leash's side")
	Check.finish(self)
