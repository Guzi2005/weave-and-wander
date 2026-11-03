shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_map : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float normal_strength = 0.22;
uniform float roughness = 0.7;
uniform float metalness = 0.0;
uniform float texture_softening = 1.8;
uniform float lamp_glow = 0.0;
uniform bool foliage_mode = false;
uniform bool painted_leaf = false;
uniform bool wood_mode = false;
uniform bool cutting_mat_grid = false;
uniform bool ruler_ticks = false;
uniform float highlight_strength = 0.04;

// Procedural replacements for the former 148 CuttingGrid + 60 RulerTick boxes
// (scheme A). Positions are object-local Godot units (1 unit = 2 cm), matching
// tools/build_workbench.py, so the ruling is exact and independent of UV export.
const vec3 MAT_INK_LINEAR = vec3(0.305, 0.479, 0.392);   // #96b8a8
const vec3 RULER_INK_LINEAR = vec3(0.0185, 0.0284, 0.0296); // #252f30
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
}

float line_mask(float coord, float spacing, float half_width) {
    float dist = abs(fract(coord / spacing + 0.5) - 0.5) * spacing;
    float aa = max(fwidth(coord), 1e-5);
    return 1.0 - smoothstep(half_width - aa, half_width + aa, dist);
}

float cutting_mat_mask(vec3 p) {
    // 1 cm (0.5 u) minor and 5 cm (2.5 u) major ruling inside the 88 x 58 cm printed area.
    float in_x = step(abs(p.x), 22.0 + 0.01);
    float in_z = step(abs(p.z), 14.5 + 0.01);
    float minor = max(line_mask(p.x, 0.5, 0.0045), line_mask(p.z, 0.5, 0.0045));
    float major = max(line_mask(p.x, 2.5, 0.010), line_mask(p.z, 2.5, 0.010));
    return clamp(max(minor * 0.78, major), 0.0, 1.0) * in_x * in_z;
}

float ruler_mask(vec3 p) {
    // 60 ticks every 0.25 u from x = -7.4; every 4th tick is long.
    float rx = p.x + 7.4;
    float in_x = step(-0.01, rx) * step(rx, 14.76);
    float k = floor(rx / 0.25 + 0.5);
    float is_major = 1.0 - step(0.5, mod(k, 4.0));
    float z_lo = mix(-0.4, -0.5, is_major);
    float z_hi = mix(-0.2, -0.1, is_major);
    float aa_z = max(fwidth(p.z), 1e-5);
    float in_z = smoothstep(z_lo - aa_z, z_lo + aa_z, p.z) * (1.0 - smoothstep(z_hi - aa_z, z_hi + aa_z, p.z));
    return line_mask(rx, 0.25, 0.006) * in_x * in_z;
}

void fragment() {
    vec4 tex = texture(albedo_map, UV, texture_softening) * base_color;
    // Keep the authored palette and grain, but group tonal detail into broad values.
    float value = max(dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.001);
    if (foliage_mode) {
        // Treat foliage as painted masses: a few broad inked greens, with the
        // scanned leaf shape retained only for silhouette and alpha.
        float band = floor(clamp(value, .12, .82) * 4.0 + .5) / 4.0;
        vec3 shadow = vec3(.075, .145, .095);
        vec3 mid = vec3(.19, .32, .16);
        vec3 light = vec3(.38, .49, .22);
        vec3 leaf = mix(shadow, mid, smoothstep(.18, .46, band));
        leaf = mix(leaf, light, smoothstep(.52, .82, band));
        ALBEDO = painted_leaf ? base_color.rgb : leaf;
    } else if (wood_mode) {
        ALBEDO = mix(tex.rgb, vec3(value), .16);
    } else {
        float grouped = floor(value * 9.0 + 0.5) / 9.0;
        ALBEDO = clamp(tex.rgb * mix(1.0, max(grouped, 0.025) / value, 0.32), vec3(0.0), vec3(1.0));
    }
    if (cutting_mat_grid && local_normal.y > 0.75) {
        ALBEDO = mix(ALBEDO, MAT_INK_LINEAR, cutting_mat_mask(local_pos));
    }
    if (ruler_ticks && local_normal.y > 0.75) {
        ALBEDO = mix(ALBEDO, RULER_INK_LINEAR, ruler_mask(local_pos));
    }
    ALPHA = tex.a;
    ALPHA_SCISSOR_THRESHOLD = 0.45;
    ROUGHNESS = roughness;
    METALLIC = metalness * 0.65;
    SPECULAR = 0.25 + metalness * 0.3;
    EMISSION = vec3(1.0, 0.66, 0.30) * lamp_glow;
    if (has_normal) {
        NORMAL_MAP = texture(normal_map, UV, 0.8).rgb;
        NORMAL_MAP_DEPTH = normal_strength;
    }
}

void light() {
    float facing = max(dot(NORMAL, LIGHT), 0.0);
    float bands = 0.19 + 0.36 * smoothstep(0.17, 0.23, facing)
                       + 0.45 * smoothstep(0.58, 0.65, facing);
    if (foliage_mode) {
        bands = .48 + .52 * smoothstep(.20, .55, facing);
    }
    // Actual light attenuation/shadows remain; night and cast shadows are not painted in.
    DIFFUSE_LIGHT += bands * ATTENUATION * LIGHT_COLOR / PI;
    vec3 half_vector = normalize(LIGHT + VIEW);
    float highlight = pow(max(dot(NORMAL, half_vector), 0.0), mix(70.0, 12.0, ROUGHNESS));
    SPECULAR_LIGHT += smoothstep(0.28, 0.42, highlight) * ATTENUATION * LIGHT_COLOR * (highlight_strength + METALLIC * 0.22);
}
