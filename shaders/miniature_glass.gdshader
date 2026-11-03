shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

#include "res://shaders/pop_up.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.78, 0.90, 0.88, 1.0);

void vertex() {
    fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}

void fragment() {
    float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 5.0);
    ALBEDO = tint.rgb;
    ROUGHNESS = 0.12;
    SPECULAR = 0.78;
    METALLIC = 0.0;
    ALPHA = 0.035 + fresnel * 0.17;
}
