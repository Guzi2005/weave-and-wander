"""Isolated Blender cloth experiment, driven by unchanged Godot body animation.

Run through Blender MCP. This never writes production meshes or saves the user's
blend file. Finish exports diagnostic geometry; it is not an accepted corrective.
"""
import hashlib
import json
import math
import runpy
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROOF_PATHS = runpy.run_path(str(Path(__file__).with_name('wearing_proof_paths.py')))


def rebind_scene_sources(scene_name, source, support_source=None):
    """Explicitly adopt migrated, byte-identical inputs without changing the simulation."""
    scene = bpy.data.scenes[scene_name]
    PROOF_PATHS['rebind_inputs'](PROJECT_ROOT, scene, source, support_source)
    print(json.dumps({'scene': scene.name, 'source': scene['source'],
                      'support_source': scene.get('support_source', '')}))


def _xyz(point):
    return (point[0], -point[2], point[1])


def _godot(point):
    return [point[0], point[2], -point[1]]


def _weld(points):
    unique, representatives, mapping = {}, [], []
    for index, point in enumerate(points):
        key = tuple(round(v, 6) for v in point)
        if key not in unique:
            unique[key] = len(representatives)
            representatives.append(index)
        mapping.append(unique[key])
    return representatives, mapping


def _quad_pairs(faces):
    quads = []
    for offset in range(0, len(faces), 2):
        pair = faces[offset:offset + 2]
        directed = [(a, b) for f in pair for a, b in zip(f, f[1:] + f[:1])]
        boundary = [(a, b) for a, b in directed if (b, a) not in directed]
        if len(boundary) != 4:
            raise ValueError('Expected paired grid triangles')
        following = dict(boundary)
        if len(following) != 4:
            raise ValueError('Invalid quad boundary')
        quad = [boundary[0][0]]
        for _ in range(3):
            quad.append(following[quad[-1]])
        if following[quad[-1]] != quad[0] or len(set(quad)) != 4:
            raise ValueError('Noncyclic quad')
        quads.append(quad)
    return quads


def _object(scene, name, base, samples, use_quads=False):
    representatives, mapping = _weld(base['vertices'])
    vertices = [_xyz(base['vertices'][i]) for i in representatives]
    faces = []
    for offset in range(0, len(base['indices']), 3):
        ids = base['indices'][offset:offset + 3]
        a, b, c = (Vector(base['vertices'][i]) for i in ids)
        normal = sum((Vector(base['normals'][i]) for i in ids), Vector())
        if (b - a).cross(c - a).dot(normal) < 0:
            ids.reverse()
        welded = [mapping[i] for i in ids]
        if len(set(welded)) == 3:
            faces.append(welded)
    if use_quads:
        faces = _quad_pairs(faces)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.shape_key_add(name='Basis')
    for sample_index, (frame, points) in enumerate(samples):
        key = obj.shape_key_add(name=f'Pose_{frame}')
        key.data.foreach_set('co', [v for i in representatives for v in _xyz(points[i])])
        if sample_index:
            key.value = 0
            key.keyframe_insert('value', frame=samples[sample_index - 1][0])
        key.value = 1
        key.keyframe_insert('value', frame=frame)
        if sample_index + 1 < len(samples):
            key.value = 0
            key.keyframe_insert('value', frame=samples[sample_index + 1][0])
    action = mesh.shape_keys.animation_data.action
    for curve in action.fcurves:
        for point in curve.keyframe_points:
            point.interpolation = 'LINEAR'
    obj['original_to_welded'] = mapping
    obj['welded_representatives'] = representatives
    return obj


def create(source, use_quads=False, coarse=False, shape_guided=False, support_source=None,
           bending_stiffness=3.0, guide_weight=.02, dynamic_rest=None,
           quality=30, collision_quality=5):
    if not math.isfinite(bending_stiffness) or not 0 <= bending_stiffness <= 100:
        raise ValueError('Expected experimental bending stiffness in 0..100')
    if not math.isfinite(guide_weight) or not 0 <= guide_weight <= .1:
        raise ValueError('Expected weak guide weight in 0..0.1')
    if dynamic_rest is not None and not isinstance(dynamic_rest, bool):
        raise ValueError('Expected a boolean dynamic_rest option')
    if not isinstance(quality, int) or not 5 <= quality <= 100:
        raise ValueError('Expected cloth quality in 5..100')
    if not isinstance(collision_quality, int) or not 1 <= collision_quality <= 20:
        raise ValueError('Expected collision quality in 1..20')
    if shape_guided and coarse:
        raise ValueError('Guided and coarse experiments must stay separate')
    source = PROOF_PATHS['checked_input'](PROJECT_ROOT, source)
    support_path = PROOF_PATHS['checked_input'](PROJECT_ROOT, support_source) if support_source else None
    data = json.loads(source.read_text(encoding='utf-8'))
    attachment = data.get('waist_attachment')
    if attachment:
        if not shape_guided or coarse or attachment.get('bone') != 'Hips':
            raise ValueError('Waist attachment needs original topology and shared-bone targets')
        low = attachment.get('pin_lower_y', attachment['lower_y'])
        high, release = (attachment[k] for k in ('upper_y', 'release_y'))
        if not all(math.isfinite(v) for v in (low, high, release)) or not release < low < high:
            raise ValueError('Invalid waistband attachment bounds')
    support = json.loads(support_path.read_text(encoding='utf-8')) if support_path else None
    scene = bpy.data.scenes.new('WW_Wearing_Physics_Experiment')
    scene['source'] = PROOF_PATHS['portable_reference'](PROJECT_ROOT, source)
    scene['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
    scene['original_scene'] = bpy.context.scene.name
    scene.frame_end = 180
    scene.render.fps = 30
    scene.gravity = (0, 0, -9.81)
    frames = data['frames']
    for index, body in enumerate(data['body_parts']):
        samples = [(f['frame'], f['body_parts'][index]['vertices']) for f in frames]
        base_body = {**body, 'vertices': body['rest_vertices']}
        obj = _object(scene, 'WW_WearBody_' + str(index), base_body, samples)
        obj.modifiers.new('Body collision', 'COLLISION')
        obj.collision.thickness_outer = .005
        obj.collision.thickness_inner = .003
        obj.collision.cloth_friction = 3
        obj['wear_body'] = True
    if support_path:
        obj = _object(scene, 'WW_WearBenchCushion', support,
                      [(1, support['vertices']), (180, support['vertices'])])
        obj.modifiers.new('Actual cushion collision', 'COLLISION')
        obj.collision.thickness_outer = .005
        obj.collision.cloth_friction = 3
        obj['wear_support'] = True
        scene['support_source'] = PROOF_PATHS['portable_reference'](PROJECT_ROOT, support_path)
        scene['support_sha256'] = hashlib.sha256(support_path.read_bytes()).hexdigest()
    base = data['base_skirt']
    sample_key = 'cloth_shape_targets' if shape_guided else 'cloth_pin_targets'
    samples = [(f['frame'], f[sample_key]) for f in frames]
    if coarse:
        cage = runpy.run_path(str(Path(__file__).with_name('coarse_wearing_cage.py')))
        base, samples, source_bindings, render_bindings = cage['build'](data)
        scene['cage_transfer'] = json.dumps({'base': base['vertices'], 'source': source_bindings, 'render': render_bindings})
        use_quads = True
    cloth = _object(scene, 'WW_WearSkirt', base, samples, use_quads=use_quads)
    scene['cloth_topology'] = 'quads' if use_quads else 'triangles'
    scene['shape_guided'] = shape_guided
    scene['guide_weight'] = guide_weight if shape_guided else 0.0
    scene['cloth_object'] = cloth.name
    group = cloth.vertex_groups.new(name='WaistPin')
    reps = cloth['welded_representatives']
    top = max(p[1] for p in base['vertices'])
    for index, original in enumerate(reps):
        amount = max(0, min(1, (base['vertices'][original][1] - top + .045) / .025))
        if attachment:
            t = max(0, min(1, (base['vertices'][original][1] - release) / (low - release)))
            amount = t * t * (3 - 2 * t)
        if shape_guided:
            amount = max(amount, guide_weight)
        if amount > 0:
            group.add([index], amount, 'REPLACE')
    mod = cloth.modifiers.new('Native cloth wearing proof', 'CLOTH')
    settings = mod.settings
    settings.quality = quality
    area = sum(p.area for p in cloth.data.polygons)
    settings.mass = .24 * area / len(cloth.data.vertices)
    settings.vertex_group_mass = group.name
    settings.pin_stiffness = 20
    settings.tension_stiffness = 40
    settings.compression_stiffness = 40
    settings.shear_stiffness = 20
    settings.bending_stiffness = bending_stiffness
    settings.tension_damping = 8
    settings.compression_damping = 8
    settings.shear_damping = 8
    settings.bending_damping = 2
    settings.air_damping = 2
    settings.use_dynamic_mesh = shape_guided if dynamic_rest is None else dynamic_rest
    collision = mod.collision_settings
    collision.collision_quality = collision_quality
    collision.distance_min = .018 if coarse else .008
    collision.use_self_collision = True
    collision.self_distance_min = .008
    collision.self_friction = 3
    mod.point_cache.frame_start = 1
    mod.point_cache.frame_end = scene.frame_end
    scene['area_m2'] = area
    scene['last_simulated_frame'] = 0
    print(json.dumps({'scene': scene.name, 'cloth_vertices': len(cloth.data.vertices),
                      'source_vertices': len(base['vertices']), 'area': area,
                      'vertex_mass': settings.mass, 'original_scene_unchanged': scene['original_scene']}))
    return scene.name


def _cache_state(scene, require_end=False):
    cloth = bpy.data.objects[scene['cloth_object']]
    cache = next(m for m in cloth.modifiers if m.type == 'CLOTH').point_cache
    if cache.is_outdated or cache.is_frame_skip:
        raise ValueError('Cloth cache is outdated or skipped frames; restart and advance sequentially')
    if require_end and (scene.get('last_simulated_frame') != scene.frame_end or scene.frame_current != scene.frame_end):
        raise ValueError('Expected the completed final cloth frame')
    return {'is_outdated': cache.is_outdated, 'is_frame_skip': cache.is_frame_skip,
            'is_baked': cache.is_baked, 'frame': scene.frame_current,
            'last_sequential_frame': scene.get('last_simulated_frame', 0)}


def restart(scene_name):
    """Explicitly reset only this isolated experiment after changing its inputs."""
    scene = bpy.data.scenes[scene_name]
    PROOF_PATHS['scene_inputs'](PROJECT_ROOT, scene)
    cloth = bpy.data.objects[scene['cloth_object']]
    cache = next(m for m in cloth.modifiers if m.type == 'CLOTH').point_cache
    if cache.is_baked or cache.use_disk_cache or cache.use_external:
        raise ValueError('Refusing to reset a baked, disk or external cache')
    original = bpy.context.window.scene
    bpy.context.window.scene = scene
    try:
        scene['last_simulated_frame'] = 0
        scene.frame_set(cache.frame_start)
        cloth.evaluated_get(bpy.context.evaluated_depsgraph_get())
        _cache_state(scene)
        print(json.dumps({'scene': scene.name, 'restart_frame': scene.frame_current}))
    finally:
        bpy.context.window.scene = original


def advance(scene_name, end):
    scene = bpy.data.scenes[scene_name]
    if not isinstance(end, int) or not 1 <= end <= scene.frame_end:
        raise ValueError('Expected an end frame inside the simulation range')
    original = bpy.context.window.scene
    bpy.context.window.scene = scene
    try:
        if scene['last_simulated_frame'] > 0:
            _cache_state(scene)
            if scene.frame_current != scene['last_simulated_frame']:
                raise ValueError('Timeline moved outside sequential advancement; restart explicitly')
        for frame in range(scene['last_simulated_frame'] + 1, min(end, scene.frame_end) + 1):
            scene.frame_set(frame)
            graph = bpy.context.evaluated_depsgraph_get()
            cloth = bpy.data.objects[scene['cloth_object']].evaluated_get(graph)
            if not all(math.isfinite(v) for p in cloth.data.vertices for v in p.co):
                raise ValueError(f'Nonfinite simulation at frame {frame}')
            _cache_state(scene)
            scene['last_simulated_frame'] = frame
        print(json.dumps({'scene': scene.name, 'frame': scene['last_simulated_frame']}))
    finally:
        bpy.context.window.scene = original


def _containment(points, faces, data):
    # Close only the two boundary loops for a diagnostic volume, not rendering.
    edges = {}
    for face in faces:
        for a, b in zip(face, face[1:] + face[:1]):
            key = tuple(sorted((a, b)))
            edges[key] = edges.get(key, 0) + 1
    neighbors = {}
    for (a, b), count in edges.items():
        if count == 1:
            neighbors.setdefault(a, []).append(b)
            neighbors.setdefault(b, []).append(a)
    if any(len(values) != 2 for values in neighbors.values()):
        raise ValueError('Non-loop skirt boundary')
    capped_points, capped_faces, unseen = list(points), list(faces), set(neighbors)
    loops = 0
    while unseen:
        start = next(iter(unseen))
        loop, previous, current = [], None, start
        while current not in loop:
            loop.append(current)
            unseen.discard(current)
            next_vertex = next(v for v in neighbors[current] if v != previous)
            previous, current = current, next_vertex
        center = sum((points[i] for i in loop), Vector()) / len(loop)
        center_id = len(capped_points)
        capped_points.append(center)
        for a, b in zip(loop, loop[1:] + loop[:1]):
            capped_faces.append([a, b, center_id])
        loops += 1
    if loops != 2:
        raise ValueError('Expected two skirt openings')
    tree = BVHTree.FromPolygons(capped_points, capped_faces, all_triangles=False)
    directions = [Vector(v).normalized() for v in [(1,.173,.317),(.219,1,.413),(.387,.271,1)]]
    records = []
    for body_index, body in enumerate(data['body_parts']):
        if body['semantic'] not in ('legL', 'legR'):
            continue
        rows = {}
        for i, p in enumerate(body['rest_vertices']):
            if .35 <= p[1] <= 1.22:
                rows.setdefault(round(p[1], 4), []).append(i)
        actual = data['frames'][-1]['body_parts'][body_index]['vertices']
        for height, ids in sorted(rows.items()):
            point = sum((Vector(_xyz(actual[i])) for i in ids), Vector()) / len(ids)
            votes = []
            for direction in directions:
                cursor, hits = point.copy(), 0
                for _ in range(100):
                    location, _, _, _ = tree.ray_cast(cursor, direction)
                    if location is None:
                        break
                    hits += 1
                    cursor = location + direction * .00001
                votes.append(hits % 2 == 1)
            records.append({'part': body['semantic'], 'rest_height': height,
                            'inside_votes': sum(votes), 'inside': sum(votes) >= 2})
    return {'method': 'Three-ray parity of leg row centers; skirt openings virtually capped; self-intersections can invalidate parity',
            'inside': sum(p['inside'] for p in records), 'samples': len(records), 'rows': records}


def _render_surface(data, posed):
    base = data['base_skirt']
    representatives, mapping = _weld(base['vertices'])
    points = [Vector(_xyz(posed[i])) for i in representatives]
    faces = []
    for offset in range(0, len(base['indices']), 3):
        ids = base['indices'][offset:offset+3]
        a, b, c = (Vector(base['vertices'][i]) for i in ids)
        normal = sum((Vector(base['normals'][i]) for i in ids), Vector())
        if (b-a).cross(c-a).dot(normal) < 0:
            ids.reverse()
        faces.append([mapping[i] for i in ids])
    return points, faces, mapping


def _contacts(scene, graph, points, faces):
    tree = BVHTree.FromPolygons(points, faces, all_triangles=True)
    face_sets = [set(f) for f in faces]
    self_pairs = {(min(a, b), max(a, b)) for a, b in tree.overlap(tree)
                  if a != b and not face_sets[a].intersection(face_sets[b])}
    body_pairs = {}
    for obj in scene.objects:
        if not (obj.get('wear_body') or obj.get('wear_support')):
            continue
        mesh = obj.evaluated_get(graph).data
        other = BVHTree.FromPolygons([v.co for v in mesh.vertices],
                                    [list(p.vertices) for p in mesh.polygons], all_triangles=True)
        body_pairs[obj.name] = len(tree.overlap(other))
    return len(self_pairs), body_pairs


def audit_cached_frames(scene_name, output_tag='motion_audit', every_frame=False):
    scene = bpy.data.scenes[scene_name]
    if scene['last_simulated_frame'] != scene.frame_end:
        raise ValueError('Complete the sequential simulation before auditing its cache')
    source, support = PROOF_PATHS['scene_inputs'](PROJECT_ROOT, scene)
    if scene.get('cage_transfer'):
        raise ValueError('Motion audit currently requires original-topology simulation')
    output = PROOF_PATHS['checked_output'](PROJECT_ROOT, source, output_tag)
    data = json.loads(source.read_text(encoding='utf-8'))
    original, previous_frame = bpy.context.window.scene, scene.frame_current
    bpy.context.window.scene = scene
    records = []
    try:
        _cache_state(scene, require_end=True)
        cloth = bpy.data.objects[scene['cloth_object']]
        bodies = sorted((obj for obj in scene.objects if obj.get('wear_body')), key=lambda obj: obj.name)
        if len(bodies) != len(data['body_parts']):
            raise ValueError('Body part count changed')
        frame_numbers = range(1, scene.frame_end + 1) if every_frame else [sample['frame'] for sample in data['frames']]
        for frame in frame_numbers:
            scene.frame_set(frame)
            graph = bpy.context.evaluated_depsgraph_get()
            mesh = cloth.evaluated_get(graph).data
            _cache_state(scene)
            posed = [_godot(mesh.vertices[i].co) for i in cloth['original_to_welded']]
            if not all(math.isfinite(v) for p in posed for v in p):
                raise ValueError(f'Nonfinite cached mesh at frame {frame}')
            points, faces, _ = _render_surface(data, posed)
            self_pairs, body_pairs = _contacts(scene, graph, points, faces)
            body_sample = []
            for obj in bodies:
                body_mesh = obj.evaluated_get(graph).data
                body_sample.append({'vertices': [_godot(body_mesh.vertices[i].co)
                                                for i in obj['original_to_welded']]})
            contained = _containment(points, faces, {**data, 'frames': [{'body_parts': body_sample}]})
            records.append({'frame': frame, 'nonadjacent_self_pairs': self_pairs,
                            'body_triangle_pairs': body_pairs,
                            'leg_centers_inside': [contained['inside'], contained['samples']]})
        report = {'source': PROOF_PATHS['portable_reference'](PROJECT_ROOT, source), 'source_sha256': scene['source_sha256'],
                  'scene': scene.name, 'blender_version': bpy.app.version_string,
                  'post_simulation_finish': json.loads(scene['fold_finish']) if scene.get('fold_finish') else None,
                  'cache_validation': _cache_state(scene),
                  'support_source': PROOF_PATHS['portable_reference'](PROJECT_ROOT, support) if support else '',
                  'support_sha256': scene.get('support_sha256', ''),
                  'cloth_topology': scene.get('cloth_topology', 'triangles'),
                  'scope': 'Cached sampled frames, original render triangles; NOT continuous collision or full body volume containment',
                  'frames': records, 'samples': len(records),
                  'frames_with_contacts': sum(r['nonadjacent_self_pairs'] > 0 or any(r['body_triangle_pairs'].values()) for r in records)}
        output.write_text(json.dumps(report), encoding='utf-8')
        print(json.dumps({k: v for k, v in report.items() if k != 'frames'} | {
            'contact_frames': [{'frame': r['frame'], 'self': r['nonadjacent_self_pairs'],
                                'collider_pairs': sum(r['body_triangle_pairs'].values())}
                               for r in records if r['nonadjacent_self_pairs'] or any(r['body_triangle_pairs'].values())],
            'containment_failures': [r['frame'] for r in records if r['leg_centers_inside'][0] != r['leg_centers_inside'][1]],
            'output': str(output)}))
    finally:
        scene.frame_set(previous_frame)
        bpy.context.window.scene = original


def finish(scene_name, normal_smoothing=0, output_tag='native'):
    scene = bpy.data.scenes[scene_name]
    if scene['last_simulated_frame'] != 180:
        raise ValueError('Run all frames sequentially before exporting')
    source, support = PROOF_PATHS['scene_inputs'](PROJECT_ROOT, scene)
    output = PROOF_PATHS['checked_output'](PROJECT_ROOT, source, output_tag)
    data = json.loads(source.read_text(encoding='utf-8'))
    original = bpy.context.window.scene
    bpy.context.window.scene = scene
    try:
        graph = bpy.context.evaluated_depsgraph_get()
        cache_state = _cache_state(scene, require_end=True)
        cloth = bpy.data.objects[scene['cloth_object']]
        evaluated = cloth.evaluated_get(graph)
        posed = [_godot(evaluated.data.vertices[i].co) for i in cloth['original_to_welded']]
        inverse = data['frames'][-1]['cloth_inverse_skin_transforms']
        if scene.get('cage_transfer'):
            transfer = json.loads(scene['cage_transfer'])
            cage = runpy.run_path(str(Path(__file__).with_name('coarse_wearing_cage.py')))
            posed, unskinned = cage['transfer'](data, posed, transfer['base'], transfer['source'], transfer['render'])
        else:
            unskinned = [list(Matrix(t['basis_rows']) @ Vector(p) + Vector(t['origin']))
                         for p, t in zip(posed, inverse)]
        # Diagnose the original render triangles, not just the simulation cage.
        points, faces, mapping = _render_surface(data, posed)
        self_pairs, body_pairs = _contacts(scene, graph, points, faces)
        sums = [Vector() for _ in points]
        adjacency = [set() for _ in points]
        for a, b, c in faces:
            n = (points[b]-points[a]).cross(points[c]-points[a])
            for index in [a, b, c]:
                sums[index] += n
                adjacency[index].update(i for i in [a, b, c] if i != index)
        sums = [n.normalized() for n in sums]
        # Art-directed shading only: never move vertices or weaken contact checks.
        for _ in range(normal_smoothing):
            sums = [(n * .5 + sum((sums[j] for j in adjacency[i]), Vector()) * (.5 / len(adjacency[i]))).normalized()
                    if adjacency[i] else n for i, n in enumerate(sums)]
        normals = [_godot(sums[i].normalized()) for i in mapping]
        unskinned_normals = [list((Matrix(t['basis_rows']) @ Vector(n)).normalized())
                            for n, t in zip(normals, inverse)]
        cloth_modifier = next(m for m in cloth.modifiers if m.type == 'CLOTH')
        result = {'source_sha256': scene['source_sha256'], 'source': PROOF_PATHS['portable_reference'](PROJECT_ROOT, source),
                  'experimental_not_accepted': True, 'scene': scene.name,
                  'frame': scene.frame_current, 'area_m2': scene['area_m2'],
                  'blender_version': bpy.app.version_string,
                  'cloth_topology': scene.get('cloth_topology', 'triangles'),
                  'shape_guided': scene.get('shape_guided', False),
                  'waist_attachment': data.get('waist_attachment'),
                  'guide_weight': scene.get('guide_weight', .02 if scene.get('shape_guided') else 0.0),
                  'support_source': PROOF_PATHS['portable_reference'](PROJECT_ROOT, support) if support else '',
                  'support_sha256': scene.get('support_sha256', ''),
                  'normal_smoothing_only': normal_smoothing,
                  'post_simulation_finish': json.loads(scene['fold_finish']) if scene.get('fold_finish') else None,
                  'cache_validation': cache_state,
                  'cage_vertices': len(evaluated.data.vertices), 'render_vertices': len(posed),
                  'diagnostic_topology': 'original Godot render triangles, welded UV seam',
                  'solver': {k: getattr(cloth_modifier.settings, k) for k in
                             ['quality', 'mass', 'tension_stiffness', 'compression_stiffness',
                              'shear_stiffness', 'bending_stiffness', 'pin_stiffness', 'use_dynamic_mesh']},
                  'collision': {k: getattr(cloth_modifier.collision_settings, k) for k in
                                ['collision_quality', 'distance_min', 'use_self_collision', 'self_distance_min']},
                  'modifiers': [{'name': m.name, 'type': m.type} for m in cloth.modifiers],
                  'nonadjacent_self_pairs': self_pairs, 'body_triangle_pairs': body_pairs,
                  'leg_center_containment': _containment(points, faces, data),
                  'posed_vertices': posed, 'unskinned_vertices': unskinned,
                  'unskinned_normals': unskinned_normals}
        output.write_text(json.dumps(result), encoding='utf-8')
        summary = {k: v for k, v in result.items() if not k.endswith(('_vertices', '_normals')) and k != 'leg_center_containment'}
        summary['leg_centers_inside'] = [result['leg_center_containment']['inside'], result['leg_center_containment']['samples']]
        summary['output'] = str(output)
        print(json.dumps(summary))
    finally:
        bpy.context.window.scene = original
