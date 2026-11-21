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
uniform vec3 floor_p = vec3(0.0, -1000.0, 0.0);   // the ground under the character: a point on it (world metres)
uniform vec3 floor_n = vec3(0.0, 1.0, 0.0);       // ... and its normal: tilted with the slope (level, she sank into the sand uphill)
uniform float press = 0.0;         // 0..1: how much it gives (lying down)
uniform float band = 0.05;         // metres above the ground where the giving starts
uniform float bulge = 0.5;         // sideways spread per metre squeezed up
uniform vec3 flesh_l = vec3(0.0); // her soft flesh (SoftFlesh): how far each region is moved now, world metres;
uniform vec3 flesh_r = vec3(0.0); // each vertex follows its shares of them (CUSTOM0 r, g, b)
uniform vec3 flesh_b = vec3(0.0);
uniform float flesh_on = 0.0;
uniform vec4 paw = vec4(0.0);      // a paw: centre (world metres) and radius; w = 0: none
uniform float paw_band = 0.02;     // metres round the paw where the skin starts to give

void vertex() {
	if (press > 0.001 || paw.w > 0.0 || flesh_on > 0.5) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		bool moved = false;
		if (flesh_on > 0.5) {
			vec3 f = CUSTOM0.r * flesh_l + CUSTOM0.g * flesh_r + CUSTOM0.b * flesh_b;
			if (dot(f, f) > 0.0) {
				w += f;   // first: the flesh moves, then the ground and a paw push it back out
				moved = true;
			}
		}
		float s = dot(w - floor_p, floor_n);   // height over the ground plane
		float d = band - s;
		if (press > 0.001 && d > 0.0) {
			float s2 = band - band * (1.0 - exp(-d / band));
			float up = (s2 - s) * press;
			vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
			vec3 side = n - floor_n * dot(n, floor_n);   // spread along the ground
			w += floor_n * up + side * up * bulge;
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
