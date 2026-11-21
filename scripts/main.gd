extends Node3D
## First scene: a small island with a sand beach. The bunny holds TOFU's leash. Each walks by
## itself (the player plans co-op) and only the leash ties them: pulling apart they pull each
## other, the one standing is led by the other, and their bodies bump instead of passing through.
## The player starts with TOFU; the switch button (Tab) takes the other one, for testing.
## The action button hammers a stake in: the leash is tied to it and the player gets the bunny.
## Next to the stake the button pulls it out again and the player gets TOFU.

const LEASH_GROUND := 3.0   ## how far apart the two ends may be on the ground, metres
const LEASH_ROPE := 3.25   ## rope length in 3D (the ends are at different heights)
const HAMMER_TIME := 0.6   ## the bunny stands still while she hammers, seconds

var obstacles := Obstacles.new()
var passages := []   ## low places to crawl under (LowPassages)
var _passage_caps := []
const CRAWL_SPEED := 0.7   ## m/s, crawling, for a character without crawl clips
var splash: Puffs              ## water drops when a paw lands in the sea
var rules := LeashRules.new()
var bunny: Actor
var tofu: Actor
var stake: Stake
var leash: Leash
var footprints: Footprints
var puffs: Puffs
var joystick: TouchJoystick
var button: ActionButton
var view_button: ViewButton
var switch_button: SwitchButton
var arm_stick: ArmStick
var sit_button: SitButton
var jump_button: JumpButton
var camera_rig: CameraRig
var forced_input := Vector2.ZERO   ## scripted runs (screenshots, tests)
var forced_run := false
var forced_paw := Vector2.INF     ## scripted runs: the paw stick held at this (INF: let go)
var partner_input := Vector3.ZERO  ## co-op later: the other character's wish (ground direction, length 0..1); scripts only for now
var _hand: Node3D
var _collar: Node3D
var _busy := 0.0
var _stake_spot := Vector3.ZERO   ## where she hammers (she faces it)
var _time := 0.0


func _ready() -> void:
	_setup_input()
	_build_light()
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = Terrain.build_mesh()
	ground.material_override = PaperMesh.material()
	add_child(ground)
	passages = LowPassages.place()
	WorldBuilder.populate(self, obstacles, 20261120, LowPassages.reserved(passages))
	LowPassages.build(self, obstacles, passages)
	_passage_caps = LowPassages.capsules(passages)
	var sea := Water.new()
	sea.name = "Sea"
	add_child(sea)

	footprints = Footprints.new()
	add_child(footprints)
	puffs = Puffs.new()
	add_child(puffs)
	splash = Puffs.new()
	splash.tint = Color("#f4fbff")
	add_child(splash)

	tofu = Actor.new()
	tofu.name = "Tofu"
	tofu.setup(Actor.TOFU)
	tofu.world = self
	var start := WorldBuilder.clearing_center()   # on the north beach, facing the sea
	tofu.position = Vector3(start.x, Terrain.height(start.x, start.y), start.y)
	add_child(tofu)

	bunny = Actor.new()
	bunny.name = "Bunny"
	bunny.setup(Actor.BUNNY)
	bunny.world = self
	bunny.position = Vector3(start.x - 0.6, Terrain.height(start.x - 0.6, start.y + 2.2), start.y + 2.2)
	add_child(bunny)

	_collar = tofu.add_collar()   # the brass ring at the front of TOFU's collar
	_hand = bunny.attach_point(Actor.BUNNY.hand)

	stake = Stake.new()
	stake.name = "Stake"
	add_child(stake)
	stake.knocked.connect(func(p): puffs.puff(p, 1.2))

	leash = Leash.new()
	leash.name = "Leash"
	leash.a = _collar
	leash.reattach_b(_hand)
	leash.length = LEASH_ROPE
	add_child(leash)

	tofu.footstep.connect(_on_step.bind(tofu))
	bunny.footstep.connect(_on_step.bind(bunny))

	var ui := CanvasLayer.new()
	add_child(ui)
	joystick = TouchJoystick.new()
	ui.add_child(joystick)
	arm_stick = ArmStick.new()
	ui.add_child(arm_stick)
	button = ActionButton.new()
	ui.add_child(button)
	button.pressed.connect(act)
	sit_button = SitButton.new()
	ui.add_child(sit_button)
	sit_button.pressed.connect(sit_toggle)
	jump_button = JumpButton.new()
	ui.add_child(jump_button)
	jump_button.pressed.connect(jump)
	view_button = ViewButton.new()
	ui.add_child(view_button)
	view_button.pressed.connect(toggle_view)
	switch_button = SwitchButton.new()
	ui.add_child(switch_button)
	switch_button.pressed.connect(switch_character)

	camera_rig = CameraRig.new()
	camera_rig.target = tofu
	camera_rig.second = bunny
	camera_rig.button = button
	camera_rig.buttons = [view_button, switch_button, arm_stick, sit_button, jump_button]
	camera_rig.stick_zone = TouchJoystick.ZONE
	add_child(camera_rig)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("act"):
		act()
	elif event.is_action_pressed("view"):
		toggle_view()
	elif event.is_action_pressed("switch"):
		switch_character()
	elif event.is_action_pressed("sit"):
		sit_toggle()
	elif event.is_action_pressed("jump"):
		jump()


## The jump button: the one you steer jumps (the bunny a hare's hop, TOFU its "surprise!" leap
## with a turn). Sitting, it gets up instead; not while crawling or hammering.
func jump() -> bool:
	var who := steered()
	if who.gait.sitting:
		who.gait.sitting = false
		return false
	if who == bunny and _busy > 0.0:
		return false
	return who.gait.jump()


## The sit button: the one you steer sits down, or gets up (the player asked; the bunny in her
## "frog" W-sit, TOFU like a dog). Not while crawling or hammering. Walking off (the stick) or
## being pulled along by the leash gets it up again.
func sit_toggle() -> void:
	var who := steered()
	if who.gait.crawling or who.gait.crawl > 0.05 or (who == bunny and _busy > 0.0):
		return
	who.gait.sitting = not who.gait.sitting


## The one the player steers now, and the other.
func steered() -> Actor:
	return tofu if rules.steers_tofu() else bunny


func partner() -> Actor:
	return bunny if rules.steers_tofu() else tofu


## The switch button (the player asked for it, to test each character): take the other one.
func switch_character() -> void:
	rules.switch()
	_aim_camera()


## The camera follows whoever the player steers (in first person, from its eyes).
func _aim_camera() -> void:
	camera_rig.target = steered()
	camera_rig.second = partner()
	if camera_rig.first_person:
		camera_rig.set_first_person(true)
	switch_button.set_bunny(not rules.steers_tofu())
	arm_stick.visible = rules.steers_tofu()   # the paw stick is TOFU's
	if not arm_stick.visible:
		arm_stick.release()


## Third person <-> the eyes of the one you steer (the player asked for both).
func toggle_view() -> void:
	camera_rig.toggle_first_person()
	view_button.set_first_person(camera_rig.first_person)


## The action button: hammer the stake in, or pull it out when the bunny is next to it.
func act() -> String:
	if _busy > 0.0:
		return "busy"
	var spot := bunny.position + bunny.global_transform.basis.z * 0.35
	spot.y = Terrain.height(spot.x, spot.z)
	var what := rules.act(spot if rules.held() else bunny.position)
	match what:
		"staked":
			stake.hammer_in(spot)
			leash.reattach_b(stake.top)
			_busy = HAMMER_TIME
			bunny.gait.hammer()
			bunny.velocity = Vector3.ZERO
			_stake_spot = spot
			_aim_camera()
		"picked":
			stake.pull_out()
			leash.reattach_b(_hand)
			_aim_camera()
	return what


func read_input() -> Vector2:
	var v := forced_input
	if v == Vector2.ZERO and joystick != null:
		v = joystick.vector
	if v == Vector2.ZERO:
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	_time += delta
	var v := read_input()
	var running := forced_run or Input.is_action_pressed("run") or v.length() > 0.92
	if camera_rig != null:
		camera_rig.set_body_leads(v.length() > 0.05 or (_busy > 0.0 and steered() == bunny))
	if _busy > 0.0:
		_busy -= delta
	_move(v, running, delta)
	_paw(delta)
	leash.colliders = tofu.capsules() + bunny.capsules() + _passage_caps
	# Under a fallen trunk, whoever is there gets down and crawls.
	for who in [tofu, bunny]:
		who.gait.crawling = LowPassages.under(Vector2(who.position.x, who.position.z), passages)
	# The collar's ring slides round toward the leash, so the rope leaves the neck on its side.
	tofu.aim_collar(leash.pts[6] if leash.pts.size() > 6 else bunny.position, delta)
	sit_button.set_sitting(steered().gait.sitting)
	stake.set_hint(rules.can_pick(bunny.position), _time)
	button.set_active(rules.held() or rules.can_pick(bunny.position))


const SOFT_CORE := 0.045   ## the chest's tip keeps this far out of the paw's ball (its soft core)
var _paw_prev := Vector3.INF


## TOFU's right paw on the second stick: pointed by the stick, out until it meets something
## (PawReach); against the bunny's skin the skin gives and her chest is pushed and wobbles.
func _paw(delta: float) -> void:
	var v := Vector2.ZERO
	var held := false
	if forced_paw != Vector2.INF:
		v = forced_paw
		held = true
	elif arm_stick != null and arm_stick.held:
		v = arm_stick.vector
		held = true
	else:
		var k := Input.get_vector("paw_left", "paw_right", "paw_up", "paw_down")
		if k != Vector2.ZERO:
			v = k
			held = true
	var paw: Dictionary = tofu.data.paw
	if held and rules.steers_tofu():
		var sk := tofu.skeleton
		var ua := Gait.find_bone(sk, tofu.data.bones.upper_arm_r)
		var fa := Gait.find_bone(sk, tofu.data.bones.forearm_r)
		var hd := Gait.find_bone(sk, tofu.data.bones.hand_r)
		var sh: Vector3 = sk.global_transform * sk.get_bone_global_pose(ua).origin
		var el: Vector3 = sk.global_transform * sk.get_bone_global_pose(fa).origin
		var wr: Vector3 = sk.global_transform * sk.get_bone_global_pose(hd).origin
		var arm := (sh.distance_to(el) + el.distance_to(wr)) * 0.95
		var shapes := bunny.touch_shapes()
		for c in _passage_caps:
			shapes.append([c[0], c[1], c[2], false])
		var r := PawReach.reach_free(sh, PawReach.direction(tofu, v), arm, float(paw.r), float(paw.off), shapes, obstacles)
		tofu.gait.paw_off = float(paw.off)
		tofu.gait.paw_target = r.paw if not r.is_empty() else Vector3.INF
	else:
		tofu.gait.paw_target = Vector3.INF
	var pc := tofu.paw_center()
	# Her soft flesh under the paw: each region pressed moves out of the way (Gait.flesh_push).
	var push := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	if tofu.gait.paw_out() > 0.01 and pc != Vector3.INF:
		for s in bunny.touch_shapes():
			if s[4] < 0:
				continue
			var ab: Vector3 = s[1] - s[0]
			var t := clampf((pc - s[0]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			var near: Vector3 = s[0] + ab * t
			var depth := float(s[2]) + float(paw.r) - pc.distance_to(near)
			if depth > 0.0 and pc.distance_to(near) > 1e-5:
				push[s[4]] += (near - pc).normalized() * depth
	bunny.gait.flesh_push = push
	if tofu.gait.paw_out() > 0.01 and pc != Vector3.INF:
		var vel := (pc - _paw_prev) / delta if _paw_prev != Vector3.INF else Vector3.ZERO
		bunny.paw_touch = Vector4(pc.x, pc.y, pc.z, float(paw.r))
		bunny.gait.soft_poke = Vector4(pc.x, pc.y, pc.z, float(paw.r) + SOFT_CORE)
		bunny.gait.soft_poke_vel = vel
		_paw_prev = pc
	else:
		bunny.paw_touch = Vector4.ZERO
		bunny.gait.soft_poke = Vector4.ZERO
		_paw_prev = Vector3.INF


## How fast `who` may crawl: as fast as its crawl clip looks natural.
func _crawl_speed(who: Actor) -> float:
	return who.gait.rt.crawl_speed() if who.gait.rt != null else CRAWL_SPEED


const PULL_LEAN := 0.18   ## the bunny leans this far forward while the leash pulls her (radians)


## Moves both for one frame. Each wants something: the player's one goes where the stick says,
## a partner with a wish (co-op later: `partner_input`) goes its way, a partner without one
## follows on the leash (or stands while the leash is on the stake). Then the leash: the
## overshoot is taken back from the one standing, or half from each when both pull. Then the
## bodies: the one walking into the other is stopped.
func _move(v: Vector2, running: bool, delta: float) -> void:
	var me := steered()
	var free := {}
	var pulls := {}   # who walks by a wish of its own (not following)
	var wishes := {}
	for who: Actor in [tofu, bunny]:
		var want := Vector3.ZERO
		var accel := 12.0
		var wish := Vector3.ZERO
		if who == bunny and _busy > 0.0:
			accel = 30.0   # hammering: stands still
		elif who == me:
			wish = camera_rig.to_ground(v) if camera_rig != null else Vector3(v.x, 0, v.y)
			want = wish * _top_speed(who, running)
			if who.gait.sitting and v.length() > 0.3:
				who.gait.sitting = false   # walking off: it gets up first
			if who.gait.sit > 0.15:
				want = Vector3.ZERO         # still getting up
				wish = wish * 0.0
		elif partner_input.length() > 0.05:
			wish = partner_input.limit_length(1.0)
			want = wish * _top_speed(who, partner_input.length() > 0.92)
		elif rules.held() and not who.gait.sitting:   # sitting, it stays until the leash pulls it up
			want = _follow_velocity(who, (bunny if who == tofu else tofu).position)
			accel = 10.0
		pulls[who] = wish.length() > 0.05
		wishes[who] = wish
		who.velocity = who.velocity.move_toward(want, accel * delta)
		free[who] = who.position + who.velocity * delta
	# The leash.
	var dragged := {tofu: false, bunny: false}
	var taut := false
	if rules.held():
		var wt := 1.0 if pulls[tofu] else 0.0
		var wb := 1.0 if pulls[bunny] else 0.0
		if wt == wb:
			wt = 0.5
			wb = 0.5
		var r := LeashRules.tug(free[tofu], free[bunny], LEASH_GROUND, 1.0 - wt, 1.0 - wb)
		for k in 2:
			var who: Actor = [tofu, bunny][k]
			dragged[who] = (r[k] as Vector3).distance_to(free[who]) > 0.002
			free[who] = r[k]
		taut = dragged[tofu] or dragged[bunny]
	else:
		var held := LeashRules.clamp_to(free[tofu], rules.stake_pos, LEASH_GROUND)
		taut = held.distance_to(free[tofu]) > 0.002
		free[tofu] = held
	# The bodies bump: the one walking into the other is stopped.
	var to_b: Vector3 = free[bunny] - free[tofu]
	to_b.y = 0.0
	var n := to_b.normalized() if to_b.length() > 1e-5 else Vector3.RIGHT
	var ap_t := maxf(tofu.velocity.dot(n), 0.0)
	var ap_b := maxf(-bunny.velocity.dot(n), 0.0)
	var sep := LeashRules.separate(free[tofu], free[bunny], float(tofu.data.radius) + float(bunny.data.radius), ap_t, ap_b)
	free[tofu] = sep[0]
	free[bunny] = sep[1]
	# Led (not pulling itself): faces the one leading; the bunny leans after the leash (her
	# "can't keep up" look); pulling against the leash she leans into it.
	var eyes := Vector3(0, 1.0, 0)
	for who: Actor in [tofu, bunny]:
		var other: Actor = bunny if who == tofu else tofu
		var led: bool = dragged[who] and not pulls[who]
		if led and who.gait.sitting:
			who.gait.sitting = false   # pulled along by the leash: it gets up
		who.face_target = _facing(who, other, led, pulls[who], wishes[who])
		who.gait.dragged = led
		who.extra_lean = PULL_LEAN if who == bunny and dragged[who] else 0.0
		who.gait.look_target = Vector3.INF if pulls[who] else other.position + eyes
		who.place(free[who], delta)
	if rules.held():
		bunny.gait.hold_target = _collar.global_position
		bunny.gait.hold_pull = lerpf(bunny.gait.hold_pull, 1.0 if taut else 0.15, 1.0 - exp(-3.0 * delta))
	else:
		bunny.gait.hold_target = Vector3.INF


## Where `who` turns to this frame (Vector3.INF: where it moves).
func _facing(who: Actor, other: Actor, led: bool, pulls: bool, wish: Vector3) -> Vector3:
	if led:
		return other.position                 # led on the leash: after the one leading
	if pulls:
		return who.position + wish * 3.0      # its own way (pulled back, it still faces there)
	if who == bunny and _busy > 0.0:
		return _stake_spot                    # hammering
	# First person, standing: the body turns to where you look, so the view never looks out
	# through the back of its head (walking, the body leads and the view goes with it).
	if camera_rig != null and camera_rig.first_person and who == steered() and who.speed < 0.3 and not camera_rig.body_leads:
		return who.position + (camera_rig.ground_axes()[1] as Vector3) * 3.0
	if who == tofu and not rules.held():
		return other.position                 # tied to the stake, it stands and watches her
	return Vector3.INF


## How fast `who` may go: walking or running, never quicker than its crawl looks natural.
func _top_speed(who: Actor, running: bool) -> float:
	var top: float = who.data.run if running else who.data.walk
	if who.gait.crawling or who.gait.crawl > 0.2:
		top = minf(top, _crawl_speed(who))
	return top


## The one following on the leash: walks after the leader once the leash grows long.
func _follow_velocity(who: Actor, leader: Vector3) -> Vector3:
	var to := leader - who.position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.001:
		return Vector3.ZERO
	var want := to / dist * LeashRules.follow_speed(dist, LEASH_GROUND, float(who.data.run))
	if who.gait.crawling or who.gait.crawl > 0.2:
		want = want.limit_length(_crawl_speed(who))
	return want


func _on_step(pos: Vector3, size: float, who: Node3D) -> void:
	if Terrain.height(pos.x, pos.z) < -0.01:
		splash.puff(pos, size * 1.2)   # wading: a splash, and the sea keeps no prints
		return
	footprints.add(pos, who.rotation.y, size * 0.8)
	puffs.puff(pos, size)


## Pushes a walker of `radius` out of trees and rocks and keeps it in the play area.
func resolve(pos: Vector3, radius: float) -> Vector3:
	var p := Terrain.keep_on_island(obstacles.push_out(Vector2(pos.x, pos.z), radius))
	return Vector3(p.x, pos.y, p.y)


static func resolve_against(pos: Vector3, radius: float, obs: Array[Vector3]) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	for o in obs:
		var d := p - Vector2(o.x, o.y)
		var min_d := o.z + radius
		var l := d.length()
		if l < min_d:
			p = Vector2(o.x, o.y) + (d / l if l > 0.0001 else Vector2.RIGHT) * min_d
	p = Terrain.keep_on_island(p)
	return Vector3(p.x, pos.y, p.y)


func _build_light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#5aa7e6")
	sky_mat.sky_horizon_color = Color("#cfe9f7")
	sky_mat.ground_horizon_color = Color("#cfe9f7")
	sky_mat.ground_bottom_color = Color("#7fc3d9")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	# Shade is lit by a soft sky-blue ambient: cool shadows on warm sand.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a9c4e4")
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color("#d4ecf6")
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# A warm afternoon sun, high enough for short crisp shadows under the palms.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color("#fff3df")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)


func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"run": [KEY_SHIFT],
		"act": [KEY_E],
		"jump": [KEY_SPACE],
		"view": [KEY_V],
		"switch": [KEY_TAB],
		"sit": [KEY_C],
		"paw_left": [KEY_J],
		"paw_right": [KEY_L],
		"paw_up": [KEY_I],
		"paw_down": [KEY_K],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
