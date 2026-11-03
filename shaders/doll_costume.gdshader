shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/pop_up.gdshaderinc"

// Same ink plates, normal-based tone steps and paper tooth as doll_volume.
// Textile maps and per-bead colours extend that palette; no PBR light response.
uniform vec4 pigment : source_color = vec4(1.0);
uniform sampler2D pigment_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_pigment_map = false;
uniform bool use_vertex_color = false;
uniform float relief_strength = 0.06;
uniform float tooth = 0.075;
uniform float tone_steps = 2.0;
uniform float backface_shade = 0.0;
varying vec3 local_position;
varying vec3 world_normal;

void vertex() {
	local_position = VERTEX;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
	fold_paper(VERTEX, NORMAL, MODEL_MATRIX);
}

void fragment() {
	vec3 ink = pigment.rgb;
	if (use_pigment_map) ink *= texture(pigment_map, UV).rgb;
	if (use_vertex_color) {
		// Geometry stores linear vertex colours. Compatibility renders in sRGB;
		// source_color handles textures/uniforms but does not transform COLOR.
		vec3 vertex_ink = COLOR.rgb;
		if (OUTPUT_IS_SRGB) vertex_ink = mix(vertex_ink * 12.92, 1.055 * pow(max(vertex_ink, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), vertex_ink));
		ink *= vertex_ink;
	}
	float grain = fract(sin(dot(floor(local_position * 220.0), vec3(17.13, 91.17, 43.71))) * 43758.5453);
	float fade = 1.0 - smoothstep(0.35, 1.1, length(fwidth(local_position * 220.0)));
	float light = dot(normalize(world_normal), normalize(vec3(-0.55, 0.8, 0.65)));
	float level = clamp((light + 0.45) / 1.4, 0.0, 1.0);
	float stepped = floor(level * tone_steps) / tone_steps;
	float lining = FRONT_FACING ? 1.0 : 1.0 - backface_shade;
	ALBEDO = ink * (1.0 - relief_strength + relief_strength * level) * lining * (1.0 + (grain - 0.5) * tooth * fade);
}
