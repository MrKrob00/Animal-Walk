class_name Stake
extends Node3D
## A wooden stake the leash ties to. Hammered in with three knocks, pulled out with a hop.

signal knocked(pos: Vector3)   ## each knock (for a puff or a sound)

const HEIGHT := 0.55
const WOOD := "#8a5a3c"
const WOOD_TOP := "#b98a62"
const ROPE := "#d8414a"

var top: Marker3D          ## where the leash ties
var _post: Node3D
var _tween: Tween


func _ready() -> void:
	_post = Node3D.new()
	add_child(_post)
	var st := PaperMesh.begin()
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0)), 0.02, 0.06, 0.25, 6, PaperMesh.col(WOOD))
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.06, 0.055, HEIGHT, 6, PaperMesh.col(WOOD))
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT, 0)), 0.065, 0.065, 0.04, 6, PaperMesh.col(WOOD_TOP))
	PaperMesh.frustum(st, Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT - 0.12, 0)), 0.068, 0.068, 0.05, 8, PaperMesh.col(ROPE))
	var mi := MeshInstance3D.new()
	mi.mesh = PaperMesh.commit(st)
	mi.material_override = PaperMesh.material()
	_post.add_child(mi)
	top = Marker3D.new()
	top.position = Vector3(0, HEIGHT - 0.1, 0)
	_post.add_child(top)
	visible = false


## Three knocks: the stake drops into the snow step by step, squashing on each hit.
func hammer_in(at: Vector3) -> void:
	position = at
	visible = true
	_kill()
	_post.position.y = 0.35
	_post.scale = Vector3.ONE
	_tween = create_tween()
	for i in range(3):
		var y := 0.35 - 0.35 * float(i + 1) / 3.0
		_tween.tween_property(_post, "position:y", y, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_callback(_knock)
		_tween.tween_property(_post, "scale", Vector3(1.15, 0.85, 1.15), 0.05)
		_tween.tween_property(_post, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(0.08)


## Pops out with a little hop and vanishes.
func pull_out() -> void:
	_kill()
	_knock()
	_tween = create_tween()
	_tween.tween_property(_post, "position:y", 0.45, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_post, "scale", Vector3.ONE * 0.2, 0.2).set_delay(0.08)
	_tween.tween_callback(func(): visible = false)


## A gentle bob while the bunny is close enough to pull it out (show, don't tell).
func set_hint(on: bool, t: float) -> void:
	if _tween != null and _tween.is_running():
		return
	var s := 1.0 + (0.06 * sin(t * 7.0) if on else 0.0)
	_post.scale = Vector3(s, 1.0, s)


func _knock() -> void:
	knocked.emit(global_position)


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
