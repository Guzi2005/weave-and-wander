"""Executed in live Blender after export_mosuo_assets.gd.

Retains the editable cloth construction collection and imports the exact game rig
as a separate output collection. No reference evidence is replaced by this output.
"""
import bpy,json,struct,pathlib
ROOT=pathlib.Path(r'D:\workspace\weave-and-wander')
source=ROOT.parent/'W&W Wiki/public/assets/models/mosuo_ensemble.glb'
blob=source.read_bytes(); length=struct.unpack_from('<I',blob,12)[0]
doc=json.loads(blob[20:20+length])
def integers(value):
    if isinstance(value,dict): return {k:integers(v) for k,v in value.items()}
    if isinstance(value,list): return [integers(v) for v in value]
    if isinstance(value,float) and value.is_integer(): return int(value)
    return value
doc=integers(doc)
# Blender 4.2 predates this visibility extension; apply it after import.
hidden=[n.get('name') for n in doc.get('nodes',[]) if n.get('extensions',{}).get('KHR_node_visibility',{}).get('visible') is False]
for key in ('extensionsUsed','extensionsRequired'):
    doc[key]=[x for x in doc.get(key,[]) if x!='KHR_node_visibility']
for node in doc.get('nodes',[]): node.get('extensions',{}).pop('KHR_node_visibility',None)
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=blob[20+length:]
compat=ROOT/'captures/mosuo_blender_import.glb'
compat.write_bytes(struct.pack('<III',0x46546C67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+tail)
old=bpy.data.collections.get('WW_GamePreview')
if old:
    for obj in list(old.objects): bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.collections.remove(old)
for obj in list(bpy.data.objects):
    if obj.name!='WW_Reference_Photo': obj.hide_set(True);obj.hide_render=True
    # Source sockets from a prior inspection were in the wrong coordinate frame.
    if obj.name in ('CrownFlowerSocket','OccipitalTasselSocket','InsoleGripSocket'):
        bpy.data.objects.remove(obj,do_unlink=True)
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(compat))
new=set(bpy.data.objects)-before
collection=bpy.data.collections.new('WW_GamePreview');bpy.context.scene.collection.children.link(collection)
for obj in new:
    for owner in list(obj.users_collection): owner.objects.unlink(obj)
    collection.objects.link(obj)
    if any(obj.name==name or obj.name.startswith(name+'.') for name in hidden): obj.hide_set(True);obj.hide_render=True
    obj['ww_stage']='exported_game_adaptation'
    obj['ww_recipe_scene']='scenes/mosuo_adornment_authoring.tscn'
    if obj.type=='MESH':
        for face in obj.data.polygons: face.use_smooth=True
bpy.context.scene.frame_set(1)
armature=next(o for o in new if o.type=='ARMATURE')
armature.name='WW_CurrentGameRig'
for bone in armature.pose.bones:
    if bone.custom_shape:
        bone.custom_shape.hide_set(True); bone.custom_shape.hide_render=True
# Leave a useful full-body viewpoint when the file opens.
from mathutils import Quaternion,Vector
for area in (bpy.context.screen.areas if bpy.context.screen else []):
    if area.type=='VIEW_3D':
        space=area.spaces.active;space.region_3d.view_distance=4.4
        space.region_3d.view_location=Vector((0,0,1.5))
        space.region_3d.view_rotation=Quaternion((1,0,0),1.5708)
        space.shading.type='MATERIAL'
out=ROOT/'assets/collections/mosuo_photo_001/mosuo_photo_001.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(out))
print('BLENDER_GAME_SYNC',len(new),'objects',len(armature.data.bones),'bones','hidden',hidden)
