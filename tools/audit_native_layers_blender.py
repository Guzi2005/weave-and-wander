"""BVH diagnostics of actual Godot capture geometry. Does not change Blender scenes."""

import hashlib
import json
from pathlib import Path
import runpy

from mathutils import Vector
from mathutils.bvhtree import BVHTree


def _surface(part):
    unique, mapping, points = {}, [], []
    for point in part['vertices']:
        key = tuple(round(v, 6) for v in point)
        if key not in unique:
            unique[key] = len(points)
            points.append(Vector(point))
        mapping.append(unique[key])
    faces, degenerate = [], 0
    ids = part['indices']
    for offset in range(0, len(ids), 3):
        face = [mapping[i] for i in ids[offset:offset + 3]]
        if len(face) != 3:
            raise ValueError('Incomplete triangle')
        a, b, c = [points[i] for i in face]
        if len(set(face)) != 3 or (b - a).cross(c - a).length_squared < 1e-20:
            degenerate += 1
            continue
        faces.append(face)
    return BVHTree.FromPolygons(points, faces, all_triangles=True), faces, degenerate


def _part_records(parts):
    surfaces = [_surface(part) for part in parts]
    records = []
    for i, part in enumerate(parts):
        if part['role'] != 'cloth':
            continue
        tree, faces, degenerate = surfaces[i]
        face_sets = [set(face) for face in faces]
        self_pairs = {(min(a, b), max(a, b)) for a, b in tree.overlap(tree)
                      if a != b and not face_sets[a].intersection(face_sets[b])}
        collisions = []
        for j, other in enumerate(parts):
            if i == j or (other['role'] == 'cloth' and j < i):
                continue
            pairs = tree.overlap(surfaces[j][0])
            collisions.append({'name': other['name'], 'role': other['role'],
                               'triangle_pairs': len(pairs)})
        records.append({'name': part['name'], 'triangles': len(faces),
                        'degenerate_triangles': degenerate,
                        'nonadjacent_self_pairs': len(self_pairs), 'contacts': collisions})
    body_support = sum(len(surfaces[i][0].overlap(surfaces[j][0])) for i, part in enumerate(parts)
                       for j, other in enumerate(parts) if part['role'] == 'body' and other['role'] == 'support')
    return records, body_support


def audit(reference):
    root = Path(__file__).resolve().parents[1]
    paths = runpy.run_path(str(Path(__file__).with_name('wearing_proof_paths.py')))
    path = paths['checked_input'](root, reference)
    packet = json.loads(path.read_text(encoding='utf-8'))
    for ref, digest in packet['input_sha256'].items():
        paths['checked_input'](root, ref, digest)
    records, _ = _part_records(packet['parts'])
    report = {'source': paths['portable_reference'](root, path),
              'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'audit_source_sha256': {paths['portable_reference'](root, script):
                  hashlib.sha256(script.read_bytes()).hexdigest() for script in
                  [Path(__file__).resolve(), Path(__file__).with_name('wearing_proof_paths.py').resolve()]},
              'snapshot_only': True, 'transition_validated': False,
              'scope': 'BVH candidate intersections; original render triangles with 1e-6 seam weld. No CCD or containment guarantee.',
              'parts': records,
              'total_candidate_pairs': sum(r['nonadjacent_self_pairs'] +
                  sum(c['triangle_pairs'] for c in r['contacts']) for r in records)}
    output = paths['checked_output'](root, path, 'layer_audit')
    output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))
    return report


def audit_motion(reference):
    root = Path(__file__).resolve().parents[1]
    paths = runpy.run_path(str(Path(__file__).with_name('wearing_proof_paths.py')))
    path = paths['checked_input'](root, reference)
    packet = json.loads(path.read_text(encoding='utf-8'))
    for ref, digest in packet['input_sha256'].items():
        paths['checked_input'](root, ref, digest)
    if packet.get('failures') or not packet.get('body_and_rest_unchanged'):
        raise ValueError('Runtime capture invariants failed')
    frames = []
    for sample in packet['frames']:
        if len(sample['vertices']) != len(packet['parts']):
            raise ValueError('Runtime topology count differs')
        parts = [{**part, 'vertices': points} for part, points in zip(packet['parts'], sample['vertices'])] + [packet['support']]
        records, body_support = _part_records(parts)
        frames.append({'phase': sample['phase'], 'step': sample['step'], 'rest_blend': sample['rest_blend'],
                       'self_pairs': sum(r['nonadjacent_self_pairs'] for r in records),
                       'layer_pairs': sum(c['triangle_pairs'] for r in records for c in r['contacts'] if c['role'] == 'cloth'),
                       'body_pairs': sum(c['triangle_pairs'] for r in records for c in r['contacts'] if c['role'] == 'body'),
                       'support_pairs': sum(c['triangle_pairs'] for r in records for c in r['contacts'] if c['role'] == 'support'),
                       'body_support_pairs': body_support})
    report = {'source': paths['portable_reference'](root, path), 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'transition_validated': False, 'scope': 'Sampled runtime skinning and layers; triangle overlap only, no CCD or containment',
              'samples': len(frames), 'frames': frames,
              'frames_with_contacts': sum(any(frame[key] for key in ('self_pairs', 'layer_pairs', 'body_pairs', 'support_pairs')) for frame in frames)}
    output = paths['checked_output'](root, path, 'runtime_layer_audit')
    output.write_text(json.dumps(report), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'frames'}))
    return report
