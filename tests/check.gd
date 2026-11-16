class_name Check
extends RefCounted
## Tiny assert helpers for the headless test suites.

static var failures := 0


static func ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


static func finish(tree: SceneTree) -> void:
	print("FAILED %d" % failures if failures > 0 else "ALL PASSED")
	tree.quit(1 if failures > 0 else 0)
