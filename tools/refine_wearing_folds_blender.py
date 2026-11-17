"""Experimental local native finish, not a runtime cloth solver or accepted bake.

Derive a fixed rest-space neighborhood from intersecting cloth faces. Never move
fully pinned vertices. After installation call restart, advance to the last frame,
then finish and audit_cached_frames(every_frame=True). It invalidates the cache.
"""

import hashlib
import json
import math
from pathlib import Path
import runpy

import bpy
from mathutils.bvhtree import BVHTree


def install(scene_name, seed_frame=180, factor=.25, iterations=3, rings=4):
    if not math.isfinite(factor) or not 0 < factor <= .5:
        raise ValueError('Expected conservative smoothing factor in (0, .5]')
    if not isinstance(iterations, int) or not 1 <= iterations <= 6:
        raise ValueError('Expected 1..6 iterations')
    if not isinstance(rings, int) or not 1 <= rings <= 6:
        raise ValueError('Expected 1..6 neighborhood rings')
    helper = Path(__file__).with_name('simulate_wearing_blender.py')
    simulation = runpy.run_path(str(helper))
    scene = bpy.data.scenes[scene_name]
    if scene.get('last_simulated_frame') != scene.frame_end:
        raise ValueError('Complete the native simulation first')
    if not isinstance(seed_frame, int) or not 1 <= seed_frame <= scene.frame_end:
        raise ValueError('Seed frame outside completed cache')
    if scene.get('fold_finish'):
        raise ValueError('Finish already installed; do not compound smoothing')
    source, _ = simulation['PROOF_PATHS']['scene_inputs'](simulation['PROJECT_ROOT'], scene)
    data = json.loads(source.read_text(encoding='utf-8'))
    if scene.get('cage_transfer'):
        raise ValueError('Requires original cloth topology')
    original, previous_frame = bpy.context.window.scene, scene.frame_current
    bpy.context.window.scene = scene
    try:
        simulation['_cache_state'](scene, require_end=True)
        scene.frame_set(seed_frame)
        graph = bpy.context.evaluated_depsgraph_get()
        cloth = bpy.data.objects[scene['cloth_object']]
        native = next(m for m in cloth.modifiers if m.type == 'CLOTH')
        group = cloth.vertex_groups[native.settings.vertex_group_mass]
        pinned = {v.index for v in cloth.data.vertices
                  if any(g.group == group.index and g.weight >= 1 - 1e-6 for g in v.groups)}
        mesh = cloth.evaluated_get(graph).data
        posed = [simulation['_godot'](mesh.vertices[i].co) for i in cloth['original_to_welded']]
        points, faces, _ = simulation['_render_surface'](data, posed)
        tree = BVHTree.FromPolygons(points, faces, all_triangles=True)
        pairs = sorted({(min(a, b), max(a, b)) for a, b in tree.overlap(tree)
                        if a != b and not set(faces[a]).intersection(faces[b])})
        neighbors = [set() for _ in points]
        for face in faces:
            for v in face:
                neighbors[v].update(i for i in face if i != v)
        distances = {v: 0 for a, b in pairs for f in (faces[a], faces[b]) for v in f if v not in pinned}
        if not distances:
            raise ValueError('No unpinned intersections to refine')
        for level in range(1, rings + 1):
            frontier = [v for v, depth in distances.items() if depth == level - 1]
            for v in frontier:
                for neighbor in neighbors[v]:
                    if neighbor not in distances and neighbor not in pinned:
                        distances[neighbor] = level
        weights = {v: 1 - depth / (rings + 1) for v, depth in distances.items()}
        local = cloth.vertex_groups.new(name='ExperimentalFoldNeighborhood')
        for vertex, weight in weights.items():
            local.add([vertex], weight, 'REPLACE')
        modifier = cloth.modifiers.new('Experimental local fold finish', 'CORRECTIVE_SMOOTH')
        modifier.vertex_group = local.name
        for prop, value in (('rest_source', 'ORCO'), ('smooth_type', 'LENGTH_WEIGHTED')):
            allowed = {item.identifier for item in modifier.bl_rna.properties[prop].enum_items}
            if value not in allowed:
                cloth.modifiers.remove(modifier)
                cloth.vertex_groups.remove(local)
                raise ValueError('Unsupported Blender enum: ' + prop)
            setattr(modifier, prop, value)
        modifier.use_only_smooth = True
        modifier.use_pin_boundary = True
        modifier.factor = factor
        modifier.iterations = iterations
        report = {'experimental_not_accepted': True, 'seed_frame': seed_frame,
                  'scope': 'Fixed rest-space neighborhood, derived from seed-frame self contacts. Full motion and visual checks still required.',
                  'seed_pairs': pairs, 'factor': factor, 'iterations': iterations, 'rings': rings,
                  'weights': weights, 'fully_pinned_vertices': sorted(pinned),
                  'source_sha256': scene['source_sha256'],
                  'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  'modifier': modifier.name, 'group': local.name}
        scene['fold_finish'] = json.dumps(report)
        scene['last_simulated_frame'] = 0
        print(json.dumps({k: v for k, v in report.items() if k not in ('weights', 'fully_pinned_vertices')} |
                         {'scene': scene.name, 'affected_vertices': len(weights), 'fixed_vertices': len(pinned)}))
        return report
    finally:
        scene.frame_set(previous_frame)
        bpy.context.window.scene = original
