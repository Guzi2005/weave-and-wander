"""Rebuild the outer craft studio from empty. One Godot unit = 2 cm here.

Coordinates passed to helpers use Y-up. External CC0 sources: sources.json.
Blender 4.2: --background --python tools/build_workbench.py
"""
import bpy
import math
import random
import bmesh
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "workbench"
TEX = ASSETS / "textures"
random.seed(161016)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = .02


def v(point):
    return Vector((point[0], -point[2], point[1]))


def linear(hex_color):
    channels = [int(hex_color[i:i+2], 16)/255 for i in (0, 2, 4)]
    return tuple(c/12.92 if c < .04045 else ((c+.055)/1.055)**2.4 for c in channels)+(1,)


def material(name, color, rough=.5, metal=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = linear(color)
    shader.inputs["Roughness"].default_value = rough
    shader.inputs["Metallic"].default_value = metal
    mat.diffuse_color = linear(color)
    return mat


def textured(name, prefix, resolution, color="ffffff", diffuse=True, strength=.3):
    mat = material(name, color, .65)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    for suffix, channel in [("diff", "Base Color"), ("rough", "Roughness"), ("nor_gl", "Normal")]:
        if suffix == "diff" and not diffuse:
            continue
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(TEX/f"{prefix}_{suffix}_{resolution}.jpg"), check_existing=True)
        if suffix != "diff":
            tex.image.colorspace_settings.name = "Non-Color"
        if suffix == "nor_gl":
            normal = nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value = strength
            links.new(tex.outputs["Color"], normal.inputs["Color"])
            links.new(normal.outputs["Normal"], shader.inputs["Normal"])
        else:
            links.new(tex.outputs["Color"], shader.inputs[channel])
    return mat


# The studio furniture uses a restrained, matte black-walnut veneer.  Keeping
# this in the source builder makes rebuilds reproduce the approved material.
oak = textured("Studio_MatteBlackWalnut", "black_walnut_veneer_02", "2k", "765548", strength=.10)
light_oak = textured("Studio_MatteBlackWalnutSecondary", "black_walnut_veneer_02", "2k", "62463b", strength=.10)
plaster = textured("Studio_ChalkPlaster", "white_plaster_02", "1k", "e4e1d7", False, .2)
linen = textured("Studio_NaturalLinen", "rough_linen", "1k", "d9d9c9", False, .35)
cloth = [textured("Studio_Cloth_"+str(i), "rough_linen", "1k", c, False, .36)
         for i,c in enumerate(["688b87", "a85d64", "a4a967", "e3d5bd"])]
metal = material("Studio_PowderCoatedSteel", "252f30", .38, .65)
steel = material("Studio_SatinSteel", "bac3c5", .22, .86)
ruler_steel = material("Studio_RulerSteel", "bac3c5", .22, .86)
brass = material("Studio_Brass", "b19b63", .31, .8)
mat_rubber = material("Studio_CuttingMat", "376963", .86)
ceramic = material("Studio_Ceramic", "d1d7c4", .21)
soil = material("Garden_Earth", "536247", 1)
thread_mats = [material("Studio_Thread_"+str(i), c, .9) for i,c in enumerate(["b45c64", "ceaf78", "597d86", "b7bf94", "6e5d71"])]


def finish(obj, name, mat, smooth=False):
    obj.name = name
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = smooth
    return obj


def planar_uv(obj, repeat):
    uv = obj.data.uv_layers.active or obj.data.uv_layers.new()
    for face in obj.data.polygons:
        axis = max(range(3), key=lambda i: abs(face.normal[i]))
        axes = [i for i in range(3) if i != axis]
        for loop_id in face.loop_indices:
            point = obj.data.vertices[obj.data.loops[loop_id].vertex_index].co
            uv.data[loop_id].uv = (point[axes[0]]/repeat, point[axes[1]]/repeat)


def box(name, at, size, mat, bevel=.04, angle=0, repeat=20):
    bpy.ops.mesh.primitive_cube_add(size=1, location=v(at))
    obj = bpy.context.object
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    planar_uv(obj, repeat)
    obj.rotation_euler.z = angle
    if bevel:
        mod = obj.modifiers.new("Edge roundover", "BEVEL")
        mod.width, mod.segments = bevel, 1
        mod = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
    return finish(obj, name, mat)


def lathe(name, at, profile, mat, segments=32):
    vertices = [(r*math.cos(i*math.tau/segments), r*math.sin(i*math.tau/segments), h)
                for r,h in profile for i in range(segments)]
    faces = []
    for row in range(len(profile)-1):
        for i in range(segments):
            j = (i+1) % segments
            faces.append((row*segments+i,row*segments+j,(row+1)*segments+j,(row+1)*segments+i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = v(at)
    uv = mesh.uv_layers.new()
    for face in mesh.polygons:
        for loop_id in face.loop_indices:
            idx = mesh.loops[loop_id].vertex_index
            uv.data[loop_id].uv = (idx % segments/segments, idx//segments/max(len(profile)-1,1))
    return finish(obj,name,mat,True)


def curve(name, points, radius, mat, cyclic=False):
    data = bpy.data.curves.new(name,"CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = 1
    spline = data.splines.new("POLY")
    spline.points.add(len(points)-1)
    for p,co in zip(spline.points,points):
        p.co = (*v(co),1)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(mat)
    return obj


_asset_cache = {}

# Per-asset triangle budgets (per mesh object) for the stylised colour-block shader.
# Scanned micro-relief is flattened by the 3-band lighting, so these are visually lossless.
PROP_TRI_BUDGET = {
    "book_encyclopedia_set_01": 700,
    "desk_lamp_arm_01": 7500,
    "potted_plant_02": 2000,
    "wicker_basket_02": 2500,
}
DEFAULT_PROP_TRI_BUDGET = 4000
TREE_BRANCH_TRI_BUDGET = 6000


def tri_count(obj):
    # Planar dissolve leaves n-gons, so count triangles rather than polygons.
    return sum(len(p.vertices)-2 for p in obj.data.polygons)


def decimate_to(obj, target, label="LOD decimate"):
    bpy.context.view_layer.objects.active = obj
    for _ in range(3):
        current = tri_count(obj)
        if current <= target*1.05:
            break
        mod = obj.modifiers.new(label, "DECIMATE")
        mod.ratio = max(target/current, .01)
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)


def simplify_leaf_density(obj):
    indices = {i for i,m in enumerate(obj.data.materials) if "leaves" in m.name}
    if not indices:
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    seen, removed, leaves = set(), [], []
    rng = random.Random(17016)
    for face in bm.faces:
        if face.material_index not in indices or face in seen:
            continue
        stack, island = [face], []
        seen.add(face)
        while stack:
            current = stack.pop()
            island.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.material_index in indices and other not in seen:
                        seen.add(other)
                        stack.append(other)
        removed.extend(island)
        if rng.random() < .04:
            vertices = {vertex for f in island for vertex in f.verts}
            center = sum((vertex.co for vertex in vertices),Vector())/len(vertices)
            tip = max(vertices, key=lambda vertex: (vertex.co-center).length)
            axis = (tip.co-center).normalized()
            normal = sum((f.normal for f in island),Vector()).normalized()
            if abs(normal.dot(axis)) > .9 or normal.length < .1:
                normal = axis.cross(Vector((0,0,1))).normalized()
            side = normal.cross(axis).normalized()
            length = max((tip.co-center).length*3.4, .035)
            # One leaf per sampled island at sqrt(2) scale keeps the same crown coverage
            # (area) as the former pair of leaves, with half the leaf count.
            leaves.append((center.copy(), axis.copy(), side.copy(), normal.copy(), length*1.41*rng.uniform(.80,1.16), rng.randrange(4)))
    bmesh.ops.delete(bm,geom=removed,context="FACES")
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    # Decimate the remaining bark/branch geometry before attaching 2-triangle origami leaves.
    decimate_to(obj, TREE_BRANCH_TRI_BUDGET, "Branch decimation")
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    first_material = len(obj.data.materials)
    for index, color in enumerate(["547d46","668847","3e7760","79964e"]):
        obj.data.materials.append(material("Studio_PaintedGardenLeaves_%d" % index,color,.95))
    # 4-vertex creased diamond origami leaves (2 triangles per leaf, 75% reduction vs 8-tri fan).
    for center, axis, side, normal, length, tone in leaves:
        v_base = bm.verts.new(center - axis * (length * 0.52) + normal * (length * 0.04))
        v_right = bm.verts.new(center - side * (length * 0.30) + normal * (length * 0.01))
        v_tip = bm.verts.new(center + axis * (length * 0.58) + normal * (length * 0.05))
        v_left = bm.verts.new(center + side * (length * 0.30) + normal * (length * 0.01))
        for tri in ((v_base, v_right, v_tip), (v_base, v_tip, v_left)):
            face = bm.faces.new(tri)
            face.material_index = first_material + tone
            face.smooth = False
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()


def keep_outside_window(group):
    bpy.context.view_layer.update()
    front = max(-(obj.matrix_world @ Vector(p)).y for obj in group.children if obj.type=="MESH" for p in obj.bound_box)
    if front > -22:
        group.location.y += front + 22


def import_asset(asset,name,at,height,angle=0,base_anchor=False,max_width=None):
    if asset in _asset_cache:
        meshes = []
        for original, world in _asset_cache[asset]:
            obj = original.copy()
            obj.parent = None
            obj.matrix_world = world
            bpy.context.collection.objects.link(obj)
            meshes.append(obj)
        imported = meshes
    else:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(ASSETS/asset/f"{asset}_1k.gltf"))
        imported = list(set(bpy.data.objects)-before)
        meshes = [obj for obj in imported if obj.type == "MESH"]
        for obj in meshes:
            if len(obj.data.polygons) > 150000:
                bpy.context.view_layer.objects.active = obj
                # Dissolve coplanar triangles first, retaining the leaf silhouettes.
                mod = obj.modifiers.new("Planar foliage simplification", "DECIMATE")
                mod.decimate_type = "DISSOLVE"
                mod.angle_limit = math.radians(4)
                bpy.ops.object.modifier_apply(modifier=mod.name)
                if len(obj.data.polygons) > 450000:
                    mod = obj.modifiers.new("Medium detail garden LOD", "DECIMATE")
                    mod.ratio = 450000 / len(obj.data.polygons)
                    mod.use_collapse_triangulate = True
                    bpy.ops.object.modifier_apply(modifier=mod.name)
                simplify_leaf_density(obj)
            else:
                decimate_to(obj, PROP_TRI_BUDGET.get(asset, DEFAULT_PROP_TRI_BUDGET), "Prop LOD decimate")
        bpy.context.view_layer.update()
        _asset_cache[asset] = [(obj,obj.matrix_world.copy()) for obj in meshes]
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(p) for obj in meshes for p in obj.bound_box]
    lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    scale = height/(hi.z-lo.z)
    if max_width:
        scale = min(scale,max_width/(hi.x-lo.x))
    anchor = Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    if base_anchor:
        bottom = [obj.matrix_world @ vert.co for obj in meshes for vert in obj.data.vertices
                  if (obj.matrix_world @ vert.co).z < lo.z+(hi.z-lo.z)*.012]
        anchor.x = sum(p.x for p in bottom)/len(bottom)
        anchor.y = sum(p.y for p in bottom)/len(bottom)
    transform = Matrix.Translation(v(at)) @ Matrix.Rotation(angle,4,'Z') @ Matrix.Scale(scale,4) @ Matrix.Translation(-anchor)
    originals = [(obj,obj.matrix_world.copy()) for obj in meshes]
    parent = bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(parent)
    parent["source"] = "https://polyhaven.com/a/"+asset
    parent["license"] = "CC0-1.0"
    for obj,world in originals:
        obj.parent = parent
        obj.matrix_world = transform @ world
    for obj in imported:
        if obj.type != "MESH":
            bpy.data.objects.remove(obj,do_unlink=True)
    print("IMPORTED",name,"height",height,"source",asset)
    return parent


# New shell: 184 x 88 cm desk, 3.4 cm thick, on black steel supports.
box("CraftDeskTop",(0,-2.05,3.5),(92,1.7,44),oak,.13,repeat=46)
box("DeskBackRail",(0,-4.1,-16),(87,2.5,1.1),oak,.07)
for x in [-40,40]:
    for z in [-14,21]:
        box("DeskSteelLeg",(x,-19.8,z),(1.2,36,1.2),metal,.09)
    box("DeskSteelFoot",(x,-37,3.5),(1.4,1.2,37),metal,.09)
    box("DeskSideRail",(x,-4,3.5),(1.2,2,37),metal,.08)
box("StudioFloor",(0,-38,35),(300,.8,220),light_oak,0,repeat=45)

# Standard 90 x 60 cm mat; 1 cm and 5 cm ruling rendered procedurally in studio_color_blocks.gdshader.
mat = box("CuttingMat_90x60cm",(0,-1.145,5),(45,.11,30),mat_rubber,.10)
mat["width_cm"],mat["depth_cm"] = 90.0,60.0

# Real window opening. Transparent panes are added by the Godot component.
box("WallBelowWindow",(0,-17,-19),(300,45,1.6),plaster,0,repeat=12)
for x in [-89.5,89.5]:
    box("WallBesideWindow",(x,25,-19),(121,40,1.6),plaster,0,repeat=12)
box("WallAboveWindow",(0,73,-19),(300,64,1.6),plaster,0,repeat=12)
box("OakWindowSill",(0,5.3,-16.8),(61,.8,6),oak,.10,repeat=32)
for x in [-29.2,0,29.2]:
    box("BlackWindowMullion",(x,23.4,-18.3),(.65,35.5,1),metal,.035)
for y in [5.8,41.1]:
    box("BlackWindowFrame",(0,y,-18.3),(59,.65,1),metal,.035)
for x in [-1.2,1.2]:
    curve("WindowHandle",[(x,19,-17.6),(x,19,-17.0),(x,21.2,-17.0)],.10,metal)
box("LinenRollerBlind",(0,40.5,-17.2),(58,3.3,.18),linen,.05,repeat=3)
curve("BlindBottomHem",[(-29,38.8,-17.05),(29,38.8,-17.05)],.13,light_oak)

# Open oak shelves and exposed triangulated brackets.
for side in [-1,1]:
    for y in [10,22,34]:
        x = side*38.8
        box("OakShelf",(x,y,-14.6),(17.2,.8,8.2),oak,.09,repeat=30)
        for dx in [-6.2,6.2]:
            box("BracketWallRail",(x+dx,y-2.2,-18.1),(.30,5.3,.35),metal,.035)
            box("BracketArm",(x+dx,y-.7,-14.8),(.30,.35,6.8),metal,.035)
            curve("BracketDiagonal",[(x+dx,y-4.3,-17.9),(x+dx,y-.7,-11.7)],.14,metal)

# Artist-authored CC0 curved props, fitted to the new furniture.
import_asset("book_encyclopedia_set_01","ReferenceBooksLeft",(-38.7,10.4,-14.4),9.8,0,max_width=15.5)
import_asset("book_encyclopedia_set_01","ReferenceBooksRight",(38.7,22.4,-14.4),9.3,0,max_width=15.5)
import_asset("wicker_basket_02","FabricBasketLeft",(-38.7,22.4,-14.5),7.0,.12)
import_asset("wicker_basket_02","FabricBasketRight",(38.7,10.4,-14.5),6.7,-.12)
import_asset("potted_plant_02","SillPlantLeft",(-23,5.7,-16),10,.6)
import_asset("potted_plant_02","ShelfPlantRight",(38.8,34.4,-14.5),9,-1.1)
task_lamp = import_asset("desk_lamp_arm_01","TaskLamp",(30,-1.2,-12.8),15.0,.45+math.pi*.5,True)
bpy.context.view_layer.update()
bulb_points = [obj.matrix_world @ obj.data.vertices[i].co for obj in task_lamp.children
               for face in obj.data.polygons if "light" in obj.data.materials[face.material_index].name
               for i in face.vertices]
emitter = bpy.data.objects.new("TaskLampEmitter",None)
bpy.context.collection.objects.link(emitter)
emitter.parent = task_lamp
emitter.location = sum(bulb_points,Vector())/len(bulb_points) + v((0,-.65,0))
for i in range(5):
    box("FoldedFabric",(-32,-.75+i*.55,6),(11,.54,8),cloth[i%4],.18,-.08+i*.025,3)
box("NotionsChest",(32,1.5,-6),(10,5.4,6),light_oak,.10)
for i in range(2):
    for j in range(3):
        x,y = 29.5+i*5.0,-.2+j*1.65
        box("NotionsDrawer",(x,y,-2.9),(4.7,1.48,.28),oak,.06)
        curve("DrawerPull",[(x-.65,y,-2.65),(x-.65,y,-2.3),(x+.65,y,-2.3),(x+.65,y,-2.65)],.09,brass)

lathe("BrushPot",(28,-1.2,6),[(0,0),(1.2,0),(1.4,.2),(1.5,4),(1.4,4.1),(1.23,4.05),(1.1,.3),(0,.3)],ceramic,20)
for i in range(9):
    x,z,h = 27.3+(i%3)*.65,5.3+(i//3)*.65,5.4+random.random()*2.5
    curve("BrushHandle",[(x,-.8,z),(x+(i-4)*.10,h,z+.2)],.085,[oak,metal,cloth[1]][i%3])
    lathe("BrushFerrule",(x+(i-4)*.10,h-.4,z+.2),[(.09,0),(.12,0),(.12,.55),(.09,.55)],steel,12)
    lathe("BrushTip",(x+(i-4)*.10,h+.15,z+.2),[(0,0),(.13,0),(.12,.35),(0,.8)],metal,12)
box("ThreadRackBack",(-12,2.0,-13),(15,6,.40),light_oak,.07)
for row in range(2):
    box("ThreadRackShelf",(-12,-.4+row*3.0,-11.8),(15,.25,2.5),light_oak,.04)
    for col in range(6):
        at = (-18.3+col*2.5,-.25+row*3.0,-11.8)
        lathe("WoodBobbin",at,[(0,0),(.62,0),(.65,.18),(.38,.22),(.38,1.8),(.65,1.85),(.65,2.03),(0,2.03)],light_oak,16)
        lathe("WoundThread",at,[(.39,.23),(.57,.30),(.57,1.73),(.39,1.82)],thread_mats[(col+row)%5],16)

# Thin metal dressmaking tools beside the mat.
for side in [-1,1]:
    x,y,z = 29,-1.0,16
    curve("ShearHandle",[(x+side*.68+math.cos(t*math.tau/20)*.62,y,z+2+math.sin(t*math.tau/20)*.95) for t in range(20)],.12,brass,True)
    curve("ShearNeck",[(x+side*.5,y,z+1.3),(x,y,z)],.10,steel)
    outline = [(-.13,0),(.18,0),(side*.62,-4.3),(side*.22,-4.4)]
    vertices = [v((x+a,y+b,z+c)) for b in [-.045,.045] for a,c in outline]
    mesh = bpy.data.meshes.new("ShearBlade")
    mesh.from_pydata(vertices,[],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
    mesh.update()
    obj = bpy.data.objects.new("ShearBlade",mesh)
    bpy.context.collection.objects.link(obj)
    finish(obj,obj.name,steel)
lathe("ShearPivot",(29,-.92,16),[(0,0),(.18,0),(.18,.12),(0,.17)],brass,16)
box("SteelRuler",(9,-1.06,22.5),(15,.08,1),ruler_steel,.03)
curve("Pencil",[(-15,-1.0,22),(-6,-1.0,21.4)],.12,cloth[1])

# Real 3D garden, behind the window: foliage has parallax, shadows and occlusion.
box("GardenGround",(0,-25,-110),(300,1,175),soil,0)
for name,at,height,angle in [
        ("GardenTreeNear",(-22,-24.5,-61),65,.4),
        ("GardenTreeMiddle",(32,-24.5,-85),77,2.1),
        ("GardenTreeFar",(-58,-24.5,-115),85,-.7)]:
    tree = import_asset("jacaranda_tree",name,at,height,angle)
    keep_outside_window(tree)
for i,x in enumerate([-30,-10,13,36]):
    fern = import_asset("fern_02","GardenFern"+str(i),(x,-24.5,-36-i*3),12+i%2*3,i*.8)
    keep_outside_window(fern)

# Editable parts in the source; static batches per semantic group for Godot.
for obj in list(bpy.context.scene.objects):
    if obj.type not in {"MESH","CURVE"} or (obj.type == "MESH" and not obj.modifiers):
        continue
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
source = ROOT/"art_source"/"workbench"
source.mkdir(parents=True,exist_ok=True)
(source.parent/".gdignore").touch()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(source/"artisan_workbench.blend"))
groups = {}
for obj in list(bpy.context.scene.objects):
    if obj.type == "MESH" and len(obj.data.materials)==1 and obj.name != "CuttingMat_90x60cm":
        groups.setdefault((obj.parent,obj.data.materials[0]),[]).append(obj)
for (parent,mat),objects in groups.items():
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects)>1:
        bpy.ops.object.join()
    bpy.context.object.name = mat.name
bpy.ops.export_scene.gltf(filepath=str(ASSETS/"artisan_workbench.glb"),export_format="GLB",export_yup=True,export_apply=True,export_extras=True,export_cameras=False,export_lights=False,export_animations=False)
tris = 0
for obj in bpy.context.scene.objects:
    if obj.type=="MESH":
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
print("STUDIO_REBUILT",tris,"triangles")
