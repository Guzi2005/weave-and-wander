shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float print_mix : hint_range(0.0, 1.0) = 0.08;
uniform float grain_amount : hint_range(0.0, 0.08) = 0.009;
uniform float paper_warmth : hint_range(0.0, 0.08) = 0.012;

float hash(vec2 p) {
	p = fract(p * vec2(443.8975, 397.2973));
	p += dot(p, p.yx + 19.19);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 source = texture(screen_texture, SCREEN_UV);
	vec3 stepped = floor(source.rgb * 22.0 + 0.5) / 22.0;
	float grain = hash(floor(FRAGCOORD.xy * 0.72)) - 0.5;
	vec3 color = mix(source.rgb, stepped, print_mix);
	color += vec3(grain * grain_amount);
	color *= vec3(1.0 + paper_warmth, 1.0, 1.0 - paper_warmth);
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), source.a);
}
