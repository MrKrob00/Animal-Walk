class_name LowPassages
extends RefCounted
## Low places to crawl under (the player chose: walkers get down by themselves under something
## low, and crawl): fallen palm trunks lying across two rocks, CLEAR above the ground. Whoever is
## under one crawls (army crawl); the rocks are in the way, the trunk is not (you pass under it),
## and the leash lies over the trunk instead of through it.

const CLEAR := 0.55        ## metres from the ground to the trunk's underside
const LOG_R := 0.17        ## trunk radius
const SPAN := 2.8          ## metres between the two rocks' centres
const ROCK_BLOCK := 0.5    ## the rocks block this far round their centres
const REACH := 0.65        ## crawl from this far either side of the trunk's line
const COUNT := 12
const NEAR_START := 10.0   ## one lies this far from the start, so the player meets it early


## Where the passages lie: [{"c": Vector2 centre, "dir": Vector2 along the trunk, "y": float}].
static func place(seed_value := 4242) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	var start := WorldBuilder.clearing_center()
	# The first: on the beach near the start, the trunk across the way along the beach.
	for k in 40:
		var ang := -PI * 0.5 + (0.06 + 0.01 * k) * (1.0 if k % 2 == 0 else -1.0)
		var p := Vector2(cos(ang), sin(ang)) * Terrain.shore(ang) * 0.9
		if p.distance_to(start) > NEAR_START * 0.7 and p.distance_to(start) < NEAR_START * 1.6 and _fits(p, Vector2(cos(ang), sin(ang)), out):
			out.append({"c": p, "dir": Vector2(cos(ang), sin(ang)), "y": _ground(p, Vector2(cos(ang), sin(ang)))})
			break
	var tries := 0
	while out.size() < COUNT and tries < 4000:
		tries += 1
		var ang := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.9
		var p := Vector2(cos(ang), sin(ang)) * d * Terrain.shore(ang)
		var dir := Vector2.from_angle(rng.randf() * PI)
		if p.distance_to(start) < WorldBuilder.CLEARING_RADIUS + 2.0 or not _fits(p, dir, out):
			continue
		out.append({"c": p, "dir": dir, "y": _ground(p, dir)})
	return out


## Dry, fairly flat, and clear of the other passages.
static func _fits(p: Vector2, dir: Vector2, others: Array) -> bool:
	for o in others:
		if (o.c as Vector2).distance_to(p) < 14.0:
			return false
	var hs := []
	for t in [-0.5, 0.0, 0.5]:
		for s in [-1.0, 1.0]:
			var q: Vector2 = p + dir * SPAN * t + dir.orthogonal() * REACH * 1.5 * s
			hs.append(Terrain.height(q.x, q.y))
	return hs.min() > 0.12 and hs.max() - hs.min() < 0.35 and hs.max() < 3.5


static func _ground(p: Vector2, dir: Vector2) -> float:
	var a := p - dir * SPAN * 0.5
	var b := p + dir * SPAN * 0.5
	return maxf(Terrain.height(a.x, a.y), maxf(Terrain.height(b.x, b.y), Terrain.height(p.x, p.y)))


## The trunk's ends in the world (for the leash and for drawing).
static func trunk(pass_: Dictionary) -> Array:
	var c: Vector2 = pass_.c
	var dir: Vector2 = pass_.dir
	var y: float = pass_.y + CLEAR + LOG_R
	var half := SPAN * 0.5 + 0.45
	return [Vector3(c.x - dir.x * half, y, c.y - dir.y * half), Vector3(c.x + dir.x * half, y, c.y + dir.y * half)]


## The places other things must leave free: [Vector3(x, z, radius)].
static func reserved(passages: Array) -> Array:
	var out := []
	for p in passages:
		out.append(Vector3(p.c.x, p.c.y, SPAN * 0.5 + 1.2))
	return out


## Builds the trunks and rocks (one mesh) under `root` and puts the rocks into `obs`.
static func build(root: Node3D, obs: Obstacles, passages: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var st := PaperMesh.begin()
	for p in passages:
		var c: Vector2 = p.c
		var dir: Vector2 = p.dir
		var ends := trunk(p)
		var along := (ends[1] - ends[0]) as Vector3
		var length := along.length()
		# The trunk: a tapered cylinder lying along `dir`, a few rings drawn darker.
		var basis := Basis(_arc(Vector3.UP, along.normalized()))
		PaperMesh.frustum(st, Transform3D(basis, ends[0]), LOG_R * 1.1, LOG_R * 0.85, length, 9, PaperMesh.col(WorldBuilder.TRUNK))
		for k in [0.2, 0.5, 0.8]:
			PaperMesh.frustum(st, Transform3D(basis, ends[0] + along * k), LOG_R * 1.12 - 0.04 * k, LOG_R * 1.1 - 0.04 * k, 0.05, 9, PaperMesh.col(WorldBuilder.TRUNK_RING))
		# A broken stub of a frond on top.
		PaperMesh.frustum(st, Transform3D(Basis(_arc(Vector3.UP, Vector3(0.3, 1, 0.2).normalized())), ends[0] + along * 0.62 + Vector3(0, LOG_R * 0.8, 0)), 0.05, 0.01, 0.35, 5, PaperMesh.col(WorldBuilder.FROND_DARK))
		for s in [-1.0, 1.0]:
			var q: Vector2 = c + dir * SPAN * 0.5 * s
			var gy := Terrain.height(q.x, q.y)
			var top: float = p.y + CLEAR - gy
			PaperMesh.ellipsoid(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, gy - 0.05, q.y)), Vector3(0.62, maxf(top, 0.3) + 0.05, 0.56), 7, 4, PaperMesh.col(WorldBuilder.STONE), 0.2, rng)
			obs.add(q.x, q.y, ROCK_BLOCK)
	var mi := MeshInstance3D.new()
	mi.name = "LowPassages"
	mi.mesh = PaperMesh.commit(st)
	mi.material_override = PaperMesh.material()
	root.add_child(mi)


## Is `p` (x, z) under one of the trunks, where a walker must crawl?
static func under(p: Vector2, passages: Array) -> bool:
	for o in passages:
		var d: Vector2 = p - o.c
		if absf(d.dot(o.dir)) < SPAN * 0.5 - 0.2 and absf(d.dot((o.dir as Vector2).orthogonal())) < REACH:
			return true
	return false


## Capsules for the leash to lie over: [a, b, radius].
static func capsules(passages: Array) -> Array:
	var out := []
	for p in passages:
		var e := trunk(p)
		out.append([e[0], e[1], LOG_R])
	return out


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var c := a.cross(b)
	var d := a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY if d > 0.0 else Quaternion(Vector3.RIGHT, PI)
	return Quaternion(c.normalized(), atan2(c.length(), d))
