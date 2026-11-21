class_name PawReach
extends RefCounted
## TOFU's right paw on the second stick (the player asked): the stick points the arm round
## the shoulder (left / right, up / down) and the paw reaches out along that line until it meets
## something: the ground, a rock, bush or trunk, or the bunny's body. It never goes inside them;
## only her soft chest gives a little under it (and her skin is pushed out of the paw by the
## shader, `shaders/soft_press.gdshader`), which also wobbles it (`Gait.soft_poke`).
## The paw is its palm (about 3 cm thick, the player wanted it to come right up to things, not
## stop short as a 6 cm ball did): where it meets something it lies on it - the palm turned to
## the surface, the fingers along it, curled round what curves away under them (`Gait`).

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
const FINGER := 0.07    ## metres from the palm's middle to the finger tips
const FINGERS_UP := 0.7 ## how much the fingers point up a steep surface (besides the reach's way)
const CURL_MAX := 1.2   ## radians the fingers curl at most round a surface (and bend back -0.25)


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
			if not r.hit or (not r.soft and _nearest(r.paw, paw_r, shapes, obs).kind == "shape"):
				return _onto_chest(r, shoulder, arm, paw_r, paw_off, shapes, obs)   # in the air, or on her body beside it
			return r
		d = d.rotated(axis, -LOWER)   # turns the line downward (about dir x up, + would raise it)
		if d.y < -0.95:
			break
	return {}


## A paw in the air (or on her body) next to her chest goes onto it (the player: it slid along its edge, now and
## then touching): her chest sits about at the end of TOFU's reach, so a line pointed at it
## mostly passed by or fell short. Within CHEST_PULL of a spot on it that the arm can reach, the
## paw reaches for that spot instead. Chest: soft shapes of no flesh region ([.., soft, -1]).
const CHEST_PULL := 0.12

static func _onto_chest(r: Dictionary, shoulder: Vector3, arm: float, paw_r: float, paw_off: float, shapes: Array, obs: Obstacles) -> Dictionary:
	var p: Vector3 = r.paw
	var best := CHEST_PULL
	var spot := Vector3.INF
	for s in shapes:
		if s.size() < 5 or not s[3] or int(s[4]) >= 0:
			continue
		var ab: Vector3 = s[1] - s[0]
		var q: Vector3 = s[0] + ab * clampf((p - s[0]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var n := (p - q).normalized() if p.distance_to(q) > 1e-5 else (shoulder - q).normalized()
		var on: Vector3 = q + n * (float(s[2]) + paw_r - SOFT_GIVE * 0.5)
		var gap := p.distance_to(on)
		if gap < best and on.distance_to(shoulder) <= arm + paw_off:
			best = gap
			spot = on
	if spot == Vector3.INF:
		return r
	var there := reach(shoulder, (spot - shoulder).normalized(), arm, paw_r, paw_off, shapes, obs)
	return there if there.soft else r


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
	var out := {"paw": at, "hit": hit, "soft": hit and touches_soft(at, paw_r, shapes), "normal": Vector3.ZERO, "tan": dir, "curl": 0.0}
	if hit:
		# The surface it meets: the nearest thing to the palm, its normal, the fingers along it,
		# and how far it falls away under the finger tips (the fingers curl after it).
		var near := _nearest(at, paw_r, shapes, obs)
		var n: Vector3 = near.normal
		# The fingers along the surface: the way the arm reaches, and up it (a paw pressed on a wall
		# or a body in front points its fingers up, as a hand does; reaching straight at it, the
		# reach's own way along it is short and swings about, and wrung the wrist).
		var t := dir - n * dir.dot(n)
		var up := Vector3.UP - n * n.y
		t = t + up * FINGERS_UP
		t = t.normalized() if t.length() > 1e-3 else n.cross(Vector3.RIGHT).normalized()
		var tip := at + t * FINGER
		var gap: float = (_clearance(tip, paw_r, near) as float)
		out.normal = n
		out.tan = t
		out.curl = clampf(atan2(gap, FINGER), -0.25, CURL_MAX)
	return out


## The thing nearest the palm at `p`: {"kind", "normal", ...} (ground, an obstacle, a shape).
static func _nearest(p: Vector3, r: float, shapes: Array, obs: Obstacles) -> Dictionary:
	var best := {"kind": "ground", "normal": Vector3.UP, "clear": p.y - Terrain.height(p.x, p.z)}
	if obs != null:
		for o in obs.near(p.x, p.z, 1.0):
			var d := Vector2(p.x - o.x, p.z - o.y)
			var c: float = d.length() - float(o.z)
			if c < best.clear:
				var nd := d.normalized() if d.length() > 1e-5 else Vector2(1, 0)
				best = {"kind": "obstacle", "normal": Vector3(nd.x, 0, nd.y), "clear": c, "o": o}
	for s in shapes:
		var ab: Vector3 = s[1] - s[0]
		var k := clampf((p - s[0]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var q: Vector3 = s[0] + ab * k
		var c := p.distance_to(q) - float(s[2]) + (SOFT_GIVE if s[3] else 0.0)
		if c < best.clear:
			best = {"kind": "shape", "normal": (p - q).normalized() if p.distance_to(q) > 1e-5 else Vector3.UP, "clear": c, "s": s}
	return best


## How far a palm at `p` stands off the thing `near` beyond touching (0 = touching).
static func _clearance(p: Vector3, r: float, near: Dictionary) -> float:
	match near.kind:
		"obstacle":
			var o: Vector3 = near.o
			return Vector2(p.x - o.x, p.z - o.y).length() - o.z - r
		"shape":
			var s: Array = near.s
			return seg_distance(p, s[0], s[1]) - float(s[2]) + (SOFT_GIVE if s[3] else 0.0) - r
	return p.y - Terrain.height(p.x, p.z) - r


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
