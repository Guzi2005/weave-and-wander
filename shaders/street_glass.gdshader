shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
#include "res://shaders/pop_up.gdshaderinc"
uniform sampler2D reflection_texture : filter_linear;
uniform float reflection_strength = 0.24;
void vertex() { fold_paper(VERTEX, NORMAL, MODEL_MATRIX); }
void fragment() {
    float fresnel = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),4.0);
    vec3 reflected = texture(reflection_texture,vec2(1.0-UV.x,UV.y)).rgb;
    ALBEDO = mix(reflected,vec3(.78,.88,.85),.10);
    ROUGHNESS = .09;
    SPECULAR = .72;
    METALLIC = 0.0;
    ALPHA = reflection_strength+fresnel*.20;
}
