"""Inspect authored cloth targets before they become solver forces or pinned geometry."""

import hashlib
import json
from pathlib import Path
import runpy

from mathutils import Vector
from mathutils.bvhtree import BVHTree


def audit(reference):
    root = Path(__file__).resolve().parents[1]
    paths = runpy.run_path(str(Path(__file__).with_name('wearing_proof_paths.py')))
    simulation = runpy.run_path(str(Path(__file__).with_name('simulate_wearing_blender.py')))
    path = paths['checked_input'](root, reference)
    data = json.loads(path.read_text(encoding='utf-8'))
    for ref, sha in data['source_sha256'].items():
        paths['checked_input'](root, ref, sha)
    base = data['base_skirt']
    attachment = data.get('waist_attachment', {})
    pin_low = attachment.get('pin_lower_y', attachment.get('lower_y',
        max(p[1] for p in base['vertices']) - .02))
    reps, _ = simulation['_weld'](base['vertices'])
    records = []
    for frame in data['frames']:
        targets = frame.get('cloth_shape_targets', frame['cloth_pin_targets'])
        points, faces, _ = simulation['_render_surface'](data, targets)
        tree = BVHTree.FromPolygons(points, faces, all_triangles=True)
        sets = [set(face) for face in faces]
        pairs = {(min(a, b), max(a, b)) for a, b in tree.overlap(tree)
                 if a != b and not sets[a].intersection(sets[b])}
        pinned = [face for face in faces if all(base['vertices'][reps[v]][1] >= pin_low - 1e-6 for v in face)]
        pin_tree = BVHTree.FromPolygons(points, pinned, all_triangles=True)
        contacts = []
        for i, body in enumerate(data['body_parts']):
            body_points = [Vector(simulation['_xyz'](p)) for p in frame['body_parts'][i]['vertices']]
            ids = body['indices']
            body_tree = BVHTree.FromPolygons(body_points, [ids[j:j + 3] for j in range(0, len(ids), 3)], all_triangles=True)
            contacts.append({'body': body['semantic'], 'all_target_pairs': len(tree.overlap(body_tree)),
                             'fully_pinned_pairs': len(pin_tree.overlap(body_tree))})
        records.append({'frame': frame['frame'], 'guide_self_pairs': len(pairs),
                        'fully_pinned_triangles': len(pinned), 'body_contacts': contacts})
    report = {'source': paths['portable_reference'](root, path),
              'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'scope': 'Input target triangles, not simulated geometry. Pin/body intersections are unsatisfiable hard attachments; weak-guide crossings are conflicting preferences, not automatic simulation failure.',
              'frames': records, 'sample_count': len(records),
              'self_crossing_guide_frames': sum(r['guide_self_pairs'] > 0 for r in records),
              'pinned_body_contact_frames': sum(any(c['fully_pinned_pairs'] for c in r['body_contacts']) for r in records)}
    output = paths['checked_output'](root, path, 'target_audit')
    output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'frames'} | {'last_frame': records[-1], 'output': str(output)}))
    return report
