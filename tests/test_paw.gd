extends SceneTree
## TOFU's right paw on the second stick (the player asked): the stick points the arm and the paw
## reaches out; let go, it comes back down; it never goes into the ground, an obstacle or the
## bunny's body; on her chest the skin gives (the shader gets the paw) and the chest is pushed
## and swings back after (the player's easter egg); steering the bunny, the paw stick is gone.

var main
var tofu: Actor
var bunny: Actor


func _initialize() -> void:
	_run()


func _bone(a: Actor, n: String) -> Vector3:
	return a.skeleton.global_transform * a.skeleton.get_bone_global_pose(Gait.find_bone(a.skeleton, n)).origin


func _shoulder() -> Vector3:
	return _bone(tofu, "upper_arm.R")


## The stick that points TOFU's arm from the shoulder toward `p`.
func _stick_to(p: Vector3) -> Vector2:
	var d := (p - _shoulder()).normalized()
	var b := tofu.global_basis.orthonormalized()
	var az := atan2(d.dot(-b.x), d.dot(b.z))
	var el := asin(d.y)
	return Vector2(az / (PawReach.AZ_OUT if az > 0.0 else PawReach.AZ_IN), -el / (PawReach.EL_UP if el > 0.0 else PawReach.EL_DOWN))


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	tofu = main.tofu
	bunny = main.bunny
	var paw_r: float = tofu.data.paw.r
	# Out of everyone's way: the bunny far behind.
	bunny.position = tofu.position + Vector3(0, 0, 2.5)
	tofu.rotation.y = PI   # facing -Z, the sea
	await _frames(20)
	var rest := tofu.paw_center() - tofu.position
	Check.ok(main.arm_stick.visible, "steering TOFU, the paw stick is there")

	main.forced_paw = Vector2(0.8, -0.5)   # out to the right and up
	await _frames(60)
	var want := PawReach.direction(tofu, main.forced_paw)
	var got := (tofu.paw_center() - _shoulder()).normalized()
	Check.ok(rad_to_deg(got.angle_to(want)) < 15.0, "the paw goes where the stick points (%.0f degrees off)" % rad_to_deg(got.angle_to(want)))
	Check.ok(tofu.paw_center().distance_to(_shoulder()) > 0.4, "reaching out (%.2f m from the shoulder)" % tofu.paw_center().distance_to(_shoulder()))
	# A long frame (a hitch on a phone) must not throw the arm about (an explicit spring blew up).
	var before := tofu.paw_center()
	for i in 3:
		tofu.animate(0.3, 0.0)
	Check.ok(tofu.paw_center().distance_to(before) < 0.05, "a 0.3 s frame leaves the paw where it was (%.1f cm)" % (tofu.paw_center().distance_to(before) * 100))
	# A wall right at the shoulder: the arm goes lower instead of folding up against it.
	var sh := _shoulder()
	var fwd := tofu.global_basis.z.normalized()
	var wall := [[sh + fwd * 0.2 + Vector3.UP * 0.3, sh + fwd * 0.2 - Vector3.UP * 0.05, 0.05, false]]
	var low_r: Dictionary = PawReach.reach_free(sh, fwd, 0.41, paw_r, 0.1, wall, null)
	Check.ok(not low_r.is_empty() and (low_r.paw as Vector3).distance_to(sh) >= PawReach.MIN_REACH and (low_r.paw as Vector3).y < sh.y - 0.1, "blocked at the shoulder, the paw goes lower (%.2f m out)" % ((low_r.paw as Vector3).distance_to(sh) if not low_r.is_empty() else 0.0))
	main.forced_paw = Vector2.INF
	await _frames(60)
	var back := (tofu.paw_center() - tofu.position).distance_to(rest)
	Check.ok(tofu.gait.paw_out() < 0.01 and back < 0.05, "let go, the arm comes back down (%.1f cm from hanging)" % (back * 100))

	# Across its own chest and down: never into its own body.
	var own := 99.0
	for st in [Vector2(-1, 0), Vector2(-1, 0.7), Vector2(-0.6, 1.0), Vector2(-1, -0.6), Vector2(0, 1)]:
		main.forced_paw = st
		for i in 40:
			await physics_frame
			for c in tofu.capsules():
				own = minf(own, PawReach.seg_distance(tofu.paw_center(), c[0], c[1]) - float(c[2]) - paw_r)
	Check.ok(own > -0.02, "across its chest the paw stays out of its own body (%.1f cm clear at worst)" % (own * 100))
	main.forced_paw = Vector2.INF
	await _frames(40)

	# The ground: stick full down (standing, TOFU's paw reaches about its knee), and a paw swept
	# straight down from low (as on a slope) stops on it.
	main.forced_paw = Vector2(0.0, 1.0)
	var low := 99.0
	for i in 60:
		await physics_frame
		var p := tofu.paw_center()
		low = minf(low, p.y - paw_r - Terrain.height(p.x, p.z))
	await process_frame
	Check.ok(low > -0.01, "stick down: the paw stays above the ground (%.0f cm)" % (low * 100))
	var g := Terrain.height(tofu.position.x, tofu.position.z)
	var down: Dictionary = PawReach.reach(tofu.position + Vector3(0, 0.3, 0), Vector3.DOWN, 0.4, paw_r, 0.1, [], null)
	Check.ok(down.hit and down.paw.y - paw_r > Terrain.height(down.paw.x, down.paw.z) - 0.005 and down.paw.y - paw_r < g + 0.03, "swept down, the paw stops on the ground")

	# An obstacle right in front.
	var ahead := _shoulder() + tofu.global_basis.z.normalized() * 0.52   # right in front of the paw's shoulder
	ahead.y = tofu.position.y
	main.obstacles.add(ahead.x, ahead.z, 0.15)
	main.forced_paw = Vector2(0.0, 0.0)
	var into := 99.0
	for i in 60:
		await physics_frame
		var p := tofu.paw_center()
		into = minf(into, Vector2(p.x - ahead.x, p.z - ahead.z).length() - 0.15 - paw_r)
	Check.ok(into > -0.015, "a rock in front: the paw never goes into it (%.1f cm clear at worst)" % (into * 100))
	var p_end := tofu.paw_center()
	var rock_gap := Vector2(p_end.x - ahead.x, p_end.z - ahead.z).length() - 0.15 - paw_r
	Check.ok(rock_gap < 0.012 and tofu.gait.paw_lying() > 0.9, "and lies on it, palm to the rock (%.1f cm off, lying %.2f)" % [rock_gap * 100, tofu.gait.paw_lying()])
	main.forced_paw = Vector2.INF
	main.obstacles = Obstacles.new()   # gone again
	await _frames(40)

	# The bunny in front, facing TOFU: the paw to her body, then to her chest.
	bunny.position = tofu.position + tofu.global_basis.z.normalized() * 0.62
	bunny.rotation.y = tofu.rotation.y + PI
	await _frames(30)
	main.forced_paw = _stick_to(_bone(bunny, "DEF-spine.002"))
	var worst := 99.0
	for i in 60:
		await physics_frame
		worst = minf(worst, minf(_clear(tofu.paw_center(), paw_r, false), _clear(tofu.paw_center(), paw_r, true) + PawReach.SOFT_GIVE))
	await process_frame
	var tg: Gait = tofu.gait
	var last := minf(_clear(tofu.paw_center(), paw_r, false), _clear(tofu.paw_center(), paw_r, true))
	Check.ok(worst > -0.015, "on her body the paw never goes into her (%.1f cm clear at worst)" % (worst * 100))
	Check.ok(last < 0.012, "it comes right up to her (the palm %.1f cm off her skin; it stopped 4-5 cm short)" % (last * 100))
	var sk := tofu.skeleton
	var h := sk.get_bone_global_pose(sk.find_bone("hand.R"))
	var hy := (sk.global_transform.basis * h.basis.y).normalized()
	var palm := (sk.global_transform.basis * (h.basis * tg._palm_local(sk.find_bone("hand.R"), "r"))).normalized()
	Check.ok(tg.paw_lying() > 0.95 and palm.dot(-tg.paw_normal) > 0.85 and absf(hy.dot(tg.paw_normal)) < 0.4, "the palm lies on her: turned to her, the fingers along her (%.2f, %.2f)" % [palm.dot(-tg.paw_normal), absf(hy.dot(tg.paw_normal))])

	Check.ok(tg._curl > 0.05 and absf(tg._curl - Gait.FINGERS_REST) > 0.05, "the fingers curl round her (%.2f rad)" % tg._curl)
	main.forced_paw = Vector2.INF
	await _frames(60)
	var tip0 := _tips()
	# Her chest: aim at the side nearer TOFU's paw (her chest is turned a little).
	var near := "DEF-breast04.L" if _bone(bunny, "DEF-breast04.L").distance_to(_shoulder()) < _bone(bunny, "DEF-breast04.R").distance_to(_shoulder()) else "DEF-breast04.R"
	main.forced_paw = _stick_to(_bone(bunny, near))
	var touched := 0
	var soft_worst := 99.0
	var moved := 0.0
	var dented := false
	for i in 50:
		await physics_frame
		await process_frame
		soft_worst = minf(soft_worst, _clear(tofu.paw_center(), paw_r, true))
		if PawReach.touches_soft(tofu.paw_center(), paw_r, bunny.touch_shapes()):
			touched += 1
		moved = maxf(moved, _tip_move(tip0))
		for m in bunny._press:
			if (m.get_shader_parameter("paw") as Vector4).w > 0.0:
				dented = true
	Check.ok(soft_worst > -PawReach.SOFT_GIVE - 0.015, "on her chest the paw sinks in only a little (%.1f cm)" % (-soft_worst * 100))
	Check.ok(touched > 10, "the paw is on her chest (%d frames of 50)" % touched)
	Check.ok(moved > 0.005, "the chest is pushed (%.1f cm; 0.7-1.2 depending on frame timing)" % (moved * 100))
	Check.ok(dented, "and the skin gives under the paw (the shader gets it)")
	main.forced_paw = Vector2.INF
	var swing := 0.0
	var prev := moved
	for i in 120:
		await physics_frame
		await process_frame
		var now := _tip_move(tip0)
		swing += absf(now - prev)
		prev = now
	Check.ok(prev < 0.006, "let go, it settles back (%.1f mm off)" % (prev * 1000))
	Check.ok(swing > moved * 1.2, "swinging on a little on the way (%.1f cm travelled)" % (swing * 100))

	# Reaching across to its left onto her, the wrist is not wrung (the player saw it twist round).
	var worst_tw := 0.0
	var worst_sw := 0.0
	for st in [Vector2(-1.0, 0.0), Vector2(-0.6, 0.0), Vector2(-0.6, -0.3), Vector2(-1.0, 0.4)]:
		main.forced_paw = st
		await _frames(40)
		var w := _wrist(sk)
		worst_tw = maxf(worst_tw, w.x)
		worst_sw = maxf(worst_sw, w.y)
	Check.ok(worst_tw <= 45.0 and worst_sw <= 81.0, "to its left, the wrist turns %.0f degrees on the forearm at most (half of it is the forearm's) and bends %.0f (it turned 90-170)" % [worst_tw, worst_sw])
	# Pointed just past her chest (it is about at the end of TOFU's reach: the paw slid along its
	# edge), the paw goes onto it.
	var side_of := bunny.global_basis.x.normalized()
	var near_b := "DEF-breast04.L" if _bone(bunny, "DEF-breast04.L").distance_to(_shoulder()) < _bone(bunny, "DEF-breast04.R").distance_to(_shoulder()) else "DEF-breast04.R"
	var on := 0
	for aside in [-0.08, 0.08]:
		main.forced_paw = _stick_to(_bone(bunny, near_b) + side_of * aside + Vector3.UP * 0.04)
		await _frames(40)
		if PawReach.touches_soft(tofu.paw_center(), paw_r, bunny.touch_shapes()):
			on += 1
	Check.ok(on == 2, "pointed 8 cm beside her chest, the paw goes onto it (%d of 2)" % on)
	main.forced_paw = Vector2.INF
	await _frames(40)

	# Crawling under a trunk, the paw still reaches (the player asked).
	var pass_: Dictionary = main.passages[0]
	var c: Vector2 = pass_.c
	tofu.position = Vector3(c.x, Terrain.height(c.x, c.y), c.y)
	bunny.position = tofu.position + Vector3(2.0, 0, 0)
	main.forced_paw = Vector2.INF
	await _frames(80)
	Check.ok(tofu.gait.crawl > 0.9, "under the trunk TOFU crawls")
	main.forced_paw = Vector2(0.3, -0.4)
	await _frames(60)
	Check.ok(tofu.gait.paw_out() > 0.9 and tofu.paw_center().distance_to(_shoulder()) > 0.3, "crawling, the paw stick still reaches out (%.2f m)" % tofu.paw_center().distance_to(_shoulder()))
	main.forced_paw = Vector2.INF
	await _frames(40)

	# Steering the bunny: no paw stick.
	main.switch_character()
	main.forced_paw = Vector2(0.5, -0.5)
	await _frames(20)
	Check.ok(not main.arm_stick.visible and tofu.gait.paw_target == Vector3.INF, "steering the bunny, the paw stick is gone")
	Check.finish(self)


## The hand's turn on the forearm from rest: (about its own length, the bend), degrees.
func _wrist(sk: Skeleton3D) -> Vector2:
	var fa := sk.find_bone("forearm.R")
	var h := sk.find_bone("hand.R")
	var rel := sk.get_bone_global_pose(fa).basis.orthonormalized().inverse() * sk.get_bone_global_pose(h).basis.orthonormalized()
	var rel0 := sk.get_bone_global_rest(fa).basis.orthonormalized().inverse() * sk.get_bone_global_rest(h).basis.orthonormalized()
	var d := Quaternion(rel0.inverse() * rel)
	var tw := Quaternion(0, d.y, 0, d.w).normalized()
	return Vector2(absf(rad_to_deg(wrapf(2.0 * atan2(d.y, d.w), -PI, PI))), rad_to_deg((d * tw.inverse()).get_angle()))


## Her chest's tips relative to her chest bone.
func _tips() -> Array:
	var c := _bone(bunny, "DEF-spine.003")
	return [_bone(bunny, "DEF-breast04.L") - c, _bone(bunny, "DEF-breast04.R") - c]


## How far the tips moved since `t0` (the more moved one).
func _tip_move(t0: Array) -> float:
	var t := _tips()
	return maxf((t[0] - t0[0]).length(), (t[1] - t0[1]).length())


## How far a paw at `p` is from the nearest of her shapes (negative: inside); `soft`: her chest's.
func _clear(p: Vector3, r: float, soft: bool) -> float:
	var best := 99.0
	for s in bunny.touch_shapes():
		if s[3] != soft:
			continue
		best = minf(best, PawReach.seg_distance(p, s[0], s[1]) - float(s[2]) - r)
	return best
