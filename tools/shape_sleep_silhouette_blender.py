"""Artist-directed nap silhouette study, not a simulation or runtime preset.

Keep the native skirt's open hem; use the selected A silhouette as two smooth
envelope guides. The accepted body, pose and standing garment are read-only.
"""

import hashlib
import json
from pathlib import Path
import runpy

import bpy
from mathutils import Matrix, Vector, geometry

ROOT = Path(__file__).resolve().parents[1]
SIM = runpy.run_path(str(Path(__file__).with_name('simulate_wearing_blender.py')))
PATHS = SIM['PROOF_PATHS']
AUDIT = runpy.run_path(str(Path(__file__).with_name('audit_native_layers_blender.py')))


def _smooth(value):
    value = max(0., min(1., value))
    return value * value * (3. - 2. * value)


def _hull(points, axis):
    projected = [Vector((p[0], p[axis])) for p in points]
    return [projected[i] for i in geometry.convex_hull_2d(projected)]


def _envelope(hull, x):
    x = max(min(p.x for p in hull) + 1e-6, min(max(p.x for p in hull) - 1e-6, x))
    values = [a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
              for a, b in zip(hull, hull[1:] + hull[:1])
              if min(a.x, b.x) <= x <= max(a.x, b.x) and abs(b.x - a.x) > 1e-8]
    if len(values) < 2:
        raise ValueError('Cannot sample silhouette envelope')
    return min(values), max(values)


def build(proof_reference, original_reference, tag='silhouette_guidance', back_strength=.65, seat_strength=.85):
    if not 0 <= back_strength <= 1 or not 0 <= seat_strength <= 1:
        raise ValueError('Silhouette strengths must be in [0, 1]')
    proof_path = PATHS['checked_input'](ROOT, proof_reference)
    original_path = PATHS['checked_input'](ROOT, original_reference)
    proof = json.loads(proof_path.read_text())
    original = json.loads(original_path.read_text())
    source_path = PATHS['checked_input'](ROOT, proof['source'], proof['source_sha256'])
    support_path = PATHS['checked_input'](ROOT, proof['support_source'], proof['support_sha256'])
    reference_path = PATHS['checked_input'](ROOT, 'Docs/reference-body/sleep-silhouette-guidance-20261110.png')
    source = json.loads(source_path.read_text())
    support = json.loads(support_path.read_text())
    for ref, sha in source['source_sha256'].items():
        PATHS['checked_input'](ROOT, ref, sha)
    for ref, sha in original['input_sha256'].items():
        PATHS['checked_input'](ROOT, ref, sha)
    if source['style'] != 0 or source['nap_variant'] != 0:
        raise ValueError('This authored study only supports style0/nap0')
    rest = source['base_skirt']['vertices']
    base = proof['posed_vertices']
    if len(rest) != len(base):
        raise ValueError('Source topology changed')
    a_points = original['parts'][0]['vertices']
    a_top, a_side = _hull(a_points, 2), _hull(a_points, 1)
    b_top, b_side = _hull(base, 2), _hull(base, 1)
    lower = source['waist_attachment']['lower_y']
    final = []
    for p, rp in zip(base, rest):
        q = Vector(p)
        free = _smooth((lower - rp[1]) / .16)
        blo, bhi = _envelope(b_top, p[0])
        alo, _ = _envelope(a_top, p[0])
        back_weight = 1. - _smooth((p[2] - blo) / max(bhi - blo, .05))
        q.z += max(0., alo - blo) * back_weight * free * back_strength
        blo, bhi = _envelope(b_side, p[0])
        alo, _ = _envelope(a_side, p[0])
        seat_weight = 1. - _smooth((p[1] - blo) / max(bhi - blo, .05))
        # The front of the hem and its open volume are not a seat-contact patch.
        hem_fade = _smooth((rp[1] - .24) / .30)
        q.y += max(0., alo - blo) * seat_weight * free * hem_fade * seat_strength
        final.append(list(q))
    points, faces, mapping = SIM['_render_surface'](source, final)
    neighbors = [set() for _ in points]
    normals = [Vector() for _ in points]
    for a, b, c in faces:
        normal = (points[b] - points[a]).cross(points[c] - points[a])
        for v in (a, b, c):
            normals[v] += normal
            neighbors[v].update(j for j in (a, b, c) if j != v)
    normals = [n.normalized() for n in normals]
    for _ in range(8):
        normals = [(n * .5 + sum((normals[j] for j in neighbors[i]), Vector()) * (.5 / len(neighbors[i]))).normalized()
                   if neighbors[i] else n for i, n in enumerate(normals)]
    render_normals = [SIM['_godot'](normals[i]) for i in mapping]
    inverses = source['frames'][-1]['cloth_inverse_skin_transforms']
    unskinned = [list(Matrix(t['basis_rows']) @ Vector(p) + Vector(t['origin'])) for p, t in zip(final, inverses)]
    unskinned_normals = [list((Matrix(t['basis_rows']) @ Vector(n)).normalized()) for n, t in zip(render_normals, inverses)]
    parts = [{'name': 'LongSkirt', 'role': 'cloth', 'vertices': final, 'indices': source['base_skirt']['indices']}]
    parts += [{'name': b['semantic'], 'role': 'body', 'vertices': f['vertices'], 'indices': b['indices']}
              for b, f in zip(source['body_parts'], source['frames'][-1]['body_parts'])]
    parts.append({'name': 'cushion', 'role': 'support', 'vertices': support['vertices'], 'indices': support['indices']})
    records, _ = AUDIT['_part_records'](parts)
    output = PATHS['checked_output'](ROOT, source_path, tag)
    report = {k: proof[k] for k in ('source', 'source_sha256', 'support_source', 'support_sha256', 'frame')}
    report.update({'experimental_not_accepted': True, 'snapshot_only': True, 'transition_validated': False,
                   'method': 'Artist-directed envelope deformation of verified native nap snapshot; NOT a new physics result',
                   'parent_proof': PATHS['portable_reference'](ROOT, proof_path),
                   'parent_sha256': hashlib.sha256(proof_path.read_bytes()).hexdigest(),
                   'art_reference': PATHS['portable_reference'](ROOT, reference_path),
                   'art_reference_sha256': hashlib.sha256(reference_path.read_bytes()).hexdigest(),
                   'original_geometry': PATHS['portable_reference'](ROOT, original_path),
                   'original_geometry_sha256': hashlib.sha256(original_path.read_bytes()).hexdigest(),
                   'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   'controls': {'back_strength': back_strength, 'seat_strength': seat_strength},
                   'max_art_direction_delta': max((Vector(a) - Vector(b)).length for a, b in zip(final, base)),
                   'pinned_delta': max((Vector(a) - Vector(b)).length for a, b, rp in zip(final, base, rest) if rp[1] >= lower),
                   'main_skirt_audit': records, 'posed_vertices': final,
                   'unskinned_vertices': unskinned, 'unskinned_normals': unskinned_normals})
    output.write_text(json.dumps(report), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k not in ('posed_vertices', 'unskinned_vertices', 'unskinned_normals')}))
    return report


def relax(guidance_reference, guide_weight=.06):
    """Native collision-constrained fitting, starting from the safe B snapshot."""
    if not 0 < guide_weight <= .5:
        raise ValueError('Only compliant silhouette guides in (0, .5] are supported')
    guidance_path = PATHS['checked_input'](ROOT, guidance_reference)
    guidance = json.loads(guidance_path.read_text())
    parent_path = PATHS['checked_input'](ROOT, guidance['parent_proof'], guidance['parent_sha256'])
    parent = json.loads(parent_path.read_text())
    source_path = PATHS['checked_input'](ROOT, guidance['source'], guidance['source_sha256'])
    source = json.loads(source_path.read_text())
    name = SIM['create'](guidance['source'], shape_guided=True, support_source=guidance['support_source'],
                         bending_stiffness=12., guide_weight=.06, dynamic_rest=False)
    scene = bpy.data.scenes[name]
    scene['silhouette_guidance'] = PATHS['portable_reference'](ROOT, guidance_path)
    scene['silhouette_guidance_sha256'] = hashlib.sha256(guidance_path.read_bytes()).hexdigest()
    scene['experiment_scope'] = 'Static accepted nap pose; native fitting toward user-guided envelope, not a stand/nap transition'
    scene['guide_weight'] = guide_weight
    cloth = bpy.data.objects[scene['cloth_object']]
    reps = cloth['welded_representatives']
    for key in cloth.data.shape_keys.key_blocks:
        amount = 0. if key.name == 'Basis' else _smooth((int(key.name.split('_')[-1]) - 1) / 59.)
        posed = [Vector(a).lerp(Vector(b), amount) for a, b in zip(parent['posed_vertices'], guidance['posed_vertices'])]
        key.data.foreach_set('co', [v for i in reps for v in SIM['_xyz'](posed[i])])
    # Cloth springs use the safe posed surface as rest, not the standing skirt.
    for i, v in enumerate(cloth.data.vertices):
        v.co = SIM['_xyz'](parent['posed_vertices'][reps[i]])
    group = cloth.vertex_groups[next(m for m in cloth.modifiers if m.type == 'CLOTH').settings.vertex_group_mass]
    for i, original in enumerate(reps):
        weight = 1. if source['base_skirt']['vertices'][original][1] >= source['waist_attachment']['lower_y'] - 1e-6 else guide_weight
        group.add([i], weight, 'REPLACE')
    bodies = sorted((o for o in scene.objects if o.get('wear_body')), key=lambda o: o.name)
    for i, body in enumerate(bodies):
        posed = source['frames'][-1]['body_parts'][i]['vertices']
        for key in body.data.shape_keys.key_blocks:
            key.data.foreach_set('co', [v for j in body['welded_representatives'] for v in SIM['_xyz'](posed[j])])
    print(json.dumps({'guided_fitting_scene': name, 'body_pose': 'unchanged final nap0', 'compliant_pin_weight': guide_weight}))
    return name


def finish_relax(scene_name, tag='silhouette_fitted'):
    scene = bpy.data.scenes[scene_name]
    guidance_path = PATHS['checked_input'](ROOT, scene['silhouette_guidance'], scene['silhouette_guidance_sha256'])
    guidance = json.loads(guidance_path.read_text())
    SIM['finish'](scene_name, normal_smoothing=8, output_tag=tag)
    source_path = PATHS['checked_input'](ROOT, guidance['source'], guidance['source_sha256'])
    output = PATHS['checked_output'](ROOT, source_path, tag)
    result = json.loads(output.read_text())
    source = json.loads(source_path.read_text())
    parent_path = PATHS['checked_input'](ROOT, guidance['parent_proof'], guidance['parent_sha256'])
    parent = json.loads(parent_path.read_text())
    original_scene = bpy.context.window.scene
    try:
        bpy.context.window.scene = scene
        cloth = bpy.data.objects[scene['cloth_object']]
        graph = bpy.context.evaluated_depsgraph_get()
        bodies = sorted((o for o in scene.objects if o.get('wear_body')), key=lambda o: o.name)
        body_delta = 0.
        for obj, expected in zip(bodies, source['frames'][-1]['body_parts']):
            actual = obj.evaluated_get(graph).data.vertices
            body_delta = max(body_delta, max((Vector(SIM['_godot'](actual[i].co)) - Vector(p)).length
                                            for i, p in zip(obj['original_to_welded'], expected['vertices'])))
        scene.frame_set(1)
        actual = cloth.evaluated_get(graph).data.vertices
        initial_delta = max((Vector(SIM['_godot'](actual[i].co)) - Vector(p)).length
                            for i, p in zip(cloth['original_to_welded'], parent['posed_vertices']))
        if body_delta > 1e-6 or initial_delta > 1e-6:
            raise ValueError('Static fitting changed the body or did not start from safe B geometry')
    finally:
        scene.frame_set(180)
        bpy.context.window.scene = original_scene
    result.update({'method': scene['experiment_scope'], 'snapshot_only': True, 'transition_validated': False,
                   'silhouette_guidance': scene['silhouette_guidance'],
                   'silhouette_guidance_sha256': scene['silhouette_guidance_sha256'],
                   'guidance_tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   'static_pose_body_delta': body_delta, 'initial_safe_snapshot_delta': initial_delta,
                   'art_reference': guidance['art_reference'], 'art_reference_sha256': guidance['art_reference_sha256']})
    output.write_text(json.dumps(result), encoding='utf-8')
    return output
