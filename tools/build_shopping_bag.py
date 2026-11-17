"""Reusable open paper carrier, authored in Blender without touching other collections."""
import bpy
import math
from pathlib import Path

OUT = Path('D:/workspace/weave-and-wander/assets/models')
name = 'WW_ShoppingBag'
old = bpy.data.collections.get(name)
if old:
    for obj in list(old.objects): bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(old)
collection = bpy.data.collections.new(name)
bpy.context.scene.collection.children.link(collection)
root = bpy.data.objects.new('ShoppingBag', None)
collection.objects.link(root)

def mat(label, color):
    material = bpy.data.materials.new(label)
    material.use_nodes = True
    node = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Roughness'].default_value = .93
    material.diffuse_color = (*color, 1)
    return material

paper = mat('Bag_UncoatedPaper', (.77,.72,.56))
ink = mat('Bag_GreenInk', (.19,.38,.32))
inside = mat('Bag_InnerPaper', (.64,.59,.44))

def mesh(label, verts, faces, material):
    data = bpy.data.meshes.new(label)
    data.from_pydata([(x,-z,y) for x,y,z in verts], [], faces)
    data.update()
    uv = data.uv_layers.new(name='PaperUV')
    for polygon in data.polygons:
        normal_axis = max(range(3), key=lambda axis: abs(polygon.normal[axis]))
        axes = [axis for axis in range(3) if axis != normal_axis]
        for loop in polygon.loop_indices:
            point = data.vertices[data.loops[loop].vertex_index].co
            uv.data[loop].uv = (point[axes[0]]+.5, point[axes[1]]+.5)
    obj = bpy.data.objects.new(label, data)
    collection.objects.link(obj)
    obj.parent = root
    obj.data.materials.append(material)
    return obj

# The side profile follows the straight lines from a broad base to the grip.
levels = [0, .075, .11, .46, .64]
verts = []
for y in levels:
    verts.extend([(-.35,y,-.18),(0,y,-.18),(.35,y,-.18),(.35,y,0),
                  (.35,y,.18),(0,y,.18),(-.35,y,.18),(-.35,y,0)])
faces = [(j*8+i,(j+1)*8+i,(j+1)*8+(i+1)%8,j*8+(i+1)%8)
         for j in range(len(levels)-1) for i in range(8)]
faces.append(tuple(range(8)))
body = mesh('CreasedPaperBody', verts, faces, paper)
body.data.materials.append(ink)
for poly in body.data.polygons:
    # Ink belongs to the paper faces, with no separate protruding border mesh.
    if 8 <= poly.index < 16 and poly.index % 8 in (0,1,4,5):
        poly.material_index = 1
solid = body.modifiers.new('Paper thickness', 'SOLIDIFY')
solid.thickness = .006
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier=solid.name)
def carried_shape(obj, handle=False):
    obj.shape_key_add(name='Basis')
    key = obj.shape_key_add(name='Carried')
    for point in key.data:
        y = point.co.z
        point.co.y *= max(0, 1-y/.88)
        if not handle and abs(point.co.y) < .001 and abs(point.co.x) > .34:
            point.co.x *= 1-.12*(y/.64)

carried_shape(body)

for side in (-1, 1):
    # Handles are flat folded cotton tape, not torus or stock tube loops.
    verts=[]
    for i in range(21):
        t=i/20
        x=-.145*math.cos(math.pi*t)
        y=.59+.29*math.sin(math.pi*t)
        dx=.145*math.pi*math.sin(math.pi*t)
        dy=.29*math.pi*math.cos(math.pi*t)
        length=math.hypot(dx,dy)
        nx,ny=-dy/length*.013,dx/length*.013
        verts.extend([(x+nx,y+ny,side*.181),(x-nx,y-ny,side*.181)])
    handle=mesh('CottonTapeHandle',verts,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(20)],ink)
    solid=handle.modifiers.new('Tape thickness','SOLIDIFY'); solid.thickness=.005
    bpy.context.view_layer.objects.active=handle
    bpy.ops.object.modifier_apply(modifier=solid.name)
    carried_shape(handle, True)
    for x in (-.145,.145):
        anchor=mesh('HandleAnchor',[(x-.026,.56,side*.181),(x+.026,.56,side*.181),(x+.026,.62,side*.181),(x-.026,.62,side*.181)],[(0,1,2,3)],inside)
        carried_shape(anchor)

bpy.ops.object.select_all(action='DESELECT')
for obj in collection.objects: obj.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=str(OUT/'shopping_bag.glb'),export_format='GLB',use_selection=True,export_apply=False)
print('Exported',len(collection.objects),'objects: shopping_bag.glb')
