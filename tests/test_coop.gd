extends SceneTree
## Two walkers tied by the leash (the player plans co-op): the switch button gives the player the
## other one; the bunny leads and TOFU follows; pulling apart they pull each other (neither runs
## off, the leash holds); the bodies bump instead of passing through; with the stake in, TOFU
## steered by the player stays within the leash of it.

var main


func _initialize() -> void:
	_run()


## The stick that walks along `dir` on the ground (the stick is read relative to the camera).
func _stick(dir: Vector3) -> Vector2:
	var ax: Array = main.camera_rig.ground_axes()
	return Vector2(dir.dot(ax[0]), -dir.dot(ax[1]))


func _place(tofu_at: Vector3, bunny_at: Vector3) -> void:
	for p in [[main.tofu, tofu_at], [main.bunny, bunny_at]]:
		var a: Actor = p[0]
		var at: Vector3 = p[1]
		a.position = Vector3(at.x, Terrain.height(at.x, at.z), at.z)
		a.velocity = Vector3.ZERO


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var tofu: Actor = main.tofu
	var bunny: Actor = main.bunny
	var o: Vector3 = tofu.position
	Check.ok(main.steered() == tofu, "the player starts with TOFU")
	main.switch_character()
	Check.ok(main.steered() == bunny and main.camera_rig.target == bunny and main.switch_button.bunny_steered, "the switch button gives the player the bunny (and the camera)")

	# The bunny leads: TOFU follows on the leash.
	_place(o, o + Vector3(1.0, 0, 0))
	var t0 := tofu.position
	var worst := 0.0
	for i in 300:
		main.forced_input = _stick(Vector3(1, 0, 0.15).normalized())
		await physics_frame
		worst = maxf(worst, _flat(tofu.position, bunny.position))
	Check.ok(_flat(tofu.position, t0) > 4.0, "the bunny leads, TOFU comes after her (%.1f m)" % _flat(tofu.position, t0))
	Check.ok(worst < main.LEASH_GROUND + 0.05, "never further apart than the leash (%.2f m)" % worst)

	# Pulling apart at the same walk: both are held back, neither runs off (a quicker one would
	# win and drag the other).
	_place(o, o + Vector3(2.5, 0, 0))
	var b0 := bunny.position
	t0 = tofu.position
	worst = 0.0
	for i in 180:
		main.forced_input = _stick(Vector3(1, 0, 0)) * 0.8
		main.partner_input = Vector3(-1, 0, 0) * 0.75
		await physics_frame
		worst = maxf(worst, _flat(tofu.position, bunny.position))
	var mb := _flat(bunny.position, b0)
	var mt := _flat(tofu.position, t0)
	Check.ok(worst < main.LEASH_GROUND + 0.05, "pulling apart, the leash holds (%.2f m)" % worst)
	Check.ok(mb < 1.0 and mt < 1.0, "and each holds the other back (bunny moved %.2f m, TOFU %.2f m)" % [mb, mt])
	main.partner_input = Vector3.ZERO

	# The bodies bump: the bunny walks straight at TOFU standing.
	_place(o, o + Vector3(2.0, 0, 0))
	var closest := 99.0
	for i in 150:
		main.forced_input = _stick(Vector3(-1, 0, 0))
		await physics_frame
		closest = minf(closest, _flat(tofu.position, bunny.position))
	var gap := float(tofu.data.radius) + float(bunny.data.radius)
	Check.ok(closest > gap - 0.03, "walking into TOFU, the bunny stops against it (%.2f m apart, bodies %.2f)" % [closest, gap])
	# ... and TOFU walking into the bunny.
	main.switch_character()
	_place(o, o + Vector3(2.0, 0, 0))
	closest = 99.0
	for i in 150:
		main.forced_input = _stick(Vector3(1, 0, 0))
		await physics_frame
		closest = minf(closest, _flat(tofu.position, bunny.position))
	Check.ok(closest > gap - 0.03, "and TOFU walking into her stops too (%.2f m apart)" % closest)

	# The stake in: the player gets the bunny; switched to TOFU, it stays within the leash of it.
	main.forced_input = Vector2.ZERO
	for i in 10:
		await physics_frame
	Check.ok(main.act() == "staked" and main.steered() == bunny, "the stake goes in, the player gets the bunny")
	for i in 60:
		await physics_frame
	main.switch_character()
	Check.ok(main.steered() == tofu, "switched to TOFU with the stake in")
	worst = 0.0
	for i in 240:
		main.forced_input = _stick(Vector3(0, 0, -1))
		await physics_frame
		worst = maxf(worst, _flat(tofu.position, main.rules.stake_pos))
	Check.ok(worst < main.LEASH_GROUND + 0.01, "TOFU stays within the leash of the stake (%.2f m)" % worst)
	Check.finish(self)
