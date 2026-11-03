shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/pop_up.gdshaderinc"

uniform vec4 pigment : source_color = vec4(1.0);
uniform float pattern = 0.0;
uniform float pattern_scale = 12.0;
uniform float visibility = 1.0;
uniform float lamp_glow = 0.0;
uniform float window_glow = 0.0;

float grain(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}

void fragment() {
    float fleck = grain(floor(UV * vec2(380.0, 520.0))) - 0.5;
    vec3 color = pigment.rgb + fleck * 0.022;
    if (pattern > 0.5) {
        vec2 repeat_uv = UV * pattern_scale;
        float stripe = step(0.79, fract(repeat_uv.x));
        if (pattern > 1.5) stripe = max(stripe, step(0.88, fract(repeat_uv.y)));
        color = mix(color, color * 0.62 + vec3(0.26), stripe * 0.35);
    }
    ALBEDO = color * 0.78;
    EMISSION = color * 0.10 + vec3(1.0, 0.63, 0.28) * (lamp_glow * 1.3 + window_glow * .65);
    ROUGHNESS = 1.0;
}
