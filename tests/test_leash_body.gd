extends SceneTree
## The leash lies over both walkers, not through them: the bunny has capsules round her torso
## and hips like TOFU's, and her leash hand stays outside them (or the rope would be pushed off
## her hand). A rope drawn straight through her ends up outside.

func _initialize() -> void:
	_run()


func _run() -> void:
	var b := Actor.new()
	b.setup(Actor.BUNNY)
	root.add_child(b)
	await process_frame
	b.set_process(false)
	var caps := b.capsules()
	Check.ok(caps.size() == 2, "the bunny has two capsules for the leash")
	var hand := Gait.find_bone(b.skeleton, Actor.BUNNY.hand)
	var hand_in := false
	for i in 120:
		b.position += b.global_basis.z * 1.3 / 60.0
		b.animate(1.0 / 60.0, 1.3)
		var h: Vector3 = b.skeleton.global_transform * b.skeleton.get_bone_global_pose(hand).origin
		for c in b.capsules():
			hand_in = hand_in or Leash.push_out(h, c[0], c[1], c[2]) != h
	Check.ok(not hand_in, "walking, her leash hand stays outside them")
	# A rope from one side of her to the other, through her waist.
	var mid: Vector3 = b.skeleton.global_transform * b.skeleton.get_bone_global_pose(Gait.find_bone(b.skeleton, "DEF-spine.001")).origin
	var side := b.body.global_basis.x
	var ma := Marker3D.new()
	var mb := Marker3D.new()
	root.add_child(ma)
	root.add_child(mb)
	ma.global_position = mid - side * 0.8 + b.body.global_basis.z * 0.05
	mb.global_position = mid + side * 0.8 + b.body.global_basis.z * 0.05
	var rope := Leash.new()
	rope.a = ma
	rope.b = mb
	rope.length = 1.7
	rope.use_ground = false
	root.add_child(rope)
	await process_frame
	rope.colliders = b.capsules()
	for i in 120:
		rope.simulate(1.0 / 60.0, ma.global_position, mb.global_position)
	var inside := 0
	for p in rope.pts:
		for c in rope.colliders:
			if Leash.push_out(p, c[0], c[1], c[2] - 0.005) != p:
				inside += 1
	Check.ok(inside == 0, "a leash drawn through her waist goes round her (%d points inside)" % inside)
	Check.finish(self)
