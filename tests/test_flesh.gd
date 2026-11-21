extends SceneTree
## Her soft butt, thighs and belly (the player asked; SoftFlesh, no bones of their own): the skin
## and shorts carry the three regions' shares, her top none; running and stopping, the flesh
## lags and swings, within its limit, then settles; TOFU's paw on her thigh pushes that side
## away from the paw, never into her, and let go it comes back (with the paw easing off, as
## flesh follows a lifting hand, without swinging past).

var main
var tofu: Actor
var bunny: Actor


func _initialize() -> void:
	_run()


func _bone(a: Actor, n: String) -> Vector3:
	return a.skeleton.global_transform * a.skeleton.get_bone_global_pose(Gait.find_bone(a.skeleton, n)).origin


func _stick_to(p: Vector3) -> Vector2:
	var d := (p - _bone(tofu, "upper_arm.R")).normalized()
	var b := tofu.global_basis.orthonormalized()
	var az := atan2(d.dot(-b.x), d.dot(b.z))
	var el := asin(d.y)
	return Vector2(az / (PawReach.AZ_OUT if az > 0.0 else PawReach.AZ_IN), -el / (PawReach.EL_UP if el > 0.0 else PawReach.EL_DOWN)).limit_length(1.0)


## Largest share of each region in a mesh.
func _shares(name: String) -> Vector3:
	var m: MeshInstance3D = bunny.find_child(name, true, false)
	var c = m.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	var best := Vector3.ZERO
	if c == null:
		return best
	var f: PackedFloat32Array = c
	for i in f.size() / 4:
		best = Vector3(maxf(best.x, f[i * 4]), maxf(best.y, f[i * 4 + 1]), maxf(best.z, f[i * 4 + 2]))
	return best


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	tofu = main.tofu
	bunny = main.bunny
	Check.ok(bunny._flesh_regions.size() == 3, "three soft regions: left and right butt-and-thigh, belly")
	var skin := _shares("Object_11")
	var shorts := _shares("Object_672")
	var top := _shares("Object_670")
	Check.ok(skin.x > 0.9 and skin.y > 0.9 and skin.z > 0.5, "her skin carries all three (%.2f %.2f %.2f)" % [skin.x, skin.y, skin.z])
	Check.ok(shorts.x > 0.9 and shorts.y > 0.9, "her shorts move with the butt and thighs under them")
	Check.ok(top == Vector3.ZERO, "her top carries none (its hem turned inside out)")

	# Steering her: run, stop.
	main.switch_character()
	tofu.position = bunny.position + Vector3(-1.5, 0, 0)
	var limit := Gait.FLESH_MAX * 1.6 + 0.001
	var peak := 0.0
	for i in 150:
		main.forced_input = Vector2(0, -1)
		await physics_frame
		for o in bunny.gait.flesh_offset:
			peak = maxf(peak, (o as Vector3).length())
	main.forced_input = Vector2.ZERO
	var after := 0.0
	for i in 40:
		await physics_frame
		for o in bunny.gait.flesh_offset:
			after = maxf(after, (o as Vector3).length())
	Check.ok(maxf(peak, after) > 0.004, "running and stopping, the flesh swings (%.1f cm at most)" % (maxf(peak, after) * 100))
	Check.ok(maxf(peak, after) <= limit, "never further than its limit (%.1f cm)" % (limit * 100))
	for i in 150:
		await physics_frame
	var rest := 0.0
	for o in bunny.gait.flesh_offset:
		rest = maxf(rest, (o as Vector3).length())
	Check.ok(rest < 0.002, "standing, it settles (%.1f mm)" % (rest * 1000))

	# TOFU's paw on her left thigh.
	main.switch_character()
	tofu.rotation.y = 0.0
	bunny.position = tofu.position + tofu.global_basis.z.normalized() * 0.62
	bunny.rotation.y = PI
	for i in 40:
		await physics_frame
	var thigh := _bone(bunny, "DEF-thigh.L").lerp(_bone(bunny, "DEF-shin.L"), 0.35)
	var region := 0
	if _bone(bunny, "DEF-thigh.R").distance_to(_bone(tofu, "upper_arm.R")) < _bone(bunny, "DEF-thigh.L").distance_to(_bone(tofu, "upper_arm.R")):
		thigh = _bone(bunny, "DEF-thigh.R").lerp(_bone(bunny, "DEF-shin.R"), 0.35)
		region = 1
	var away := 0.0
	var hard := 99.0
	for i in 60:
		main.forced_paw = _stick_to(thigh)
		await physics_frame
		await process_frame
		var pc := tofu.paw_center()
		var o: Vector3 = bunny.gait.flesh_offset[region]
		away = maxf(away, o.dot((thigh - pc).normalized()))
		for s in bunny.touch_shapes():
			if not s[3]:
				hard = minf(hard, PawReach.seg_distance(pc, s[0], s[1]) - float(s[2]) - float(tofu.data.paw.r))
	Check.ok(away > 0.005, "the paw pushes her thigh away from it (%.1f cm)" % (away * 100))
	Check.ok(hard > -0.015, "and never into the rest of her (%.1f cm clear)" % (hard * 100))
	main.forced_paw = Vector2.INF
	var swing := 0.0
	for i in 90:
		await physics_frame
		swing = maxf(swing, -(bunny.gait.flesh_offset[region] as Vector3).dot((thigh - tofu.paw_center()).normalized()))
	var back: float = (bunny.gait.flesh_offset[region] as Vector3).length()
	Check.ok(back < 0.003, "let go, it comes back (%.1f mm)" % (back * 1000))
	Check.finish(self)
