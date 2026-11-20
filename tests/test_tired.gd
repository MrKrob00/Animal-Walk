extends SceneTree
## Dragged at a run the bunny tires, stumbles now and then, bends over to catch her breath
## after the stop, and recovers. TOFU never tires.

func _initialize() -> void:
	_run()


func _run() -> void:
	var a := Actor.new()
	a.setup(Actor.BUNNY)
	root.add_child(a)
	var t := Actor.new()
	t.setup(Actor.TOFU)
	root.add_child(t)
	await process_frame
	a.set_process(false)
	t.set_process(false)
	var dt := 1.0 / 60.0
	var stumbles := 0
	var was := false
	a.gait.dragged = true
	a.gait.hold_pull = 1.0
	for i in 420:   # 7 s at a run
		a.position.z += a.data.run * dt
		a.animate(dt, a.data.run)
		t.gait.dragged = true
		t.animate(dt, t.data.run)
		if a.gait.stumbling() and not was:
			stumbles += 1
		was = a.gait.stumbling()
	Check.ok(a.gait.fatigue > 0.9, "after a long drag at a run she is worn out (%.2f)" % a.gait.fatigue)
	Check.ok(stumbles >= 1, "worn out, she stumbles now and then (%d)" % stumbles)
	Check.ok(t.gait.fatigue == 0.0, "TOFU does not tire")
	a.gait.dragged = false
	a.gait.hold_pull = 0.15
	for i in 120:   # 2 s standing
		a.animate(dt, 0.0)
	Check.ok(a.gait.winded() > 0.6, "after the stop she bends over to catch her breath")
	for i in 420:   # 7 s more
		a.animate(dt, 0.0)
	Check.ok(a.gait.fatigue < 0.05 and a.gait.winded() < 0.1, "and recovers")
	var b := Actor.new()
	b.setup(Actor.BUNNY)
	root.add_child(b)
	await process_frame
	b.set_process(false)
	for i in 420:
		b.position.z += b.data.walk * dt
		b.animate(dt, b.data.walk)
	Check.ok(b.gait.fatigue == 0.0, "walking on her own does not tire her")
	Check.finish(self)
