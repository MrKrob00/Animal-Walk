class_name PawReach
extends RefCounted
## TOFU's right paw on the second stick (the player asked): the stick points the arm round
## the shoulder (left / right, up / down) and the paw reaches out along that line until it meets
## something: the ground, a rock, bush or trunk, or the bunny's body. It never goes inside them;
## only her soft chest gives a little under it (and her skin is pushed out of the paw by the
## shader, `shaders/soft_press.gdshader`), which also wobbles it (`Gait.soft_poke`).

const AZ_OUT := 1.2     ## radians the arm swings out to the right side (stick right)
const AZ_IN := 0.7      ## ... and across the chest (stick left)
const EL_UP := 1.2      ## radians above the shoulder's horizon (stick up)
const EL_DOWN := 1.1    ## ... and below it (stick down)
const START := 0.12     ## the sweep starts this far from the shoulder (outside its own body)
const STEPS := 20
const SOFT_GIVE := 0.03 ## metres the paw may sink into soft skin (the chest)
const MIN_REACH := 0.2  ## a paw stopped closer than this to the shoulder would fold the arm up
                        ## unnaturally: the arm goes lower instead (or stays down)
const LOWER := 0.2      ## radians per try, lowering the arm


## The line the stick points along, in the world: `stick` x right, y down as on the screen.
static func direction(who: Node3D, stick: Vector2) -> Vector3:
	var b := who.global_basis.orthonormalized()
	var fwd := b.z            # the models face +Z
	var right := -b.x         # ... so their right is -X
	var az := stick.x * (AZ_OUT if stick.x > 0.0 else AZ_IN)
	var el := -stick.y * (EL_UP if stick.y < 0.0 else EL_DOWN)
	return (right * sin(az) * cos(el) + fwd * cos(az) * cos(el) + Vector3.UP * sin(el)).normalized()


## Where the paw goes along `dir`, or, when that line is blocked close to the shoulder, along
## the nearest lower line that is not; {} when none is (the arm stays down). See `reach`.
static func reach_free(shoulder: Vector3, dir: Vector3, arm: float, paw_r: float, paw_off: float, shapes: Array, obs: Obstacles) -> Dictionary:
	var axis := dir.cross(Vector3.UP)
	axis = axis.normalized() if axis.length() > 1e-4 else Vector3.RIGHT
	var d := dir
	for i in 8:
		var r := reach(shoulder, d, arm, paw_r, paw_off, shapes, obs)
		if (r.paw as Vector3).distance_to(shoulder) >= MIN_REACH:
			return r
		d = d.rotated(axis, -LOWER)   # turns the line downward (about dir x up, + would raise it)
		if d.y < -0.95:
			break
	return {}


## Where the paw goes: {"paw": centre, "wrist": the wrist's goal, "hit": met something,
## "soft": met soft skin}. `shapes`: capsules [a, b, radius, soft]; `obs`: Obstacles or null.
static func reach(shoulder: Vector3, dir: Vector3, arm: float, paw_r: float, paw_off: float, shapes: Array, obs: Obstacles) -> Dictionary:
	var from := shoulder + dir * START
	var to := shoulder + dir * (arm + paw_off)
	var at := from
	var hit := false
	if not _blocked(from, paw_r, shapes, obs):
		var lo := 0.0
		var hi := 1.0
		for i in range(1, STEPS + 1):
			var t := float(i) / STEPS
			if _blocked(from.lerp(to, t), paw_r, shapes, obs):
				hi = t
				hit = true
				break
			lo = t
		if hit:
			for i in 6:
				var mid := (lo + hi) * 0.5
				if _blocked(from.lerp(to, mid), paw_r, shapes, obs):
					hi = mid
				else:
					lo = mid
		at = from.lerp(to, lo)
	else:
		hit = true
	return {"paw": at, "wrist": at - dir * paw_off, "hit": hit, "soft": hit and touches_soft(at, paw_r, shapes)}


## Is a paw of radius `r` at `p` inside anything?
static func _blocked(p: Vector3, r: float, shapes: Array, obs: Obstacles) -> bool:
	if p.y - r < Terrain.height(p.x, p.z):
		return true
	if obs != null:
		for o in obs.near(p.x, p.z, 1.0):
			if Vector2(p.x - o.x, p.z - o.y).length() < o.z + r:
				return true
	for s in shapes:
		var give := SOFT_GIVE if s[3] else 0.0
		if seg_distance(p, s[0], s[1]) < float(s[2]) + r - give:
			return true
	return false


## Does the paw at `p` touch soft skin?
static func touches_soft(p: Vector3, r: float, shapes: Array) -> bool:
	for s in shapes:
		if s[3] and seg_distance(p, s[0], s[1]) < float(s[2]) + r + 0.005:
			return true
	return false


static func seg_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)
