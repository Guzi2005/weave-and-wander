shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/pop_up.gdshaderinc"
uniform vec4 pigment : source_color = vec4(0.3, 0.25, 0.25, 1.0);
void vertex() {
	fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}
void fragment() {
	ALBEDO = pigment.rgb * 0.68;
}
