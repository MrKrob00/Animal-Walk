class_name SoftPress
extends RefCounted
## Soft skin against the ground (shaders/soft_press.gdshader): lying down, what would go under
## the ground is squeezed up onto it per vertex and spreads a little. Swaps a model's plain
## textured materials for this one (same look) and keeps the ground height in it.

const SHADER := preload("res://shaders/soft_press.gdshader")
const BAND := 0.05


## Gives every mesh under `model` the soft material; returns the materials (one per surface).
static func apply(model: Node) -> Array:
	var out := []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for sf in m.mesh.get_surface_count():
			var old := m.get_active_material(sf)
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			if old is BaseMaterial3D and (old as BaseMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				push_warning("SoftPress: %s is lit; the soft material draws it unshaded" % m.name)
			if old is BaseMaterial3D:
				mat.set_shader_parameter("albedo_tex", (old as BaseMaterial3D).albedo_texture)
				mat.set_shader_parameter("albedo", (old as BaseMaterial3D).albedo_color)
			mat.set_shader_parameter("band", BAND)
			m.set_surface_override_material(sf, mat)
			out.append(mat)
	return out


## Where the shader puts a point at height `y` over ground `floor_y` (fully pressed).
static func squash_y(y: float, floor_y: float, band := BAND) -> float:
	var top := floor_y + band
	var d := top - y
	if d <= 0.0:
		return y
	return top - band * (1.0 - exp(-d / band))
