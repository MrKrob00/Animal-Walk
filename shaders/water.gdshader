// Sea around the island: shallow turquoise to deep blue by depth, a foam line breathing at
// the shore, a gentle swell. Opaque, no discard, no global uniforms (see CLAUDE.md, traps).
// Depth comes in the vertex colour's alpha (0 at the waterline, 1 deep), baked by water.gd.
shader_type spatial;
render_mode specular_schlick_ggx, shadows_disabled;

uniform vec4 shallow : source_color = vec4(0.47, 0.86, 0.80, 1.0);
uniform vec4 deep : source_color = vec4(0.13, 0.47, 0.64, 1.0);
uniform vec4 foam : source_color = vec4(0.98, 0.98, 0.95, 1.0);
uniform float swell = 0.03;

varying float depth;
varying vec3 wpos;

void vertex() {
	depth = COLOR.a;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (sin(TIME * 1.1 + wpos.x * 0.35) + sin(TIME * 0.8 + wpos.z * 0.28)) * swell * (0.3 + depth);
}

void fragment() {
	vec3 c = mix(shallow.rgb, deep.rgb, smoothstep(0.02, 0.9, depth));
	// The foam line rolls in and out a little.
	float edge = depth + 0.008 * sin(TIME * 1.6 + wpos.x * 0.4 + wpos.z * 0.3);
	float band = smoothstep(0.022, 0.004, edge);
	c = mix(c, foam.rgb, band * 0.9);
	ALBEDO = c;
	ROUGHNESS = mix(0.22, 0.6, band);
	SPECULAR = 0.35;
}
