shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/pop_up.gdshaderinc"
uniform vec4 pigment : source_color;
uniform vec4 sock_color : source_color;
uniform vec4 pattern_color : source_color;
uniform float sock_top = -1.0;
uniform float covered_above = 100.0;
uniform bool surface_only = false;
uniform int pattern = 0;
uniform float repeats = 20.0;
uniform bool use_texture = false;
uniform sampler2D knit_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform vec2 texture_scale = vec2(1.0, 4.0);
varying vec3 world_normal;
void vertex() {
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
	fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}
void fragment() {
	if (UV2.y > covered_above) discard;
	if (surface_only && UV2.y > sock_top) discard;
	vec3 ink = pigment.rgb;
	if (UV2.y <= sock_top) {
		float motif = 0.0;
		if (pattern == 1) motif = .16 * pow(.5+.5*cos(UV2.x*repeats*6.283185), 8.0);
		if (pattern == 2) motif = step(.5, fract(UV2.y*repeats));
		if (pattern == 3) motif = 1.0-smoothstep(.17,.22,length(fract(UV2*vec2(repeats,repeats))-.5));
		ink = mix(sock_color.rgb,pattern_color.rgb,motif);
		if (use_texture) ink *= texture(knit_texture,UV2*texture_scale).rgb;
	}
	float light = dot(normalize(world_normal),normalize(vec3(-.55,.8,.65)));
	float level = clamp((light+.45)/1.4,0.0,1.0);
	ALBEDO = ink*(.94+.06*floor(level*2.0)/2.0);
}
