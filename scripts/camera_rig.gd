class_name CameraRig
extends Node3D
## Third-person camera (the player asked for one like in mobile shooters): it floats after the
## character you steer and orbits it.
##   Phone: drag on the right part of the screen to turn it round and up / down; pinch with two
##          fingers to come closer or move away. The left part is the walking stick.
##   PC:    drag with the right mouse button (or the left one on the right part) to turn; the
##          wheel zooms.
## First person (a button, or V): the camera sits at the eyes of the character you steer, whose
## head is hidden so it never gets in the way; the head turns after the view only partly (the
## eyes do the rest), so looking down shows the bunny's chest or TOFU's collar without breaking
## a neck. The view is the body's own: when the body turns (walking off sideways or back, the
## hammer), the view turns with it; walking keeps the direction it set off in, the drag steers it.
## Walking is relative to the camera: the stick's "up" goes away from the camera.

const FOV := 50.0
const DISTANCE := 4.5            ## starting distance, metres
const MIN_DISTANCE := 2.0
const MAX_DISTANCE := 10.0
const PITCH := deg_to_rad(24.0)  ## starting angle above the horizon
const MIN_PITCH := deg_to_rad(5.0)
const MAX_PITCH := deg_to_rad(75.0)
const TURN := 0.006              ## radians per pixel dragged
const WHEEL := 1.12              ## zoom step per wheel notch
const LOOK_HEIGHT := 0.9         ## metres above the character's feet the camera looks at
const LOOK_HEIGHT_CRAWL := 0.35  ## ... while it crawls
const CLEARANCE := 0.35          ## the camera stays this far above the ground

var target: Node3D       ## the character the player steers
var second: Node3D       ## the other one (the camera leans a little toward it)
var camera: Camera3D
var button: Control      ## the action button (its touches are not for the camera)
var stick_zone := 0.6    ## left share of the screen that belongs to the walking stick

var buttons: Array = []  ## more on-screen buttons whose touches are not for the camera
var first_person := false
var look := -0.2         ## first person: up (+) / down (-) from the horizon, radians
const LOOK_MIN := -1.45  ## first person: furthest down (her chest shows; the neck turns only part of it)
const LOOK_MAX := 0.9
var _hidden_on: Node3D   ## whose head is hidden (first person)
var body_leads := false  ## first person: the body turns by itself now (walking, busy), the view goes with it
var _aim := 0.0          ## first person, walking: the yaw the stick is read against (the drag turns it)
var _body_yaw := INF     ## the steered body's facing last frame, as a camera yaw
var yaw := 0.0           ## round the character; 0 looks toward -Z (the sea at the start)
var pitch := PITCH
var distance := DISTANCE
var _zoom := DISTANCE    ## the distance being eased toward
var _fingers := {}       ## touch index -> last position, for the camera's own touches
var _pinch := 0.0
var _rmb := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.far = 160.0
	add_child(camera)
	camera.make_current()
	if target != null:
		position = _focus()
	_place_camera()


func _focus() -> Vector3:
	var f := target.position
	if second != null:
		f = f.lerp(second.position, 0.15)
	var low := 0.0
	if "gait" in target and target.gait != null:
		low = smoothstep(0.0, 1.0, target.gait.crawl)
	return f + Vector3(0, lerpf(LOOK_HEIGHT, LOOK_HEIGHT_CRAWL, low), 0)   # down with a crawler


## The ground directions the stick means: [right, forward] (unit, horizontal).
func ground_axes() -> Array:
	var y := _aim if first_person and body_leads else yaw
	var fwd := Vector3(-sin(y), 0.0, -cos(y))
	var right := Vector3(cos(y), 0.0, -sin(y))
	return [right, fwd]


## A stick / key vector (x right, y down as on screen) as a direction on the ground.
func to_ground(v: Vector2) -> Vector3:
	var ax := ground_axes()
	return ax[0] * v.x + ax[1] * -v.y


func turn(dx: float, dy: float) -> void:
	if first_person and body_leads:
		_aim -= dx * TURN    # walking: steer; the body turns that way and the view with it
	else:
		yaw -= dx * TURN
	if first_person:
		look = clampf(look - dy * TURN, LOOK_MIN, LOOK_MAX)
	else:
		pitch = clampf(pitch + dy * TURN, MIN_PITCH, MAX_PITCH)


## Switches between third person and the eyes of the character being steered.
func toggle_first_person() -> void:
	set_first_person(not first_person)


func set_first_person(on: bool) -> void:
	first_person = on
	look = -0.2
	if on and target != null:
		yaw = body_yaw(target)   # start from where the character looks
	_body_yaw = INF
	camera.near = 0.03 if on else 0.05
	_show_head()


## The way `who` faces, as a camera yaw (the models face +Z).
static func body_yaw(who: Node3D) -> float:
	return who.rotation.y + PI


## First person: whether the body turns by itself now (the stick is held, or it is busy); while it
## does, the view turns with it and the stick keeps the direction it was pushed in.
func set_body_leads(on: bool) -> void:
	if on and not body_leads:
		_aim = yaw
	body_leads = on


func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, MIN_DISTANCE, MAX_DISTANCE)


## Sets the distance straight away, without the player's limits (for scripted shots).
func set_distance(d: float) -> void:
	distance = d
	_zoom = d
	_place_camera()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(1.0 / WHEEL)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(WHEEL)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = event.pressed
	elif event is InputEventMouseMotion and _rmb:
		turn(event.relative.x, event.relative.y)
	elif event is InputEventScreenTouch:
		if event.pressed:
			if _owns(event.position):
				_fingers[event.index] = event.position
				_pinch = _spread()
		elif _fingers.has(event.index):
			_fingers.erase(event.index)
			_pinch = _spread()
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		if _fingers.size() >= 2:
			_fingers[event.index] = event.position
			var s := _spread()
			if _pinch > 1.0 and s > 1.0:
				zoom_by(_pinch / s)   # fingers apart: closer
			_pinch = s
		else:
			turn(event.relative.x, event.relative.y)
			_fingers[event.index] = event.position


## A touch is the camera's when it lands on the right part of the screen (not on the action
## button), or anywhere once the walking stick is already held.
func _owns(p: Vector2) -> bool:
	var size := get_viewport().get_visible_rect().size
	for b in [button] + buttons:
		if b != null and b.has_method("center") and p.distance_to(b.center()) <= float(b.get("RADIUS")) * 1.2:
			return false
	return p.x >= size.x * stick_zone or _stick_held()


func _stick_held() -> bool:
	var main := get_parent()
	return main != null and "joystick" in main and main.joystick != null and main.joystick._finger >= 0


func _spread() -> float:
	if _fingers.size() < 2:
		return 0.0
	var pts := _fingers.values()
	return (pts[0] as Vector2).distance_to(pts[1])


## Releases the camera's fingers (when a pausing window closes, like the stick).
func release() -> void:
	_fingers.clear()
	_rmb = false


func _process(delta: float) -> void:
	if target == null:
		return
	position = position.lerp(_focus(), 1.0 - exp(-6.0 * delta))
	distance = lerpf(distance, _zoom, 1.0 - exp(-10.0 * delta))
	_place_camera()
	if first_person and target.has_method("eye_position"):
		_show_head()
		var by := body_yaw(target)
		if body_leads and _body_yaw != INF:
			yaw += angle_difference(_body_yaw, by)   # the body turned: the eyes turn with it
		_body_yaw = by
		var eye: Vector3 = target.eye_position()
		_fp_at = _fp_at.lerp(eye, 1.0 - exp(-25.0 * delta)) if _fp_ready else eye   # smooths the head's jitter
		_fp_ready = true
		camera.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, look), _fp_at)
		if "gait" in target:
			target.gait.view_dir = -camera.global_basis.z
	else:
		_fp_ready = false
		_body_yaw = INF


var _fp_ready := false
var _fp_at := Vector3.ZERO


## First person: the steered character's head is hidden (so it never blocks the eyes); everyone
## else shows theirs; its head stops following the view.
func _show_head() -> void:
	var who: Node3D = target if first_person else null
	if _hidden_on != null and is_instance_valid(_hidden_on) and _hidden_on != who:
		_hidden_on.set("head_hidden", false)
		if "gait" in _hidden_on:
			_hidden_on.gait.view_dir = Vector3.INF
	if who != null and "head_hidden" in who:
		who.set("head_hidden", true)
	_hidden_on = who


func _place_camera() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	var p := pitch
	var local := Vector3(0.0, sin(p) * distance, cos(p) * distance)
	var world := global_transform * local if is_inside_tree() else position + basis * local
	# Never under the ground: rise above it and look down a little more.
	var floor_y := maxf(Terrain.height(world.x, world.z), 0.0) + CLEARANCE
	if world.y < floor_y:
		local.y += floor_y - world.y
	camera.position = local
	camera.rotation = Vector3(-atan2(local.y, local.z), 0.0, 0.0)
