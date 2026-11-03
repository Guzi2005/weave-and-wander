shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/pop_up.gdshaderinc"

uniform vec4 pigment : source_color = vec4(.82,.80,.72,1.0);
uniform vec4 ink : source_color = vec4(.26,.35,.40,1.0);
uniform vec2 cloth_size = vec2(3.65,1.0);
uniform float floral = 0.0;
uniform float visibility = 1.0;

float stripe(float p,float width,float aa) {
	return 1.0-smoothstep(width-aa,width+aa,abs(fract(p)-.5));
}
float leaf(vec2 p, vec2 center, float rotation) {
	p -= center;
	p = mat2(vec2(cos(rotation),-sin(rotation)),vec2(sin(rotation),cos(rotation)))*p;
	float shape = length(p/vec2(.095,.20));
	return 1.0-smoothstep(.88,1.03,shape);
}
void vertex() {
	fold_paper(VERTEX,NORMAL,MODEL_MATRIX);
}
void fragment() {
	vec2 physical = UV*cloth_size;
	float repeat = physical.x*7.0;
	float aa = max(fwidth(repeat),.003);
	float pattern = stripe(repeat,.075,aa)*.75;
	pattern = max(pattern,stripe(repeat+.18,.014,aa));
	pattern = max(pattern,stripe(repeat-.18,.014,aa));
	vec2 cell = fract(physical*4.0)-.5;
	if (floral > .5) {
		float stem = (1.0-smoothstep(.008,.022,abs(cell.x-.035*sin(cell.y*8.0))))*step(abs(cell.y),.36);
		pattern = max(stem,max(leaf(cell,vec2(-.085,.13),-.65),leaf(cell,vec2(.09,-.08),.65)));
		pattern = max(pattern,leaf(cell,vec2(0,.30),0.0)*.75);
	}
	vec2 weave = physical*650.0;
	vec2 coverage = 1.0-smoothstep(vec2(.2),vec2(1.0),fwidth(weave));
	float warp = sin(weave.x*6.28318)*coverage.x;
	float weft = sin(weave.y*6.28318)*coverage.y;
	float fibers = (warp+weft)*.025;
	float fleck = fract(sin(dot(floor(UV*vec2(1400.0,520.0)),vec2(127.1,311.7)))*43758.5453)-.5;
	vec3 cloth = mix(pigment.rgb,ink.rgb,pattern*.66)+fibers+fleck*.025;
	ALBEDO = cloth*.80;
	EMISSION = cloth*.07;
	ROUGHNESS = .98;
	NORMAL_MAP = normalize(vec3(-warp*.10,-weft*.10,1.0))*.5+.5;
}
