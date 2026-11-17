"""Keep CURRENT's upper nap silhouette; study only a compliant hem reorientation.

Not a runtime solver or an accepted corrective. Strain uses the standing mesh's
edge lengths, not a calibrated 2D pattern or measured fabric stress/strain curve.
"""

import contextlib
import hashlib
import io
import json
import math
from pathlib import Path
import runpy

import bpy
import numpy as np
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
SIM = runpy.run_path(str(Path(__file__).with_name('simulate_wearing_blender.py')))
PATHS = SIM['PROOF_PATHS']


def strain(rest, posed, indices, maximum_ratio=1.1, boundary=.59):
    if len(rest) != len(posed) or not rest or not math.isfinite(maximum_ratio) or maximum_ratio < 1:
        raise ValueError('Invalid strain inputs')
    if not all(len(p) == 3 and all(math.isfinite(v) for v in p) for p in rest + posed):
        raise ValueError('Nonfinite strain points')
    if len(indices) % 3 or any(type(i) is not int or not 0 <= i < len(rest) for i in indices):
        raise ValueError('Invalid triangle indices')
    edges = {tuple(sorted((a, b))) for k in range(0, len(indices), 3)
             for a, b in zip(indices[k:k + 3], indices[k + 1:k + 3] + indices[k:k + 1])}
    groups = {'all': [], 'hem': [], 'transition': [], 'protected': []}
    for a, b in edges:
        length = (Vector(rest[a]) - Vector(rest[b])).length
        if length < 1e-6:
            continue
        ratio = (Vector(posed[a]) - Vector(posed[b])).length / length
        region = ('hem' if max(rest[a][1], rest[b][1]) <= .300001 else
                  'protected' if min(rest[a][1], rest[b][1]) >= boundary - 1e-6 else 'transition')
        groups['all'].append(ratio)
        groups[region].append(ratio)
    return {name: {'edges': len(values), 'maximum_ratio': max(values, default=0.),
                   'p95_ratio': sorted(values)[int(.95 * (len(values) - 1))] if values else 0.,
                   'over_screening_limit': sum(v > maximum_ratio for v in values)} for name, values in groups.items()}


def _ring_normal(points):
    values = np.asarray(points)
    center = values.mean(axis=0)
    _, _, vectors = np.linalg.svd(values - center)
    return Vector(center), Vector(vectors[-1])


def _set_rest_metric(cloth, rest):
    # Blender's rest key index 0 (Basis) means use the evaluated initial mesh.
    # Request a nonzero key; the actual solver regression must also pass.
    key = cloth.shape_key_add(name='FabricRestMetric')
    key.data.foreach_set('co', [v for i in cloth['welded_representatives'] for v in SIM['_xyz'](rest[i])])
    key.value = 0.
    modifier = next(m for m in cloth.modifiers if m.type == 'CLOTH')
    modifier.settings.rest_shape_key = key
    if cloth.data.shape_keys.key_blocks.find(key.name) <= 0:
        raise ValueError('Fabric rest metric must not be the Basis sentinel')
    return key


def create(source_reference, current_reference, native_reference, boundary=.59, guide_weight=.12):
    if not .39 <= boundary <= .7 or not 0 < guide_weight <= .5:
        raise ValueError('Expected a bounded lower-skirt study')
    source_path = PATHS['checked_input'](ROOT, source_reference)
    current_path = PATHS['checked_input'](ROOT, current_reference)
    native_path = PATHS['checked_input'](ROOT, native_reference)
    source = json.loads(source_path.read_text())
    current_packet = json.loads(current_path.read_text())
    native = json.loads(native_path.read_text())
    for ref, sha in source['source_sha256'].items():
        PATHS['checked_input'](ROOT, ref, sha)
    for ref, sha in current_packet['input_sha256'].items():
        PATHS['checked_input'](ROOT, ref, sha)
    PATHS['checked_input'](ROOT, native['source'], native['source_sha256'])
    if native['source_sha256'] != hashlib.sha256(source_path.read_bytes()).hexdigest():
        raise ValueError('Native reference has different topology')
    initial = [list(p) for p in current_packet['parts'][0]['vertices']]
    for seam in source['mesh_seam']['edge_bindings']:
        if seam['index'] != len(initial):
            raise ValueError('Current/seam correspondence differs')
        a, b = seam['edge']
        initial.append(list(Vector(initial[a]).lerp(Vector(initial[b]), seam['weight'])))
    rest = source['base_skirt']['vertices']
    if len(initial) != len(rest):
        raise ValueError('Current topology differs')
    ring = [i for i, p in enumerate(rest) if abs(p[1] - .2) < 1e-6]
    _, current_normal = _ring_normal([initial[i] for i in ring])
    _, native_normal = _ring_normal([native['posed_vertices'][i] for i in ring])
    if current_normal.dot(native_normal) < 0:
        native_normal.negate()
    rotation = current_normal.rotation_difference(native_normal)
    rows = {}
    for i, p in enumerate(rest):
        rows.setdefault(round(p[1], 6), []).append(i)
    target = [list(p) for p in initial]
    for height, ids in rows.items():
        t = max(0., min(1., (boundary - height) / (boundary - .2)))
        t = t * t * (3. - 2. * t)
        turn = Quaternion().slerp(rotation, t)
        center = sum((Vector(initial[i]) for i in ids), Vector()) / len(ids)
        for i in ids:
            target[i] = list(center + turn @ (Vector(initial[i]) - center))
    name = SIM['create'](source_reference, shape_guided=True, support_source=native['support_source'],
                         bending_stiffness=12., guide_weight=.06, dynamic_rest=False)
    scene = bpy.data.scenes[name]
    cloth = bpy.data.objects[scene['cloth_object']]
    representatives = cloth['welded_representatives']
    for key in cloth.data.shape_keys.key_blocks:
        if key.name == 'Basis':
            continue
        t = min(1., (int(key.name.split('_')[-1]) - 1) / 59.)
        t = t * t * (3. - 2. * t)
        points = [Vector(a).lerp(Vector(b), t) for a, b in zip(initial, target)]
        key.data.foreach_set('co', [v for i in representatives for v in SIM['_xyz'](points[i])])
    modifier = next(m for m in cloth.modifiers if m.type == 'CLOTH')
    _set_rest_metric(cloth, rest)
    group = cloth.vertex_groups[modifier.settings.vertex_group_mass]
    for i, original in enumerate(representatives):
        group.add([i], 1. if rest[original][1] >= boundary - 1e-6 else guide_weight, 'REPLACE')
    bodies = sorted((o for o in scene.objects if o.get('wear_body')), key=lambda o: o.name)
    for i, body in enumerate(bodies):
        points = source['frames'][-1]['body_parts'][i]['vertices']
        for key in body.data.shape_keys.key_blocks:
            key.data.foreach_set('co', [v for j in body['welded_representatives'] for v in SIM['_xyz'](points[j])])
    scene['current_hem_inputs'] = json.dumps({ref: hashlib.sha256(path.read_bytes()).hexdigest() for ref, path in
        [(source_reference, source_path), (current_reference, current_path), (native_reference, native_path)]})
    scene['current_hem_initial'] = json.dumps(initial)
    scene['current_hem_boundary'] = boundary
    scene['current_hem_angle_degrees'] = math.degrees(rotation.angle)
    scene['guide_weight'] = guide_weight
    scene['rest_metric_requested'] = 'FabricRestMetric'
    print(json.dumps({'scene': name, 'protected_rest_y_at_least': boundary,
                      'hem_target_rotation_degrees': math.degrees(rotation.angle),
                      'rest_metric_requested': 'FabricRestMetric', 'rest_metric_validated': False,
                      'guide_weight': guide_weight}))
    return name


def finish(name, tag='current_local_hem'):
    scene = bpy.data.scenes[name]
    dependencies = json.loads(scene['current_hem_inputs'])
    for ref, sha in dependencies.items():
        PATHS['checked_input'](ROOT, ref, sha)
    source_path = PATHS['checked_input'](ROOT, scene['source'], scene['source_sha256'])
    source = json.loads(source_path.read_text())
    initial = json.loads(scene['current_hem_initial'])
    with contextlib.redirect_stdout(io.StringIO()):
        SIM['finish'](name, normal_smoothing=8, output_tag=tag)
    output = PATHS['checked_output'](ROOT, source_path, tag)
    result = json.loads(output.read_text())
    rest = source['base_skirt']['vertices']
    boundary = scene['current_hem_boundary']
    protected_delta = max((Vector(a) - Vector(b)).length for a, b, p in zip(initial, result['posed_vertices'], rest)
                          if p[1] >= boundary - 1e-6)
    result.update({'snapshot_only': True, 'transition_validated': False,
                   'method': 'CURRENT upper skirt pinned unchanged; only lower skirt native fitting toward referenced hem angle',
                   'protected_delta': protected_delta, 'protected_rest_y': boundary,
                   'target_rotation_degrees': scene['current_hem_angle_degrees'],
                   'rest_metric_requested': scene.get('rest_metric_requested', 'Basis (legacy run)'),
                   'rest_metric_validated': False,
                   'strain_screening_ratio': 1.1, 'screening_is_not_measured_fabric_limit': True,
                   'strain_before': strain(rest, initial, source['base_skirt']['indices'], boundary=boundary),
                   'strain_after': strain(rest, result['posed_vertices'], source['base_skirt']['indices'], boundary=boundary),
                   'dependency_sha256': dependencies, 'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()})
    if protected_delta > 1e-6:
        raise ValueError('Native fitting changed protected CURRENT geometry')
    output.write_text(json.dumps(result), encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('method', 'protected_delta', 'strain_before', 'strain_after',
                                            'nonadjacent_self_pairs', 'body_triangle_pairs')}))
    return output
