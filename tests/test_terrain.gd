extends SceneTree
## The ground: walkable in the middle, mountains at the rim, no jumps.

func _initialize() -> void:
	Check.ok(absf(Terrain.height(0, 0)) < 3.0, "the clearing is low")
	Check.ok(Terrain.height(0, Terrain.PLAY_RADIUS + 24.0) > 10.0, "mountains rise around")
	Check.ok(absf(Terrain.height(5.0, 5.0) - Terrain.height(5.01, 5.0)) < 0.05, "the ground has no steps")
	var p: Vector3 = load("res://scripts/main.gd").resolve_against(Vector3(0.1, 0, 0), 0.3, [Vector3(0, 0, 1.0)] as Array[Vector3])
	Check.ok(Vector2(p.x, p.z).length() >= 1.299, "a walker is pushed out of a tree")
	Check.finish(self)
