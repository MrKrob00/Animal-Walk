class_name LeashRules
extends RefCounted
## Who is on the leash and who the player steers.
## HELD: the bunny holds the leash (the player starts with TOFU).
## STAKED: the leash is tied to a stake (the player is given the bunny), TOFU stays within reach.
## Each walks by itself; only the leash ties them (the player plans co-op): pulling apart they
## pull each other, one standing is led by the other. The switch button (for testing each
## character) changes who the player steers at any time.

enum State { HELD, STAKED }

const PICK_RADIUS := 1.4   ## how close the bunny must be to pull the stake out, metres

var state := State.HELD
var stake_pos := Vector3.ZERO
var steered_tofu := true


## The player pressed the action button. Returns what happened:
## "staked", "picked", or "too_far" (nothing changes).
func act(bunny_pos: Vector3) -> String:
	if state == State.HELD:
		state = State.STAKED
		steered_tofu = false
		stake_pos = bunny_pos
		return "staked"
	if Vector2(bunny_pos.x - stake_pos.x, bunny_pos.z - stake_pos.z).length() <= PICK_RADIUS:
		state = State.HELD
		steered_tofu = true
		return "picked"
	return "too_far"


func steers_tofu() -> bool:
	return steered_tofu


func held() -> bool:
	return state == State.HELD


## The switch button: the player takes the other character.
func switch() -> void:
	steered_tofu = not steered_tofu


## The leash between `a` and `b` (ground plane) at most `length`: the overshoot is taken back
## from each in the share `wa` : `wb` (one standing gives way fully, two pulling give way half
## each). Returns [a, b].
static func tug(a: Vector3, b: Vector3, length: float, wa: float, wb: float) -> Array:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var over := d.length() - length
	if over <= 0.0:
		return [a, b]
	var n := d.normalized()
	var ka := wa / maxf(wa + wb, 1e-6) if wa + wb > 0.0 else 0.5
	var fix := n * over
	return [a + Vector3(fix.x, 0, fix.y) * ka, b - Vector3(fix.x, 0, fix.y) * (1.0 - ka)]


## Two bodies never closer than `gap` (ground plane): the overlap is taken back from each in the
## share `wa` : `wb` (the one walking into the other is stopped, a standing one is not pushed).
## Returns [a, b].
static func separate(a: Vector3, b: Vector3, gap: float, wa: float, wb: float) -> Array:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var dist := d.length()
	if dist >= gap:
		return [a, b]
	var n := d / dist if dist > 1e-5 else Vector2(1, 0)
	var ka := wa / (wa + wb) if wa + wb > 1e-6 else 0.5
	var fix := n * (gap - dist)
	return [a - Vector3(fix.x, 0, fix.y) * ka, b + Vector3(fix.x, 0, fix.y) * (1.0 - ka)]


func can_pick(bunny_pos: Vector3) -> bool:
	return state == State.STAKED and Vector2(bunny_pos.x - stake_pos.x, bunny_pos.z - stake_pos.z).length() <= PICK_RADIUS


## Keeps `who` within `length` of `anchor` on the ground plane.
static func clamp_to(who: Vector3, anchor: Vector3, length: float) -> Vector3:
	var d := Vector2(who.x - anchor.x, who.z - anchor.z)
	if d.length() <= length:
		return who
	d = d.normalized() * length
	return Vector3(anchor.x + d.x, who.y, anchor.z + d.y)


## How fast the one being led wants to walk toward the leader at this distance.
static func follow_speed(dist: float, length: float, walk: float) -> float:
	var start := length * 0.55
	if dist <= start:
		return 0.0
	return walk * clampf((dist - start) / (length * 0.3), 0.3, 1.0)
