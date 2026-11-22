// Plants in the wind (the player: grass, trees, leaves, wind for a pretty picture): the paper look
// (vertex colour, or a texture for KayKit's trees, times the paper grain) and a sway that grows
// with height above the plant's foot, in waves that roll across the island (gusts), with a small
// flutter on top. Grass also sinks into the ground with distance from the camera, so it fades out
// without popping and without transparency. No discard, no global uniforms (CLAUDE.md, traps).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, cull_disabled;

uniform sampler2D grain : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float grain_strength = 0.12;
uniform float grain_scale = 0.55;
uniform bool use_texture = false;           // KayKit's trees: their atlas instead of vertex colours
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 wind_dir = vec2(0.8, 0.6);     // the way the wind blows (x, z)
uniform float wind_strength = 0.12;         // metres of sway at sway_height
uniform float sway_height = 1.0;            // model metres up where the sway is whole
uniform float gust_scale = 0.045;           // waves across the island per metre
uniform float flutter = 0.02;               // small fast shiver at the tips
uniform float fade_near = 0.0;              // grass: sinks into the ground between these distances
uniform float fade_far = 0.0;               // (0, 0: never)
uniform float tip_light = 0.0;              // grass: tips this much lighter than the roots

varying vec3 wpos;
varying vec3 wnrm;
varying float tip;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;   // the plant's foot (a MultiMesh instance's origin)
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.5);
	tip = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	vec2 d = normalize(wind_dir);
	float wave = dot(root.xz, d) * gust_scale;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + wave * 0.5);   // stronger and weaker by turns
	float s = sin(TIME * 1.7 - wave * 6.2831) * 0.5 + 0.5;
	float f = sin(TIME * 7.0 + root.x * 3.1 + root.z * 2.3 + VERTEX.x * 9.0) * flutter;
	vec2 off = d * (s * wind_strength * gust) * h * h + vec2(-d.y, d.x) * f * h;
	if (fade_far > 0.0) {
		float dist = length(root - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
		VERTEX.y *= 1.0 - smoothstep(fade_near, fade_far, dist);
	}
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += inv * vec3(off.x, -length(off) * 0.25 * h, off.y);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = abs(wnrm.y) > 0.6 ? wpos.xz : (abs(wnrm.x) > abs(wnrm.z) ? wpos.zy : wpos.xy);
	float g = texture(grain, uv * grain_scale).r;
	vec3 c = use_texture ? texture(albedo_tex, UV).rgb : COLOR.rgb;
	c *= 1.0 + tip_light * (tip - 0.5);
	ALBEDO = c * (1.0 + grain_strength * (g - 0.5) * 2.0);
	ROUGHNESS = 1.0;
}
