shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

#include "res://shaders/pop_up.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.87, 0.96, 0.95, 1.0);

void vertex() {
	fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}

// Thin glazing: clear head-on, more reflective at grazing angles.
void fragment() {
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 5.0);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.045;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ALPHA = 0.055 + fresnel * 0.30;
}
