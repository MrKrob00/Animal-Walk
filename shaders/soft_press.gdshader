// A character's own look (its texture, unshaded like the model's own material) that gives softly against the ground: lying down,
// skin that would go under the ground (the chest, belly and thighs pressed into it) is squeezed
// up onto it, the more the deeper, and bulges a little sideways - per vertex, so a soft part
// flattens and spreads like flesh. Only while `press` > 0. Also a paw pressing the skin (TOFU's,
// on the second stick): skin is pushed out of the paw's ball the same soft way (the chest dents
// under it, the player's easter egg), so the paw never shows through her. Uniforms are set per material (no
// global uniforms: see CLAUDE.md, traps). Kept in step with SoftPress.squash_y.
shader_type spatial;
render_mode cull_disabled, unshaded;   // as her own material

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float floor_y = -1000.0;   // the ground under the character, world metres
uniform float press = 0.0;         // 0..1: how much it gives (lying down)
uniform float band = 0.05;         // metres above the ground where the giving starts
uniform float bulge = 0.5;         // sideways spread per metre squeezed up
uniform vec4 paw = vec4(0.0);      // a paw: centre (world metres) and radius; w = 0: none
uniform float paw_band = 0.02;     // metres round the paw where the skin starts to give

void vertex() {
	if (press > 0.001 || paw.w > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		bool moved = false;
		float top = floor_y + band;
		float d = top - w.y;
		if (press > 0.001 && d > 0.0) {
			float y2 = top - band * (1.0 - exp(-d / band));
			float up = (y2 - w.y) * press;
			vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
			w.y += up;
			w.xz += n.xz * up * bulge;
			moved = true;
		}
		if (paw.w > 0.0) {
			vec3 off = w - paw.xyz;
			float r = length(off);
			float out_r = paw.w + paw_band;
			if (r < out_r) {
				float r2 = out_r - paw_band * (1.0 - exp(-(out_r - r) / paw_band));
				w = paw.xyz + (r > 1e-5 ? off / r : vec3(0.0, 1.0, 0.0)) * r2;
				moved = true;
			}
		}
		if (moved) {
			VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
		}
	}
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo;
	ALBEDO = c.rgb;
}
