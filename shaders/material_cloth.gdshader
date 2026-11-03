shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/pop_up.gdshaderinc"

// Repeats are in original local metres, shared by packages, cut pieces and garments.
uniform vec4 pigment : source_color = vec4(0.47, 0.60, 0.69, 1.0);
uniform float pattern = 0.0;
uniform float pattern_scale = 12.0;
uniform float weave_scale = 180.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.94;
uniform float fiber_strength : hint_range(0.0, 0.2) = 0.055;
uniform vec3 physical_scale = vec3(1.0);
uniform bool use_material_uv = false;
uniform vec2 uv_metres = vec2(1.0);
varying vec3 cloth_position;
varying vec3 cloth_normal;

float stripe(float coordinate) {
	float width = max(fwidth(coordinate), 0.005);
	float distance = abs(fract(coordinate) - 0.5);
	return 1.0 - smoothstep(0.16 - width, 0.16 + width, distance);
}

void vertex() {
	cloth_position = VERTEX * physical_scale;
	cloth_normal = NORMAL;
	fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}

void fragment() {
	vec3 normal_weight = pow(abs(normalize(cloth_normal)), vec3(6.0));
	normal_weight /= max(dot(normal_weight, vec3(1.0)), 0.0001);
	vec3 p = cloth_position * pattern_scale;
	vec3 lines = vec3(stripe(p.x), stripe(p.y), stripe(p.z));
	float stripe_pattern = dot(normal_weight, vec3(lines.y, lines.x, lines.y));
	float check_pattern = dot(normal_weight, vec3(lines.y + lines.z, lines.x + lines.z, lines.x + lines.y)) * 0.5;
	float print_coverage = pattern > 1.5 ? check_pattern : stripe_pattern;
	if (use_material_uv) {
		vec2 garment_uv = UV * uv_metres * pattern_scale;
		print_coverage = pattern > 1.5 ? (stripe(garment_uv.x) + stripe(garment_uv.y)) * 0.5 : stripe(garment_uv.x);
	}
	vec3 color = pigment.rgb;
	if (pattern > 0.5) color = mix(color, color * 0.48 + vec3(0.42), print_coverage * 0.72);
	vec3 w = cloth_position * weave_scale;
	float weave = (sin(w.x * 6.283185) + sin(w.y * 6.283185) + sin(w.z * 6.283185)) / 3.0;
	float fade = 1.0 - smoothstep(0.3, 1.0, length(fwidth(w)));
	color *= 1.0 + weave * fiber_strength * fade;
	ALBEDO = color * 0.78;
	EMISSION = color * 0.10;
	ROUGHNESS = roughness;
}
