extends Node3D
## First scene: a snowy mountain clearing. The bunny holds TOFU's leash and TOFU drags her
## around (the player steers TOFU). The action button hammers a stake in: the leash is tied
## to it and the player steers the bunny. Next to the stake the button pulls it out again.

const LEASH_GROUND := 3.0   ## how far apart the two ends may be on the ground, metres
const LEASH_ROPE := 3.25   ## rope length in 3D (the ends are at different heights)
const HAMMER_TIME := 0.6   ## the bunny stands still while she hammers, seconds

var obstacles: Array[Vector3] = []   ## x, z, radius
var rules := LeashRules.new()
var bunny: Actor
var tofu: Actor
var stake: Stake
var leash: Leash
var footprints: Footprints
var puffs: SnowPuffs
var joystick: TouchJoystick
var button: ActionButton
var camera_rig: CameraRig
var forced_input := Vector2.ZERO   ## scripted runs (screenshots, tests)
var forced_run := false
var _hand: Node3D
var _collar: Node3D
var _busy := 0.0
var _time := 0.0


func _ready() -> void:
	_setup_input()
	_build_light()
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = Terrain.build_mesh()
	ground.material_override = PaperMesh.material()
	add_child(ground)
	obstacles = WorldBuilder.populate(self)

	footprints = Footprints.new()
	add_child(footprints)
	puffs = SnowPuffs.new()
	add_child(puffs)

	tofu = Actor.new()
	tofu.name = "Tofu"
	tofu.setup(Actor.TOFU)
	tofu.world = self
	tofu.position = Vector3(0, Terrain.height(0, 1.0), 1.0)
	add_child(tofu)

	bunny = Actor.new()
	bunny.name = "Bunny"
	bunny.setup(Actor.BUNNY)
	bunny.world = self
	bunny.position = Vector3(-0.6, Terrain.height(-0.6, 3.2), 3.2)
	add_child(bunny)

	_collar = tofu.attach_point(Actor.TOFU.collar, Vector3(0, -0.01, 0.06))   # front of the neck
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
	button = ActionButton.new()
	ui.add_child(button)
	button.pressed.connect(act)

	camera_rig = CameraRig.new()
	camera_rig.target = tofu
	camera_rig.second = bunny
	add_child(camera_rig)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("act"):
		act()


## The action button: hammer the stake in, or pull it out when the bunny is next to it.
func act() -> String:
	if _busy > 0.0:
		return "busy"
	var spot := bunny.position + bunny.global_transform.basis.z * 0.35
	spot.y = Terrain.height(spot.x, spot.z)
	var what := rules.act(spot if rules.steers_tofu() else bunny.position)
	match what:
		"staked":
			stake.hammer_in(spot)
			leash.reattach_b(stake.top)
			_busy = HAMMER_TIME
			bunny.gait.hammer()
			bunny.velocity = Vector3.ZERO
			bunny.face_target = spot
			camera_rig.target = bunny
			camera_rig.second = tofu
		"picked":
			stake.pull_out()
			leash.reattach_b(_hand)
			camera_rig.target = tofu
			camera_rig.second = bunny
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
	if _busy > 0.0:
		_busy -= delta
		if _busy <= 0.0:
			bunny.face_target = Vector3.INF
	var eyes := Vector3(0, 1.0, 0)
	if rules.steers_tofu():
		_drive(tofu, v, running, delta)
		_follow(bunny, tofu.position, delta)
		tofu.face_target = Vector3.INF
		tofu.gait.look_target = Vector3.INF
		bunny.gait.hold_target = _collar.global_position
		bunny.gait.look_target = tofu.position + eyes
	else:
		bunny.gait.dragged = false
		bunny.gait.hold_target = Vector3.INF
		bunny.gait.look_target = Vector3.INF
		tofu.gait.look_target = bunny.position + eyes
		if _busy > 0.0:
			bunny.steer(Vector3.ZERO, delta, 30.0)
		else:
			_drive(bunny, v, running, delta)
		# TOFU stays where the leash lets it be and watches the bunny.
		tofu.steer(Vector3.ZERO, delta)
		tofu.place(LeashRules.clamp_to(tofu.position, rules.stake_pos, LEASH_GROUND), delta)
		tofu.face_target = bunny.position
	stake.set_hint(rules.can_pick(bunny.position), _time)
	button.set_active(rules.steers_tofu() or rules.can_pick(bunny.position))


## The player's character: walk with the stick, run with the stick pushed far (or Shift).
func _drive(who: Actor, v: Vector2, running: bool, delta: float) -> void:
	var top: float = who.data.run if running else who.data.walk
	who.steer(Vector3(v.x, 0, v.y) * top, delta)


## The bunny holding the leash: walks after TOFU, and is dragged when the leash is taut.
func _follow(who: Actor, leader: Vector3, delta: float) -> void:
	var to := leader - who.position
	to.y = 0.0
	var dist := to.length()
	var want := Vector3.ZERO
	if dist > 0.001:
		want = to / dist * LeashRules.follow_speed(dist, LEASH_GROUND, float(who.data.run))
	who.velocity = who.velocity.move_toward(want, 10.0 * delta)
	var free := who.position + who.velocity * delta
	var held := LeashRules.clamp_to(free, leader, LEASH_GROUND)
	var dragged := free.distance_to(held) > 0.002
	who.face_target = leader if dragged else Vector3.INF
	who.extra_lean = -0.22 if dragged else 0.0
	who.gait.dragged = dragged
	who.gait.hold_pull = lerpf(who.gait.hold_pull, 1.0 if dragged else 0.15, 1.0 - exp(-3.0 * delta))
	who.place(held, delta)


func _on_step(pos: Vector3, size: float, who: Node3D) -> void:
	footprints.add(pos, who.rotation.y, size * 0.8)
	puffs.puff(pos, size)


## Pushes a walker of `radius` out of trees and rocks and keeps it in the play area.
func resolve(pos: Vector3, radius: float) -> Vector3:
	return resolve_against(pos, radius, obstacles)


static func resolve_against(pos: Vector3, radius: float, obs: Array[Vector3]) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	for o in obs:
		var d := p - Vector2(o.x, o.y)
		var min_d := o.z + radius
		var l := d.length()
		if l < min_d:
			p = Vector2(o.x, o.y) + (d / l if l > 0.0001 else Vector2.RIGHT) * min_d
	if p.length() > Terrain.PLAY_RADIUS:
		p = p.normalized() * Terrain.PLAY_RADIUS
	return Vector3(p.x, pos.y, p.y)


func _build_light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#8fb4e8")
	sky_mat.sky_horizon_color = Color("#dfe8f5")
	sky_mat.ground_horizon_color = Color("#dfe8f5")
	sky_mat.ground_bottom_color = Color("#c8d4ea")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	# Shade is lit only by this cold lilac ambient: blue shadows on white snow.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a7b2de")
	env.ambient_light_energy = 0.62
	env.fog_enabled = true
	env.fog_light_color = Color("#dce6f5")
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Low warm sun: long shadows across the snow.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-34, -35, 0)
	sun.light_color = Color("#fff1de")
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
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
		"act": [KEY_SPACE, KEY_E],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
