class_name LeashRules
extends RefCounted
## Who is on the leash and who the player steers.
## HELD: the bunny holds the leash, the player steers TOFU, TOFU drags the bunny.
## STAKED: the leash is tied to a stake, the player steers the bunny, TOFU stays within reach.

enum State { HELD, STAKED }

const PICK_RADIUS := 1.4   ## how close the bunny must be to pull the stake out, metres

var state := State.HELD
var stake_pos := Vector3.ZERO


## The player pressed the action button. Returns what happened:
## "staked", "picked", or "too_far" (nothing changes).
func act(bunny_pos: Vector3) -> String:
	if state == State.HELD:
		state = State.STAKED
		stake_pos = bunny_pos
		return "staked"
	if Vector2(bunny_pos.x - stake_pos.x, bunny_pos.z - stake_pos.z).length() <= PICK_RADIUS:
		state = State.HELD
		return "picked"
	return "too_far"


func steers_tofu() -> bool:
	return state == State.HELD


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
