extends SceneTree
## Army crawl (the player chose it): both characters get down on their bellies and crawl on,
## nothing of them sinks into the ground (skin skinned on the CPU: at most 2.5 cm, a paw tip),
## no footprints while crawling, and they stand up again after.

func _initialize() -> void:
	_run()


func _run() -> void:
	for who in [Actor.BUNNY, Actor.TOFU]:
		var a := Actor.new()
		a.setup(who)
		root.add_child(a)
		await process_frame
		a.set_process(false)
		var sk := a.skeleton
		var head := func() -> float: return (sk.global_transform * sk.get_bone_global_pose(Gait.find_bone(sk, who.bones.head)).origin).y
		var name: String = "bunny" if who == Actor.BUNNY else "TOFU"
		var h: float = who.height
		a.animate(1.0 / 60.0, 0.0)
		var standing: float = head.call()
		var deepest := 0.0
		var steps := 0
		a.footstep.connect(func(_p, _s): steps += 1)
		for i in 240:
			a.gait.crawling = true
			var go := 0.6 if i > 40 else 0.0
			a.position += Vector3(0, 0, go / 60.0)
			a.animate(1.0 / 60.0, go)
			if i >= 120 and i % 12 == 0:
				deepest = maxf(deepest, _deepest(a))
		Check.ok(head.call() < h * 0.45, "%s gets down on its belly (head %.2f m up)" % [name, head.call()])
		Check.ok(deepest < 0.025, "%s: nothing sinks into the ground (%.1f cm at most)" % [name, deepest * 100])
		Check.ok(steps == 0, "%s leaves no footprints crawling" % name)
		for i in 90:
			a.gait.crawling = false
			a.animate(1.0 / 60.0, 0.0)
		Check.ok(head.call() > standing * 0.95, "%s stands up again after (head %.2f m up, %.2f before)" % [name, head.call(), standing])
		a.queue_free()
	Check.finish(self)


## How far the deepest skin point is under the ground (metres; 0 when none is).
func _deepest(a: Actor) -> float:
	var sk := a.skeleton
	var worst := 0.0
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.skin == null or not m.visible:
			continue
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
			mats[k] = sk.global_transform * sk.get_bone_global_pose(bone) * m.skin.get_bind_pose(k)
		for j in range(0, v.size(), 3):
			var p := Vector3.ZERO
			for k in per:
				var wt := w[j * per + k]
				if wt > 0.0:
					p += (mats[b[j * per + k]] * v[j]) * wt
			worst = maxf(worst, a.global_position.y - p.y)
	return worst
