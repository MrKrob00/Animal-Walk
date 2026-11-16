extends SceneTree
## The leash keeps the two ends within its length; the one led walks only when far.

func _initialize() -> void:
	var p := LeashRules.clamp_to(Vector3(10, 3, 0), Vector3.ZERO, 3.0)
	Check.ok(is_equal_approx(Vector2(p.x, p.z).length(), 3.0), "pulled back to the leash length")
	Check.ok(p.y == 3.0, "height is left to the terrain")
	var q := LeashRules.clamp_to(Vector3(1, 0, 1), Vector3.ZERO, 3.0)
	Check.ok(q == Vector3(1, 0, 1), "inside the reach nothing moves")
	Check.ok(LeashRules.follow_speed(1.0, 3.0, 2.0) == 0.0, "close by, the one led stands")
	Check.ok(LeashRules.follow_speed(2.9, 3.0, 2.0) > 1.5, "near the end of the leash, it hurries")
	Check.finish(self)
