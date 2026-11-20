// A character's own look (its texture, unshaded like the model's own material) that gives softly against the ground: lying down,
// skin that would go under the ground (the chest, belly and thighs pressed into it) is squeezed
// up onto it, the more the deeper, and bulges a little sideways - per vertex, so a soft part
// flattens and spreads like flesh. Only while `press` > 0. Uniforms are set per material (no
// global uniforms: see CLAUDE.md, traps). Kept in step with SoftPress.squash_y.
shader_type spatial;
render_mode cull_disabled, unshaded;   // as her own material

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float floor_y = -1000.0;   // the ground under the character, world metres
uniform float press = 0.0;         // 0..1: how much it gives (lying down)
uniform float band = 0.05;         // metres above the ground where the giving starts
uniform float bulge = 0.5;         // sideways spread per metre squeezed up

void vertex() {
	if (press > 0.001) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float top = floor_y + band;
		float d = top - w.y;
		if (d > 0.0) {
			float y2 = top - band * (1.0 - exp(-d / band));
			float up = (y2 - w.y) * press;
			vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
			w.y += up;
			w.xz += n.xz * up * bulge;
			VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
		}
	}
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo;
	ALBEDO = c.rgb;
}
