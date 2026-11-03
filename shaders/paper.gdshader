shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/pop_up.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.8, 0.7, 0.6, 1.0);
uniform float grain_strength : hint_range(0.0, 0.18) = 0.03;
uniform float fiber_strength : hint_range(0.0, 0.12) = 0.005;

void vertex() {
	fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}

float paper_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 grain_uv = floor((UV * vec2(420.0, 610.0)) + NODE_POSITION_WORLD.xy * 17.0);
	float grain = paper_hash(grain_uv) - 0.5;
	float fibers = sin((UV.y * 740.0) + sin(UV.x * 41.0) * 2.0) * 0.5;
	vec3 paper_color = base_color.rgb;
	paper_color += grain * grain_strength;
	paper_color += fibers * fiber_strength;
	ALBEDO = clamp(paper_color, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
}
