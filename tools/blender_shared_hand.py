"""Continuous palm and thumb, authored through the live Blender MCP."""
import bpy,json
from pathlib import Path
scene=bpy.data.scenes.new('Shared doll hand')
bpy.context.window.scene=scene
pieces=[]
for center,radius in [((0,0,0),(.09,.132,.087)),((-.060,.022,.033),(.049,.070,.052)),((-.090,.051,.047),(.030,.042,.034))]:
    x,y,z=center
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=16,location=(x,-z,y))
    ob=bpy.context.object;ob.scale=(radius[0],radius[2],radius[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    pieces.append(ob)
for ob in pieces:ob.select_set(True)
bpy.context.view_layer.objects.active=pieces[0]
bpy.ops.object.join()
ob=bpy.context.object
rem=ob.modifiers.new('Joined thumb web','REMESH');rem.mode='VOXEL';rem.voxel_size=.003
bpy.ops.object.modifier_apply(modifier=rem.name)
sm=ob.modifiers.new('Palm transition','SMOOTH');sm.factor=.85;sm.iterations=8
bpy.ops.object.modifier_apply(modifier=sm.name)
dec=ob.modifiers.new('Game mesh','DECIMATE');dec.ratio=.18
bpy.ops.object.modifier_apply(modifier=dec.name)
ob.data.calc_loop_triangles()
data={'vertices':[(v.co.x,v.co.z,-v.co.y) for v in ob.data.vertices],
      'normals':[(v.normal.x,v.normal.z,-v.normal.y) for v in ob.data.vertices],
      'indices':[i for t in ob.data.loop_triangles for i in reversed(t.vertices)]}
root=Path(r'D:/workspace/weave-and-wander')
(root/'assets/shared_hand.json').write_text(json.dumps(data))
bpy.ops.wm.save_as_mainfile(filepath=str(root/'Docs/ukrainian-model/shared-hand.blend'))
print('SHARED_HAND',len(data['vertices']))
