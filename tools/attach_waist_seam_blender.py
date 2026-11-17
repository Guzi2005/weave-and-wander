"""Isolated, snapshot-only waist attachment on a verified native cloth result.

Retain the simulated skirt, split at the authored waist boundary, attach the new
seam points, then ease only the unpinned local intersection neighborhood. This is
not another cloth simulation and must not be presented as motion acceptance.
"""

import hashlib
import json
import math
from pathlib import Path
import runpy

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
SIM = runpy.run_path(str(Path(__file__).with_name('simulate_wearing_blender.py')))
PATHS = SIM['PROOF_PATHS']


def _tree(points, indices):
    return BVHTree.FromPolygons([Vector(SIM['_xyz'](p)) for p in points],
                               [indices[i:i + 3] for i in range(0, len(indices), 3)], all_triangles=True)


def _self_pairs(points, faces):
    tree = BVHTree.FromPolygons(points, faces, all_triangles=True)
    sets = [set(face) for face in faces]
    return sorted({(min(a, b), max(a, b)) for a, b in tree.overlap(tree)
                   if a != b and not sets[a].intersection(sets[b])})


def _finish_modifier(cloth, weights, factor=.25, iterations=3):
    if not math.isfinite(factor) or not 0 < factor <= .5 or not isinstance(iterations, int) or not 1 <= iterations <= 6:
        raise ValueError('Finish requires factor in (0, .5] and 1..6 iterations')
    for vertex, weight in weights.items():
        index = int(vertex)
        if str(index) != str(vertex) or not 0 <= index < len(cloth.data.vertices) or not math.isfinite(weight) or not 0 < weight <= 1:
            raise ValueError('Invalid local finish vertex or weight')
    group = cloth.vertex_groups.new(name='LocalFreeCloth')
    for vertex, weight in weights.items():
        group.add([int(vertex)], weight, 'REPLACE')
    if not weights:
        return
    modifier = cloth.modifiers.new('Native local attachment finish', 'CORRECTIVE_SMOOTH')
    modifier.vertex_group = group.name
    for prop, value in [('rest_source', 'ORCO'), ('smooth_type', 'LENGTH_WEIGHTED')]:
        if value not in [item.identifier for item in modifier.bl_rna.properties[prop].enum_items]:
            raise ValueError('Unsupported native modifier enum: ' + prop)
        setattr(modifier, prop, value)
    modifier.use_only_smooth = True
    modifier.use_pin_boundary = True
    modifier.factor = factor
    modifier.iterations = iterations


def _static_finish_object(scene, name, base, posed, weights, factor=.25, iterations=3):
    # New-scene F-curves need a later dependency update; this probe is not animated.
    cloth = SIM['_object'](scene, name, base, [(1, posed)])
    cloth.data.shape_keys.animation_data_clear()
    cloth.data.shape_keys.key_blocks['Pose_1'].value = 1.0
    _finish_modifier(cloth, weights, factor, iterations)
    return cloth


def _motion_seed_pairs(audit, face_count):
    cache = audit.get('cache_validation', {})
    if cache.get('is_outdated', True) or cache.get('is_frame_skip', True) or cache.get('last_sequential_frame') != 180:
        raise ValueError('Motion seed requires a complete, valid native cache')
    if audit.get('attachment_guard_frames') != [] or not math.isfinite(audit.get('final_snapshot_delta', math.inf)) or audit.get('final_snapshot_delta', math.inf) > 1e-6:
        raise ValueError('Motion seed requires valid displacement and endpoint guards')
    if [frame['frame'] for frame in audit['frames']] != list(range(1, 181)):
        raise ValueError('Motion seed requires every frame in order')
    pairs = set()
    for frame in audit['frames']:
        for pair in frame['self_triangle_pairs']:
            if len(pair) != 2 or any(type(i) is not int or not 0 <= i < face_count for i in pair) or pair[0] == pair[1]:
                raise ValueError('Invalid motion seed triangle pair')
            pairs.add(tuple(sorted(pair)))
    return pairs


def build(base_proof_reference, seamed_source_reference, output_tag='seam_attached', motion_audit_reference=None,
          factor=.25, iterations=3):
    proof_path = PATHS['checked_input'](ROOT, base_proof_reference)
    proof = json.loads(proof_path.read_text(encoding='utf-8'))
    old_path = PATHS['checked_input'](ROOT, proof['source'], proof['source_sha256'])
    source_path = PATHS['checked_input'](ROOT, seamed_source_reference)
    source = json.loads(source_path.read_text(encoding='utf-8'))
    old = json.loads(old_path.read_text(encoding='utf-8'))
    for data in [old, source]:
        for ref, sha in data['source_sha256'].items():
            PATHS['checked_input'](ROOT, ref, sha)
    cache = proof.get('cache_validation', {})
    if cache.get('is_outdated', True) or cache.get('is_frame_skip', True) or cache.get('last_sequential_frame') != 180 or proof['frame'] != 180:
        raise ValueError('Base proof must have verified complete native cache')
    if source['body_parts'] != old['body_parts'] or source['bone_count'] != old['bone_count']:
        raise ValueError('Body or skeleton correspondence differs')
    if [f['body_parts'] for f in source['frames']] != [f['body_parts'] for f in old['frames']]:
        raise ValueError('Body motion differs between inputs')
    count = len(old['base_skirt']['vertices'])
    if source['base_skirt']['vertices'][:count] != old['base_skirt']['vertices']:
        raise ValueError('Refinement changed original standing points')
    if len(proof['posed_vertices']) != count:
        raise ValueError('Original simulation count differs')
    support_path = PATHS['checked_input'](ROOT, proof['support_source'], proof['support_sha256'])
    support = json.loads(support_path.read_text(encoding='utf-8'))
    output = PATHS['checked_output'](ROOT, source_path, output_tag)
    posed = [list(p) for p in proof['posed_vertices']]
    max_attachment_delta = 0.0
    for entry in source['mesh_seam']['edge_bindings']:
        a, b = entry['edge']
        t = entry['weight']
        if entry['index'] != len(posed) or min(a, b) < 0 or max(a, b) >= count or not 0 <= t <= 1:
            raise ValueError('Invalid seam edge binding')
        target = Vector(source['frames'][-1]['cloth_shape_targets'][entry['index']])
        max_attachment_delta = max(max_attachment_delta, (Vector(posed[a]).lerp(Vector(posed[b]), t) - target).length)
        posed.append(list(target))
    if max_attachment_delta > .02:
        raise ValueError('Seam attachment exceeds local correction limit')
    points, faces, mapping = SIM['_render_surface'](source, posed)
    reps, _ = SIM['_weld'](source['base_skirt']['vertices'])
    lower = source['waist_attachment']['lower_y']
    pinned = {i for i, original in enumerate(reps) if source['base_skirt']['vertices'][original][1] >= lower - 1e-6}
    neighbors = [set() for _ in points]
    for face in faces:
        for vertex in face:
            neighbors[vertex].update(i for i in face if i != vertex)
    seed_pairs = _self_pairs(points, faces)
    motion_seed = None
    if motion_audit_reference:
        audit_path = PATHS['checked_input'](ROOT, motion_audit_reference)
        audit = json.loads(audit_path.read_text(encoding='utf-8'))
        audit_proof_path = PATHS['checked_input'](ROOT, audit['source_proof'], audit['source_proof_sha256'])
        audit_proof = json.loads(audit_proof_path.read_text(encoding='utf-8'))
        if audit_proof['source_sha256'] != hashlib.sha256(source_path.read_bytes()).hexdigest() or audit['attachment_guard_frames']:
            raise ValueError('Motion seed is not a compatible, valid attachment audit')
        if audit_proof['base_native_proof_sha256'] != hashlib.sha256(proof_path.read_bytes()).hexdigest():
            raise ValueError('Motion seed has a different native base')
        seed_pairs = sorted(set(seed_pairs).union(_motion_seed_pairs(audit, len(faces))))
        motion_seed = {'source': PATHS['portable_reference'](ROOT, audit_path), 'sha256': hashlib.sha256(audit_path.read_bytes()).hexdigest()}
    distances = {v: 0 for a, b in seed_pairs for face in (faces[a], faces[b]) for v in face if v not in pinned}
    for level in range(1, 5):
        for v in [v for v, distance in distances.items() if distance == level - 1]:
            for neighbor in neighbors[v]:
                if neighbor not in pinned and neighbor not in distances:
                    distances[neighbor] = level
    weights = {v: 1 - distance / 5 for v, distance in distances.items()}
    original_scene = bpy.context.window.scene
    scene = bpy.data.scenes.new('WW_Seam_Attachment_Proof')
    try:
        cloth = _static_finish_object(scene, 'WW_SeamAttachedSkirt', source['base_skirt'], posed, weights, factor, iterations)
        bpy.context.window.scene = scene
        scene.frame_set(1)
        evaluated = cloth.evaluated_get(bpy.context.evaluated_depsgraph_get())
        final = [v.co.copy() for v in evaluated.data.vertices]
        maximum = max((a - b).length for a, b in zip(final, points))
        pin_delta = max((final[v] - points[v]).length for v in pinned)
        outside_delta = max((final[v] - points[v]).length for v in range(len(points)) if v not in weights)
        if maximum > .02 or pin_delta > 1e-6 or outside_delta > 1e-6:
            raise ValueError('Local finish changed protected geometry or exceeded displacement limit')
        tree = BVHTree.FromPolygons(final, faces, all_triangles=True)
        contacts = {body['semantic']: len(tree.overlap(_tree(source['frames'][-1]['body_parts'][i]['vertices'], body['indices'])))
                    for i, body in enumerate(source['body_parts'])}
        contacts['cushion'] = len(tree.overlap(_tree(support['vertices'], support['indices'])))
        final_pairs = _self_pairs(final, faces)
        sums = [Vector() for _ in final]
        for a, b, c in faces:
            normal = (final[b] - final[a]).cross(final[c] - final[a])
            for vertex in [a, b, c]:
                sums[vertex] += normal
        sums = [n.normalized() for n in sums]
        for _ in range(8):
            sums = [(n * .5 + sum((sums[j] for j in neighbors[i]), Vector()) * (.5 / len(neighbors[i]))).normalized()
                    if neighbors[i] else n for i, n in enumerate(sums)]
        final_posed = [SIM['_godot'](final[i]) for i in mapping]
        normals = [SIM['_godot'](sums[i]) for i in mapping]
        inverses = source['frames'][-1]['cloth_inverse_skin_transforms']
        unskinned = [list(Matrix(t['basis_rows']) @ Vector(p) + Vector(t['origin'])) for p, t in zip(final_posed, inverses)]
        unskinned_normals = [list((Matrix(t['basis_rows']) @ Vector(n)).normalized()) for n, t in zip(normals, inverses)]
        report = {'experimental_not_accepted': True, 'snapshot_only': True, 'transition_validated': False,
                  'method': 'Verified native cloth snapshot plus exact hip waist seam and local unpinned native finish; not a new simulation',
                  'source': PATHS['portable_reference'](ROOT, source_path), 'source_sha256': hashlib.sha256(source_path.read_bytes()).hexdigest(),
                  'base_native_proof': PATHS['portable_reference'](ROOT, proof_path), 'base_native_proof_sha256': hashlib.sha256(proof_path.read_bytes()).hexdigest(),
                  'support_source': PATHS['portable_reference'](ROOT, support_path), 'support_sha256': proof['support_sha256'],
                  'frame': 180, 'scene': scene.name, 'blender_version': bpy.app.version_string,
                  'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  'finish_weights': weights, 'seed_pairs': seed_pairs, 'nonadjacent_self_pairs': len(final_pairs),
                  'finish_settings': {'factor': factor, 'iterations': iterations},
                  'motion_seed': motion_seed,
                  'body_triangle_pairs': contacts, 'leg_center_containment': SIM['_containment'](final, faces, source),
                  'max_attachment_delta': max_attachment_delta, 'max_finish_delta': maximum,
                  'fully_pinned_delta': pin_delta, 'outside_finish_neighborhood_delta': outside_delta,
                  'posed_vertices': final_posed, 'unskinned_vertices': unskinned, 'unskinned_normals': unskinned_normals}
        output.write_text(json.dumps(report), encoding='utf-8')
        print(json.dumps({k: v for k, v in report.items() if k not in ('posed_vertices', 'unskinned_vertices', 'unskinned_normals', 'finish_weights', 'leg_center_containment')}))
        return report
    finally:
        bpy.context.window.scene = original_scene


def audit_motion(proof_reference, native_scene_name, output_tag='seam_attached_motion_audit', cache_filter_radius=0,
                 capture_frames=()):
    """Replay a verified cache; the finishing neighborhood stays fixed across time."""
    proof_path = PATHS['checked_input'](ROOT, proof_reference)
    proof = json.loads(proof_path.read_text(encoding='utf-8'))
    source_path = PATHS['checked_input'](ROOT, proof['source'], proof['source_sha256'])
    source = json.loads(source_path.read_text(encoding='utf-8'))
    base_path = PATHS['checked_input'](ROOT, proof['base_native_proof'], proof['base_native_proof_sha256'])
    base = json.loads(base_path.read_text(encoding='utf-8'))
    support_path = PATHS['checked_input'](ROOT, proof['support_source'], proof['support_sha256'])
    support = json.loads(support_path.read_text(encoding='utf-8'))
    for reference, sha in source['source_sha256'].items():
        PATHS['checked_input'](ROOT, reference, sha)
    native = bpy.data.scenes[native_scene_name]
    native_path, _ = PATHS['scene_inputs'](ROOT, native)
    if hashlib.sha256(native_path.read_bytes()).hexdigest() != base['source_sha256']:
        raise ValueError('Native scene does not correspond to the base proof')
    old = json.loads(native_path.read_text(encoding='utf-8'))
    if type(cache_filter_radius) is not int or cache_filter_radius not in (0, 1, 2):
        raise ValueError('Unsupported offline cache filter radius')
    if any(type(frame) is not int or not 1 <= frame <= 180 for frame in capture_frames):
        raise ValueError('Capture frame outside the native cache')
    original_scene = bpy.context.window.scene
    samples = []
    try:
        bpy.context.window.scene = native
        SIM['_cache_state'](native, require_end=True)
        obj = bpy.data.objects[native['cloth_object']]
        graph = bpy.context.evaluated_depsgraph_get()
        final = [SIM['_godot'](obj.evaluated_get(graph).data.vertices[i].co) for i in obj['original_to_welded']]
        if max((Vector(a) - Vector(b)).length for a, b in zip(final, base['posed_vertices'])) > 1e-6:
            raise ValueError('Native final cache differs from the verified base proof')
        bodies = sorted((o for o in native.objects if o.get('wear_body')), key=lambda o: o.name)
        if len(bodies) != len(source['body_parts']):
            raise ValueError('Native body count differs')
        for frame in range(1, native.frame_end + 1):
            native.frame_set(frame)
            graph = bpy.context.evaluated_depsgraph_get()
            mesh = obj.evaluated_get(graph).data
            SIM['_cache_state'](native)
            posed = [SIM['_godot'](mesh.vertices[i].co) for i in obj['original_to_welded']]
            body_samples = []
            for body in bodies:
                mesh = body.evaluated_get(graph).data
                body_samples.append([SIM['_godot'](mesh.vertices[i].co) for i in body['original_to_welded']])
            samples.append({'frame': frame, 'posed': posed, 'bodies': body_samples})
        cache_state = SIM['_cache_state'](native, require_end=True)
        cache_filter = None
        if cache_filter_radius:
            helper = Path(__file__).with_name('cloth_cache_filter.py')
            samples, cache_filter = runpy.run_path(str(helper))['filter_samples'](
                samples, old['base_skirt']['vertices'], source['waist_attachment']['lower_y'], cache_filter_radius)
            cache_filter['tool_sha256'] = hashlib.sha256(helper.read_bytes()).hexdigest()
        scene = bpy.data.scenes.new('WW_Waist_Attachment_Motion_Audit')
        cloth = _static_finish_object(scene, 'WW_AttachmentMotion', source['base_skirt'],
                                      proof['posed_vertices'], proof['finish_weights'], **proof.get('finish_settings', {}))
        bpy.context.window.scene = scene
        scene.frame_set(1)
        reps, mapping = SIM['_weld'](source['base_skirt']['vertices'])
        _, faces, _ = SIM['_render_surface'](source, proof['posed_vertices'])
        low = source['waist_attachment']['lower_y']
        pinned = {i for i, r in enumerate(reps) if source['base_skirt']['vertices'][r][1] >= low - 1e-6}
        support_tree = _tree(support['vertices'], support['indices'])
        key = cloth.data.shape_keys.key_blocks['Pose_1']
        if key.value != 1.0 or cloth.data.shape_keys.animation_data is not None:
            raise ValueError('Static finishing probe must not depend on animated shape values')
        records = []
        captured_geometry = []
        for sample in samples:
            frame = sample['frame']
            upper_index = next(i for i, value in enumerate(source['frames']) if value['frame'] >= frame)
            high = source['frames'][upper_index]
            low_frame = source['frames'][max(0, upper_index - 1)]
            t = (frame - low_frame['frame']) / max(1, high['frame'] - low_frame['frame'])
            posed = [list(p) for p in sample['posed']]
            attachment_delta = 0.0
            for binding in source['mesh_seam']['edge_bindings']:
                index = binding['index']
                a, b = binding['edge']
                if index != len(posed) or max(a, b) >= len(old['base_skirt']['vertices']):
                    raise ValueError('Invalid refinement binding')
                target = Vector(low_frame['cloth_shape_targets'][index]).lerp(Vector(high['cloth_shape_targets'][index]), t)
                attachment_delta = max(attachment_delta, (Vector(posed[a]).lerp(Vector(posed[b]), binding['weight']) - target).length)
                posed.append(list(target))
            points = [Vector(SIM['_xyz'](posed[r])) for r in reps]
            key.data.foreach_set('co', [coordinate for p in points for coordinate in p])
            cloth.data.shape_keys.update_tag()
            cloth.data.update()
            cloth.update_tag()
            bpy.context.view_layer.update()
            graph = bpy.context.evaluated_depsgraph_get()
            evaluated = cloth.evaluated_get(graph)
            final = [v.co.copy() for v in evaluated.data.vertices]
            if not all(math.isfinite(c) for p in final for c in p):
                raise ValueError('Nonfinite attachment motion')
            tree = BVHTree.FromPolygons(final, faces, all_triangles=True)
            contacts = {body['semantic']: len(tree.overlap(_tree(sample['bodies'][i], body['indices'])))
                        for i, body in enumerate(source['body_parts'])}
            contacts['cushion'] = len(tree.overlap(support_tree))
            pairs = _self_pairs(final, faces)
            if frame in capture_frames:
                captured_geometry.append({'frame': frame, 'posed_vertices': [SIM['_godot'](final[i]) for i in mapping],
                                          'body_vertices': sample['bodies'], 'self_triangle_pairs': pairs})
            records.append({'frame': frame, 'self_pairs': len(pairs), 'self_triangle_pairs': pairs,
                            'collider_pairs': contacts, 'attachment_delta': attachment_delta,
                            'finish_delta': max((a - b).length for a, b in zip(points, final)),
                            'pinned_delta': max((points[i] - final[i]).length for i in pinned),
                            'cache_filter_delta': cache_filter['frame_deltas'][frame - 1] if cache_filter else 0.0,
                            'outside_finish_delta': max((points[i] - final[i]).length for i in range(len(points))
                                                        if str(i) not in proof['finish_weights'])})
        final_snapshot_delta = max((Vector(SIM['_godot'](final[i])) - Vector(p)).length
                                   for i, p in zip(mapping, proof['posed_vertices']))
        if final_snapshot_delta > 1e-6:
            raise ValueError('Motion endpoint does not reproduce the independent static proof')
        report = {'experimental_not_accepted': True, 'transition_validated': False,
                  'scope': 'Every cached frame, fixed finish weights, original render topology. No CCD or garment-layer motion audit.',
                  'source_proof': PATHS['portable_reference'](ROOT, proof_path), 'source_proof_sha256': hashlib.sha256(proof_path.read_bytes()).hexdigest(),
                  'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  'native_scene': native_scene_name, 'cache_validation': cache_state, 'samples': len(records), 'frames': records,
                  'final_snapshot_delta': final_snapshot_delta,
                  'cache_filter': cache_filter,
                  'contact_frames': sum(r['self_pairs'] > 0 or any(r['collider_pairs'].values()) for r in records),
                  'attachment_guard_frames': [r['frame'] for r in records if r['attachment_delta'] > .02 or r['finish_delta'] > .02
                                              or r['pinned_delta'] > 1e-6 or r['outside_finish_delta'] > 1e-6]}
        report['cache_filter_guard_frames'] = [r['frame'] for r in records if r['cache_filter_delta'] > .02]
        if captured_geometry:
            report['captured_geometry'] = captured_geometry
        output = PATHS['checked_output'](ROOT, source_path, output_tag)
        output.write_text(json.dumps(report), encoding='utf-8')
        print(json.dumps({k: v for k, v in report.items() if k not in ('frames', 'captured_geometry')}))
        return report
    finally:
        bpy.context.window.scene = original_scene
