// Paper look: vertex colour times a paper-grain texture. One texture read,
// no discard, no global uniforms (see CLAUDE.md, traps).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform sampler2D grain : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float grain_strength = 0.12;
uniform float grain_scale = 0.55;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Project the grain along the dominant axis of the face: one sample only.
	vec2 uv = abs(wnrm.y) > 0.6 ? wpos.xz : (abs(wnrm.x) > abs(wnrm.z) ? wpos.zy : wpos.xy);
	float g = texture(grain, uv * grain_scale).r;
	ALBEDO = COLOR.rgb * (1.0 + grain_strength * (g - 0.5) * 2.0);
	ROUGHNESS = 1.0;
}
