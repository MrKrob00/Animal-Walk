extends Node3D
## Builds the first scene: a snowy mountain clearing, the wolf and the fox kit on a leash.

const LEASH_WALK := 3.0    ## how far the kit can be on the ground
const LEASH_ROPE := 3.3    ## rope length in 3D (hands are at different heights)

var obstacles: Array[Vector3] = []   ## x, z, radius
var player: Player
var kit: Follower
var leash: Leash
var footprints: Footprints
var puffs: SnowPuffs
var joystick: TouchJoystick
var camera_rig: CameraRig


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

	var ui := CanvasLayer.new()
	add_child(ui)
	joystick = TouchJoystick.new()
	ui.add_child(joystick)

	player = Player.new()
	player.name = "Player"
	player.world = self
	player.joystick = joystick
	player.position = Vector3(0, Terrain.height(0, 2), 2)
	add_child(player)

	kit = Follower.new()
	kit.name = "Kit"
	kit.world = self
	kit.leader = player
	kit.leash_len = LEASH_WALK
	kit.position = Vector3(-1.2, Terrain.height(-1.2, 3.8), 3.8)
	add_child(kit)

	leash = Leash.new()
	leash.name = "Leash"
	leash.a = player.critter.hand_r
	leash.b = kit.critter.hand_l
	leash.length = LEASH_ROPE
	add_child(leash)

	player.critter.footstep.connect(_on_step.bind(player))
	kit.critter.footstep.connect(_on_step.bind(kit))

	camera_rig = CameraRig.new()
	camera_rig.target = player
	camera_rig.second = kit
	add_child(camera_rig)


func _on_step(pos: Vector3, size: float, who: Node3D) -> void:
	footprints.add(pos, who.rotation.y, size)
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
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
