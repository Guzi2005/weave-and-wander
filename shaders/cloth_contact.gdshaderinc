// Post-skin collision envelopes. These move cloth, never erase or resize skin.
uniform bool cloth_contact_enabled = false;
uniform bool cloth_contact_arms = true;
uniform mat4 cloth_to_rest[14];
uniform mat4 cloth_to_pose[14];
uniform vec4 cloth_contact_a[14];
uniform vec4 cloth_contact_b[14];
uniform vec4 cloth_contact_settings[14];
uniform float cloth_layer_clearance = 0.012;
uniform float cloth_surface_lift = 0.0;
uniform bool cloth_outer_layer = false;
uniform float cloth_layer_depth = 1.0;
uniform bool cloth_skirt_side = false;
uniform vec4 cloth_arm_bones;
uniform vec4 cloth_surface_centers[12];
uniform vec4 cloth_surface_across[12];
uniform vec4 cloth_surface_depth[12];
uniform float cloth_fabric_gap = 0.018;
uniform float cloth_sleeve_gap = 0.050;
uniform float cloth_collision_margin = 0.008;
uniform vec3 cloth_side_axis = vec3(1.0, 0.0, 0.0);
uniform bool cloth_secondary_enabled = false;
uniform vec4 cloth_motion_states[9];
uniform float cloth_motion_amount = 0.0;
uniform float cloth_motion_stretch = 0.85;

vec3 cloth_secondary_point(vec3 point, float s) {
	if (s <= 0.0 || cloth_motion_amount <= 0.0) return point;
	float u = clamp(s, 0.0, 1.0) * 8.0;
	int row = min(7, int(floor(u)));
	vec4 state = mix(cloth_motion_states[row], cloth_motion_states[row + 1], u - float(row)) * cloth_motion_amount;
	vec3 p = (cloth_to_rest[0] * vec4(point, 1.0)).xyz;
	float radius = length(p.xz);
	float c = cos(state.x);
	float sn = sin(state.x);
	vec3 result = vec3(p.x * c + p.z * sn, p.y, -p.x * sn + p.z * c);
	result.xz = result.xz * (1.0 + state.y / max(radius, 0.001)) + state.zw;
	float drop = max(0.001, 1.11 * s);
	float radial_run = max(0.0, radius - 0.25);
	float remaining = sqrt(max(0.0, drop * drop + radial_run * radial_run - pow(radial_run + state.y, 2.0)));
	result.y += (drop - remaining) * mix(0.55, 1.0, clamp(cloth_motion_stretch, 0.0, 1.0));
	return (cloth_to_pose[0] * vec4(result, 1.0)).xyz;
}

void cloth_secondary(inout vec3 point, inout vec3 normal, vec2 binding) {
	if (!cloth_secondary_enabled || binding.y < 0.5 || cloth_motion_amount <= 0.0) return;
	vec3 n = normalize(normal);
	vec3 axis = abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(axis, n));
	vec3 bitangent = cross(n, tangent);
	float ds_t = -(mat3(cloth_to_rest[0]) * tangent).y * 0.001 / 1.11;
	float ds_b = -(mat3(cloth_to_rest[0]) * bitangent).y * 0.001 / 1.11;
	vec3 moved = cloth_secondary_point(point, binding.x);
	vec3 t = cloth_secondary_point(point + tangent * 0.001, clamp(binding.x + ds_t, 0.0, 1.0)) - moved;
	vec3 b = cloth_secondary_point(point + bitangent * 0.001, clamp(binding.x + ds_b, 0.0, 1.0)) - moved;
	vec3 candidate = cross(t, b);
	if (dot(candidate, candidate) > 0.000000000001) normal = normalize(candidate);
	point = moved;
}

vec3 contact_fabric(vec3 point, float gap) {
	for (int i = 0; i < 11; i++) {
		if (cloth_surface_centers[i].w == 0.0 || cloth_surface_centers[i].w != cloth_surface_centers[i + 1].w) continue;
		vec3 a = cloth_surface_centers[i].xyz;
		vec3 b = cloth_surface_centers[i + 1].xyz;
		vec3 axis = b - a;
		float t = dot(point - a, axis) / max(dot(axis, axis), 0.000001);
		if (t < 0.0 || t > 1.0) continue;
		vec3 center = mix(a, b, t);
		vec3 u = mix(cloth_surface_across[i].xyz, cloth_surface_across[i + 1].xyz, t);
		vec3 v = mix(cloth_surface_depth[i].xyz, cloth_surface_depth[i + 1].xyz, t);
		vec3 n = normalize(cross(u, v));
		mat3 frame = mat3(u, n, v);
		if (abs(determinant(frame)) < 0.000001) continue;
		vec3 local = inverse(frame) * (point - center);
		float radius = length(local.xz);
		if (radius < 0.00001) continue;
		vec3 surface = (u * local.x + v * local.z) / radius;
		float required = 1.0 + gap / max(length(surface), 0.001);
		if (radius < required) point = center + surface * required + n * local.y;
	}
	return point;
}

void contact_cloth(inout vec3 point, inout vec3 normal, uvec4 ids, vec4 weights, vec2 binding) {
	if (!cloth_contact_enabled) return;
	cloth_secondary(point, normal, binding);
	float sleeve = 0.0;
	float forearm = 0.0;
	for (int j = 0; j < 4; j++) {
		if (float(ids[j]) == cloth_arm_bones.x || float(ids[j]) == cloth_arm_bones.y || float(ids[j]) == cloth_arm_bones.z || float(ids[j]) == cloth_arm_bones.w) sleeve += weights[j];
		if (float(ids[j]) == cloth_arm_bones.y || float(ids[j]) == cloth_arm_bones.w) forearm += weights[j];
	}
	for (int pass_index = 0; pass_index < 2; pass_index++) {
		for (int i = 0; i < 14; i++) {
			bool arm = (i >= 2 && i <= 4) || (i >= 7 && i <= 9) || i >= 12;
			if (arm && (!cloth_contact_arms || sleeve <= 0.2)) continue;
			vec3 local_point = (cloth_to_rest[i] * vec4(point, 1.0)).xyz;
			float z_scale = cloth_contact_settings[i].x;
			local_point.z /= z_scale;
			vec3 a = cloth_contact_a[i].xyz;
			vec3 b = cloth_contact_b[i].xyz;
			a.z /= z_scale;
			b.z /= z_scale;
			vec3 span = b - a;
			float t = clamp(dot(local_point - a, span) / max(dot(span, span), 0.000001), 0.0, 1.0);
			vec3 center = mix(a, b, t);
			vec3 radial = local_point - center;
			float radius = mix(cloth_contact_a[i].w, cloth_contact_b[i].w, t) + cloth_layer_clearance;
			float distance_to_axis = length(radial);
			if (distance_to_axis < radius) {
				if (!arm && cloth_skirt_side) {
					vec3 ray = normalize((mat3(cloth_to_rest[i]) * normal) / vec3(1.0, 1.0, z_scale));
					float d = dot(radial, ray);
					local_point += ray * (-d + sqrt(max(0.0, d * d + radius * radius - dot(radial, radial))));
				} else {
					vec3 exit_normal = distance_to_axis > 0.00001 ? radial / distance_to_axis : vec3(0.0, 0.0, 1.0);
					local_point = center + exit_normal * radius;
				}
				local_point.z *= z_scale;
				point = (cloth_to_pose[i] * vec4(local_point, 1.0)).xyz;
			}
		}
	}
	if (cloth_skirt_side) {
		for (int i = 2; i < 14; i++) {
			if (!((i >= 2 && i <= 4) || (i >= 7 && i <= 9) || i >= 12)) continue;
			vec3 a = cloth_contact_a[i].xyz;
			vec3 b = cloth_contact_b[i].xyz;
			vec3 span = b - a;
			float t = clamp(dot(point - a, span) / max(dot(span, span), 0.000001), 0.0, 1.0);
			vec3 radial = point - mix(a, b, t);
			float radius = mix(cloth_contact_a[i].w, cloth_contact_b[i].w, t) + cloth_collision_margin;
			if (dot(radial, radial) >= radius * radius) continue;
			vec3 direction = cloth_side_axis * ((i <= 4 || i == 12) ? 1.0 : -1.0);
			float d = dot(radial, direction);
			float distance = -d + sqrt(max(0.0, d * d + radius * radius - dot(radial, radial)));
			point += direction * min(distance, 0.14);
		}
		// Body contact remains the hard constraint after side compression.
		for (int pass_index = 0; pass_index < 2; pass_index++) {
		for (int i = 0; i < 12; i++) {
			if ((i >= 2 && i <= 4) || (i >= 7 && i <= 9)) continue;
			vec3 p = (cloth_to_rest[i] * vec4(point, 1.0)).xyz;
			float zs = cloth_contact_settings[i].x;
			p.z /= zs;
			vec3 a = cloth_contact_a[i].xyz / vec3(1.0, 1.0, zs);
			vec3 b = cloth_contact_b[i].xyz / vec3(1.0, 1.0, zs);
			vec3 span = b - a;
			float t = clamp(dot(p - a, span) / max(dot(span, span), 0.000001), 0.0, 1.0);
			vec3 center = mix(a, b, t);
			vec3 radial = p - center;
			float radius = mix(cloth_contact_a[i].w, cloth_contact_b[i].w, t) + cloth_layer_clearance;
			if (length(radial) < radius) {
				vec3 ray = normalize((mat3(cloth_to_rest[i]) * normal) / vec3(1.0, 1.0, zs));
				float d = dot(radial, ray);
				p += ray * (-d + sqrt(max(0.0, d * d + radius * radius - dot(radial, radial))));
				p.z *= zs;
				point = (cloth_to_pose[i] * vec4(p, 1.0)).xyz;
			}
		}
		}
	}
	point += normal * cloth_surface_lift;
	// Sewn shoulder roots stay pinned; free sleeve fabric yields at the elbow/cuff.
	float contact_weight = cloth_outer_layer ? 1.0 : (cloth_contact_arms ? smoothstep(0.35, 0.85, sleeve) * smoothstep(0.04, 0.35, forearm) : 0.0);
	if (contact_weight > 0.0) point = mix(point, contact_fabric(point, (cloth_contact_arms && sleeve > 0.2) ? cloth_sleeve_gap : cloth_fabric_gap * max(1.0, cloth_layer_depth)), contact_weight);
}
