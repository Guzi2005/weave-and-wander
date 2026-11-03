shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 ink_color : source_color = vec4(0.64, 0.79, 0.82, 1.0);
uniform float grain_strength : hint_range(0.0, 0.2) = 0.055;
varying vec2 paper_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	// Local paper coordinates keep the ink attached while a doll moves.
	paper_position = VERTEX.xy;
}

void fragment() {
	float pigment = noise(paper_position * 70.0) - 0.5;
	float tooth = noise(paper_position * 260.0) - 0.5;
	float coverage = 1.0 - noise(paper_position * 8.0) * 0.007;
	// Fade subpixel grain to prevent crawling speckles at gameplay scale.
	float pixel_width = max(length(dFdx(paper_position)), length(dFdy(paper_position)));
	float fine_weight = 1.0 - smoothstep(0.002, 0.009, pixel_width);
	vec3 ink = ink_color.rgb * (coverage + pigment * grain_strength * 0.25);
	ink += vec3(tooth * grain_strength * 1.6 * fine_weight);
	ink = mix(ink, vec3(0.91, 0.88, 0.82), max(tooth - 0.23, 0.0) * 0.16 * fine_weight);
	ALBEDO = clamp(ink, vec3(0.0), vec3(1.0));
}
