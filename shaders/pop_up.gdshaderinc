// Presentation only: world-space paths, interaction anchors and skeletons remain intact.
uniform bool fold_enabled = false;
uniform float fold_amount = 1.0;
uniform vec3 fold_origin = vec3(0.0);
uniform bool fold_floor = false;
uniform bool fold_card = false;
uniform bool fold_leaf = false;

void fold_paper(inout vec3 vertex, inout vec3 normal, mat4 model) {
	if (!fold_enabled) return;
	vec3 world = (model * vec4(vertex, 1.0)).xyz;
	vec3 n = normalize(mat3(model) * normal);
	float closed = 1.0 - fold_amount;
	float angle = closed * 1.57079633;
	if (!fold_floor || fold_leaf) {
		vec3 q = world - fold_origin;
		// Depth collapses along the scored folds before the upright folds onto its page.
		float depth = fold_leaf ? 1.0 : mix(0.025, 1.0, fold_amount);
		world.y = fold_origin.y + q.y * cos(angle) - q.z * depth * sin(angle);
		world.z = fold_origin.z + q.y * sin(angle) + q.z * depth * cos(angle);
		n = vec3(n.x, n.y * cos(angle) - n.z * sin(angle), n.y * sin(angle) + n.z * cos(angle));
	}
	// The rear leaf of an outdoor greeting card closes through a full half-turn.
	if (fold_card && world.z < 3.8) {
		float leaf_angle = smoothstep(0.55, 1.0, closed) * 3.14159265;
		vec2 q = world.yz - vec2(0.0, 3.8);
		world.yz = vec2(q.x * cos(leaf_angle) - q.y * sin(leaf_angle), q.x * sin(leaf_angle) + q.y * cos(leaf_angle)) + vec2(0.0, 3.8);
		n = vec3(n.x, n.y * cos(leaf_angle) - n.z * sin(leaf_angle), n.y * sin(leaf_angle) + n.z * cos(leaf_angle));
	}
	world.y -= closed * 0.30;
	vertex = (inverse(model) * vec4(world, 1.0)).xyz;
	normal = normalize(inverse(mat3(model)) * n);
}
