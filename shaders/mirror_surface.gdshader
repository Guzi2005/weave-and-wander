shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/pop_up.gdshaderinc"

uniform sampler2D mirror_texture : filter_linear;

void vertex() {
    fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}

void fragment() {
    // A real reflection is supplied by the shared-world viewport.  The slight
    // blue-green cast and vertical sheen keep it reading as glass, not a flat
    // screenshot pasted onto the furniture.
    vec2 reflected_uv = vec2(1.0 - UV.x, UV.y);
    vec2 q = abs((UV - .5) * vec2(.8, 2.5)) - vec2(.19, 1.04);
    if (length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) > .21) discard;
    vec2 texel = 1.0 / vec2(textureSize(mirror_texture, 0));
    vec3 reflection = texture(mirror_texture, reflected_uv).rgb * .60;
    reflection += texture(mirror_texture, reflected_uv + texel * vec2(1.4, 0)).rgb * .10;
    reflection += texture(mirror_texture, reflected_uv - texel * vec2(1.4, 0)).rgb * .10;
    reflection += texture(mirror_texture, reflected_uv + texel * vec2(0, 1.4)).rgb * .10;
    reflection += texture(mirror_texture, reflected_uv - texel * vec2(0, 1.4)).rgb * .10;
    float sheen = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 4.0) * .06;
    ALBEDO = mix(reflection, vec3(.75, .83, .81), .06) + vec3(sheen);
    ROUGHNESS = .12;
    SPECULAR = .92;
}
