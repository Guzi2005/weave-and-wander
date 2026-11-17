shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/pop_up.gdshaderinc"
#include "res://shaders/cloth_contact.gdshaderinc"

uniform vec4 pigment : source_color = vec4(0.7, 0.5, 0.4, 1.0);
uniform float tooth = 0.075;
uniform float tone_steps = 2.0;
uniform float backface_shade = 0.0;
varying vec3 local_position;
varying vec3 world_normal;

void vertex() {
	contact_cloth(VERTEX, NORMAL, BONE_INDICES, BONE_WEIGHTS, UV2);
	local_position = VERTEX;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
	fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}

void fragment() {
	float grain = fract(sin(dot(floor(local_position * 220.0), vec3(17.13, 91.17, 43.71))) * 43758.5453);
	float fade = 1.0 - smoothstep(0.35, 1.1, length(fwidth(local_position * 220.0)));
	float light = dot(normalize(world_normal), normalize(vec3(-0.55, 0.8, 0.65)));
	float level = clamp((light + 0.45) / 1.4, 0.0, 1.0);
	float stepped = floor(level * tone_steps) / tone_steps;
	// The whole doll uses flat ink plates; room lighting is a separate shader.
	float painted_light = 0.94 + 0.06 * stepped;
	float lining = FRONT_FACING ? 1.0 : 1.0 - backface_shade;
	ALBEDO = pigment.rgb * painted_light * lining * (1.0 + (grain - 0.5) * tooth * fade);
}
