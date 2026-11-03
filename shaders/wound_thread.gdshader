shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/pop_up.gdshaderinc"

uniform vec4 pigment : source_color = vec4(1.0);
uniform float visibility = 1.0;

void vertex() {
	// Thread-sized ridges should not read as deep black grooves at shop scale.
	vec3 cylinder_normal = normalize(vec3(VERTEX.x,0.0,VERTEX.z));
	NORMAL = normalize(mix(cylinder_normal,NORMAL,.20));
	fold_paper(VERTEX,NORMAL,MODEL_MATRIX);
}
void fragment() {
	ALBEDO = pigment.rgb*.78;
	EMISSION = pigment.rgb*.10;
	ROUGHNESS = 1.0;
}
