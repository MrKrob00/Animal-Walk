extends SceneTree
## The stake rules: who the player steers, when the stake goes in and comes out.

func _initialize() -> void:
	var r := LeashRules.new()
	Check.ok(r.steers_tofu(), "at start the player steers TOFU")
	Check.ok(r.act(Vector3(1, 0, 2)) == "staked", "the button hammers the stake in")
	Check.ok(not r.steers_tofu(), "with the stake in, the player steers the bunny")
	Check.ok(r.stake_pos == Vector3(1, 0, 2), "the stake is where the bunny was")
	Check.ok(r.act(Vector3(5, 0, 2)) == "too_far", "far from the stake the button does nothing")
	Check.ok(not r.steers_tofu(), "still steering the bunny after a press far away")
	Check.ok(r.can_pick(Vector3(1.5, 0, 2.5)), "next to the stake it can be pulled out")
	Check.ok(r.act(Vector3(1.5, 0, 2.5)) == "picked", "next to the stake the button pulls it out")
	Check.ok(r.steers_tofu(), "with the leash in hand the player steers TOFU again")
	Check.finish(self)
