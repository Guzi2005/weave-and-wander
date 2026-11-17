"""Run in Blender via MCP. Bake the existing skirt, not a replacement garment."""
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path('D:/workspace/weave-and-wander')
INPUT = json.loads((ROOT / 'captures/rest_cloth_input.json').read_text())


def blender_point(p):
    return Vector((p[0], -p[2], p[1]))


def material(name, color):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    node = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Roughness'].default_value = .85
    return mat


def mesh_object(scene, name, vertices, faces, mat=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    if mat:
        mesh.materials.append(mat)
    return obj


def collision(obj):
    obj.modifiers.new('Cloth contact', 'COLLISION')
    obj.collision.thickness_outer = .009
    obj.collision.thickness_inner = .004
    obj.collision.cloth_friction = 8


def capsule(scene, name, a, b, radius, mat):
    axis = b-a
    axis.normalize()
    side = axis.cross(Vector((0, 0, 1))).normalized()
    if side.length < .1:
        side = Vector((1, 0, 0))
    across = axis.cross(side)
    vertices = []
    for t, r in [(-.05, .35), (0, .85), (.18, 1), (.82, 1), (1, .85), (1.05, .35)]:
        for i in range(16):
            angle = i*math.tau/16
            vertices.append(a.lerp(b, t)+radius*r*(math.cos(angle)*side+math.sin(angle)*across))
    faces = [(j*16+i, j*16+(i+1)%16, (j+1)*16+(i+1)%16, (j+1)*16+i)
             for j in range(5) for i in range(16)]
    faces += [tuple(reversed(range(16))), tuple(range(80, 96))]
    obj = mesh_object(scene, name, vertices, faces, mat)
    collision(obj)
    return obj


def setup(variant=0):
    name = 'RestClothStudy_%d' % variant
    if name in bpy.data.scenes:
        raise RuntimeError('Study already exists; inspect it before replacing anything: '+name)
    scene = bpy.data.scenes.new(name)
    bpy.context.window.scene = scene
    scene.frame_end = 100
    scene.render.fps = 30
    scene.gravity = (0, 0, -9.81)
    pose = INPUT['variants'][variant]
    green = material('RestCloth study fabric', (.28, .48, .34))
    skin = material('RestCloth study legs', (.64, .40, .24))
    seat = material('RestCloth study cushion', (.65, .68, .63))
    lo, hi = (-1.84, -.505, .60), (1.84, .505, INPUT['seat_top'])
    verts = [(x, y, z) for z in (lo[2], hi[2]) for y in (lo[1], hi[1]) for x in (lo[0], hi[0])]
    faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    collision(mesh_object(scene, 'Cushion', verts, faces, seat))
    bones = {key: blender_point(value) for key, value in pose['bones'].items()}
    for side in ('L', 'R'):
        capsule(scene, 'Thigh '+side, bones['Thigh'+side], bones['Shin'+side], .105, skin)
    capsule(scene, 'Pelvis', bones['ThighL'], bones['ThighR'], .19, skin)
    for index, source in enumerate(pose['colliders']):
        triangles = source['triangles']
        faces = [tuple(triangles[i:i+3]) for i in range(0, len(triangles), 3)]
        obj = mesh_object(scene, source['name']+str(index), [blender_point(p) for p in source['vertices']], faces, skin)
        collision(obj)
    # Weld the lathe seam. Original vertex order remains recorded for Godot sampling.
    ids = [ring*41+i for ring in range(8) for i in range(40)]
    faces = [(ring*40+i, ring*40+(i+1)%40, (ring+1)*40+(i+1)%40, (ring+1)*40+i)
             for ring in range(7) for i in range(40)]
    skirt = mesh_object(scene, 'GravitySkirt', [blender_point(pose['posed'][i]) for i in ids], faces, green)
    skirt.shape_key_add(name='Basis')
    rest = skirt.shape_key_add(name='Standing cut, length preserved')
    for target, index in zip(rest.data, ids):
        target.co = blender_point(pose['rest'][index])
    pins = skirt.vertex_groups.new(name='Waist seam')
    pins.add(list(range(7*40, 8*40)), 1, 'REPLACE')
    pins.add(list(range(4*40, 7*40)), 1, 'REPLACE')
    pins.add(list(range(3*40, 4*40)), .7, 'REPLACE')
    cloth = skirt.modifiers.new('Gravity drape', 'CLOTH')
    settings = cloth.settings
    settings.quality = 12
    settings.mass = .20
    settings.vertex_group_mass = pins.name
    # The authored pose supplies garment ease. Preserve it above the knees;
    # this solve supplies gravitational settling below them, not a new silhouette.
    settings.tension_stiffness = 30
    settings.compression_stiffness = 30
    settings.shear_stiffness = 12
    settings.bending_stiffness = 2
    settings.air_damping = 5
    settings.tension_damping = 12
    settings.compression_damping = 12
    settings.bending_damping = 2
    settings.pin_stiffness = 1
    cloth.collision_settings.use_collision = True
    cloth.collision_settings.distance_min = .009
    cloth.collision_settings.collision_quality = 6
    cloth.collision_settings.use_self_collision = True
    cloth.collision_settings.self_distance_min = .008
    cloth.point_cache.frame_end = 100
    scene.frame_set(1)
    print('READY', scene.name, len(skirt.data.vertices))


def advance(last_frame):
    scene = bpy.context.scene
    obj = next(o for o in scene.objects if o.name.startswith('GravitySkirt'))
    for frame in range(scene.frame_current+1, last_frame+1):
        scene.frame_set(frame)
        obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    print('FRAME', scene.frame_current)


def export(variant=0):
    scene = bpy.context.scene
    obj = next(o for o in scene.objects if o.name.startswith('GravitySkirt'))
    mesh = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    inverse = INPUT['variants'][variant]['root_inverse']
    basis = [Vector(p) for p in inverse]
    points = []
    for vertex in mesh.vertices:
        p = vertex.co
        world = Vector((p.x, p.z, -p.y))
        local = basis[3]+basis[0]*world.x+basis[1]*world.y+basis[2]*world.z
        points.append(list(local))
    obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    output = ROOT / 'art_source/rest_cloth'
    output.mkdir(exist_ok=True, parents=True)
    (output / ('nap_%d.json' % variant)).write_text(json.dumps({'rings': [INPUT['variants'][variant]['rest'][i*41][1] for i in range(8)], 'segments':40, 'points':points}, separators=(',', ':')))
    print('EXPORTED', variant, len(points))


def export_gravity_resource():
    samples = []
    for variant in range(4):
        scene = bpy.data.scenes['RestClothStudy_%d' % variant]
        bpy.context.window.scene = scene
        obj = next(o for o in scene.objects if o.name.startswith('GravitySkirt')).evaluated_get(bpy.context.evaluated_depsgraph_get())
        source = INPUT['variants'][variant]
        for ring in range(8):
            offsets = [max(-.14, min(.035, obj.data.vertices[ring*40+i].co.z-source['posed'][ring*41+i][1]))*.75 for i in range(40)]
            # Broad folds suit the existing printed doll; remove collision-scale noise.
            for _ in range(3):
                offsets = [(offsets[(i-1)%40]+2*offsets[i]+offsets[(i+1)%40])*.25 for i in range(40)]
            samples.extend(offsets)
    output = ROOT / 'assets/rest_cloth'
    output.mkdir(exist_ok=True, parents=True)
    text = '[gd_resource type="Resource" script_class="NapDrapeData" load_steps=2 format=3]\n\n'
    text += '[ext_resource type="Script" path="res://scripts/nap_drape_data.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    text += 'offsets = PackedFloat32Array('+','.join('%.6f' % n for n in samples)+')\n'
    (output / 'nap_gravity.tres').write_text(text)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art_source/rest_cloth/rest_drape_study.blend'), copy=True)
    print('GRAVITY_RESOURCE', len(samples), 'frame', bpy.context.scene.frame_current)
