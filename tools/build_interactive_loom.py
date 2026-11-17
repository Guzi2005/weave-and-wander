"""Run in Blender through MCP. Only touches its own named collection."""
import bpy
import math
from pathlib import Path
from mathutils import Vector

OUT = Path('D:/workspace/weave-and-wander/assets/models')
OUT.mkdir(parents=True, exist_ok=True)
name = 'WW_InteractiveLoom'
old = bpy.data.collections.get(name)
if old:
    for obj in list(old.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(old)
collection = bpy.data.collections.new(name)
bpy.context.scene.collection.children.link(collection)

def point(v):
    return Vector((v[0], -v[2], v[1]))

def material(label, color):
    mat = bpy.data.materials.new(label)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = .84
    mat.diffuse_color = (*color, 1)
    return mat

wood = material('Loom_Walnut', (.26,.16,.10))
edge = material('Loom_PolishedEdges', (.43,.28,.15))
metal = material('Loom_BrassPins', (.52,.37,.15))
thread = material('Loom_UnbleachedCotton', (.77,.74,.62))
shuttle_mat = material('Loom_ShuttleRed', (.48,.16,.17))

def own(obj, label, parent=None, mat=wood):
    for owner in list(obj.users_collection): owner.objects.unlink(obj)
    collection.objects.link(obj)
    obj.name = label
    if parent:
        transform = obj.matrix_world.copy()
        obj.parent = parent
        obj.matrix_world = transform
    if obj.type == 'MESH':
        obj.data.materials.append(mat)
    return obj

def pivot(label, at):
    obj = bpy.data.objects.new(label, None)
    collection.objects.link(obj)
    obj.location = point(at)
    bpy.context.view_layer.update()
    return obj

def box(label, size, at, parent=None, mat=wood, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=point(at))
    obj = own(bpy.context.object, label, None, mat)
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new('Soft crafted edges', 'BEVEL')
    mod.width = min(bevel, min(size)*.2)
    mod.segments = 3
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    if parent:
        bpy.context.view_layer.update()
        transform=obj.matrix_world.copy()
        obj.parent=parent
        obj.matrix_world=transform
    return obj

def rod(label, a, b, radius, parent=None, mat=wood, segments=24):
    a,b = point(a),point(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius, depth=(b-a).length, location=(a+b)*.5)
    obj=own(bpy.context.object,label,None,mat)
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    mod=obj.modifiers.new('Turned rim','BEVEL'); mod.width=radius*.12; mod.segments=2
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for face in obj.data.polygons: face.use_smooth=True
    if parent:
        bpy.context.view_layer.update()
        transform=obj.matrix_world.copy(); obj.parent=parent; obj.matrix_world=transform
    return obj

for x in (-1.12,1.12):
    box('Foot',(.22,.14,1.54),(x,.10,0),mat=edge)
    for z in (-.57,.57):
        box('MortisedLeg',(.15,1.28,.18),(x,.72,z))
    box('SideRail',(.18,.20,1.48),(x,1.29,0),mat=edge)
    box('ShaftPost',(.14,.76,.14),(x,1.70,-.08))
    for y in (.38,1.17):
        rod('JoineryPeg',(x-.105,y,.57),(x+.105,y,.57),.038,mat=metal)
box('LowerStretcher',(2.32,.12,.16),(0,.36,-.52))
box('CastleBeam',(2.42,.13,.18),(0,2.08,-.08),mat=edge)
rod('BackBeam',(-1.24,1.44,-.63),(1.24,1.44,-.63),.105,mat=edge)
rod('FrontBreastBeam',(-1.23,1.27,.68),(1.23,1.27,.68),.10,mat=edge)

roller=pivot('ClothRollPivot',(0,.96,.55))
rod('ClothRollCore',(-1.26,.96,.55),(1.26,.96,.55),.105,roller,edge)
for x in (-1.32,1.32):
    rod('RatchetWheel',(x-.035,.96,.55),(x+.035,.96,.55),.22,roller,edge,32)
    for tooth in range(12):
        angle=tooth*math.tau/12
        box('RatchetTooth',(.09,.065,.065),(x,.96+math.cos(angle)*.22,.55+math.sin(angle)*.22),roller,metal,.012)
rod('Crank', (1.39,.96,.55),(1.39,1.16,.55),.045,roller,metal)
rod('CrankGrip',(1.36,1.16,.55),(1.58,1.16,.55),.055,roller,edge)

beater=pivot('BeaterPivot',(0,1.31,.12))
for x in (-.99,.99): box('ReedSide',(.09,.64,.10),(x,1.40,.12),beater,edge)
for y in (1.10,1.70): box('ReedBar',(2.06,.085,.10),(0,y,.12),beater,edge)
for x in (-.40,.40): rod('BeaterReachArm',(x,1.70,.12),(x,1.70,.66),.027,beater,edge)
rod('BeaterHandGrip',(-.50,1.70,.66),(.50,1.70,.66),.032,beater,edge)
for i in range(53):
    box('ReedDent',(.009,.51,.014),(-.94+i*.036,1.40,.12),beater,metal,.001)

for index,z in enumerate((-.18,-.36)):
    heddle=pivot('Heddle%d'%index,(0,1.39,z))
    for y in (1.11,1.68): box('HeddleRail',(2.01,.045,.045),(0,y,z),heddle,edge)
    for i in range(26): rod('HeddleCord',(-.90+i*.072,1.13,z),(-.90+i*.072,1.66,z),.006,heddle,thread,6)
    treadle=pivot('Treadle%d'%index,(-.23+index*.46,.22,-.2))
    box('TreadleBoard',(.18,.055,1.22),(-.23+index*.46,.22,.30),treadle,edge)

shuttle=pivot('ShuttlePivot',(0,1.37,.38))
# Lenticular boat outline, an actual open bobbin pocket, and rounded tapered tips.
ring=[(-.29,0),(-.20,-.055),(.20,-.055),(.29,0),(.20,.055),(-.20,.055)]
verts=[]
for height in (-.025,.025):
    verts += [tuple(point((x,1.37+height,.38+z))) for x,z in ring]
faces=[tuple(range(5,-1,-1)),tuple(range(6,12))]
faces += [(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)]
mesh=bpy.data.meshes.new('BoatShuttleMesh'); mesh.from_pydata(verts,[],faces); mesh.update()
obj=bpy.data.objects.new('BoatShuttle',mesh); collection.objects.link(obj); obj.data.materials.append(shuttle_mat)
obj.parent=shuttle; obj.matrix_parent_inverse=shuttle.matrix_world.inverted()
bpy.context.view_layer.objects.active=obj; obj.select_set(True)
mod=obj.modifiers.new('Shuttle edge bevel','BEVEL');mod.width=.018;mod.segments=3
bpy.ops.object.modifier_apply(modifier=mod.name)
rod('ShuttleBobbin',(-.12,1.405,.38),(.12,1.405,.38),.029,shuttle,thread)

bpy.context.view_layer.update()
root = pivot('InteractiveLoom',(0,0,0))
for obj in list(collection.objects):
    if obj != root and obj.parent is None:
        obj.parent=root
bpy.ops.object.select_all(action='DESELECT')
for obj in collection.objects: obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'interactive_loom.glb'),use_selection=True,export_apply=True)
(OUT/'source').mkdir(exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source'/'interactive_loom.blend'))
print('LOOM_EXPORTED',len(collection.objects),'objects',sum(len(o.data.polygons) for o in collection.objects if o.type=='MESH'),'faces')
