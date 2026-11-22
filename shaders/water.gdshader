// Sea around the island: shallow turquoise to deep blue by depth, a foam line breathing at
// the shore, a gentle swell. Opaque, no discard, no global uniforms (see CLAUDE.md, traps).
// The signed depth in metres comes in UV.x (negative under the land), baked by water.gd.
shader_type spatial;
render_mode specular_schlick_ggx, shadows_disabled;

uniform vec4 shallow : source_color = vec4(0.47, 0.86, 0.80, 1.0);
uniform vec4 deep : source_color = vec4(0.13, 0.47, 0.64, 1.0);
uniform vec4 foam : source_color = vec4(0.98, 0.98, 0.95, 1.0);
uniform float swell = 0.03;
uniform float depth_full = 2.4;   // metres that count as deep

varying float depth_m;
varying vec3 wpos;

void vertex() {
	depth_m = UV.x;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (sin(TIME * 1.1 + wpos.x * 0.35) + sin(TIME * 0.8 + wpos.z * 0.28)) * swell * clamp(depth_m / depth_full + 0.3, 0.0, 1.3) * UV.y;   // UV.y: 0 on the edges that meet the still frame
}

void fragment() {
	vec3 c = mix(shallow.rgb, deep.rgb, smoothstep(0.0, 0.9, depth_m / depth_full));
	// A thin foam line at the waterline, rolling in and out a little.
	float edge = depth_m + 0.012 * sin(TIME * 1.6 + wpos.x * 0.4 + wpos.z * 0.3);
	float band = smoothstep(0.026, 0.004, edge) * smoothstep(-0.03, 0.0, edge);   // none over the sand
	c = mix(c, foam.rgb, band * 0.9);
	ALBEDO = c;
	ROUGHNESS = mix(0.22, 0.6, band);
	SPECULAR = 0.35;
}
