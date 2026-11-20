class_name Footprints
extends MultiMeshInstance3D
## Paw prints pressed into the sand. A ring buffer: the oldest print is reused.

const MAX_PRINTS := 320

var _next := 0


func _ready() -> void:
	var st := PaperMesh.begin()
	PaperMesh.disc(st, Transform3D.IDENTITY, 0.075, 0.11, 8, Color.WHITE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true   # each print takes a darker shade of the ground it is pressed into
	mm.mesh = PaperMesh.commit(st)
	mm.instance_count = MAX_PRINTS
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0))
	for i in range(MAX_PRINTS):
		mm.set_instance_transform(i, hidden)
	multimesh = mm
	material_override = PaperMesh.material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Presses a print at `pos` (ground height is taken from the terrain), turned by `yaw`.
func add(pos: Vector3, yaw: float, size := 1.0) -> void:
	var y := Terrain.height(pos.x, pos.z) + 0.02
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size)
	multimesh.set_instance_transform(_next, Transform3D(basis, Vector3(pos.x, y, pos.z)))
	var ground := Terrain.ground_color(y - 0.02, Terrain.normal(pos.x, pos.z))
	multimesh.set_instance_color(_next, Color(ground.r * 0.8, ground.g * 0.78, ground.b * 0.74))
	_next = (_next + 1) % MAX_PRINTS


func count_visible() -> int:
	var n := 0
	for i in range(MAX_PRINTS):
		if multimesh.get_instance_transform(i).basis.get_scale().x > 0.0:
			n += 1
	return n
