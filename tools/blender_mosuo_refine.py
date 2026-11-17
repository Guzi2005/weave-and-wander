"""Run through Blender MCP. Photo-based geometry study; unseen surfaces are inferred.

Coordinates in the construction helpers are Godot metres (Y up, +Z front).
Blender is the editable source; JSON is a deterministic mesh handoff to the shared rig.
"""
import bpy, math, json, os, random
from mathutils import Vector
from math import sin, cos, pi, sqrt

ROOT = r'D:\workspace\weave-and-wander'
OUT = os.path.join(ROOT, 'assets/collections/mosuo_photo_001')
os.makedirs(OUT, exist_ok=True)
NAME = 'WW_Photo001_Refined'
old = bpy.data.collections.get(NAME)
if old:
    for obj in list(old.objects): bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(old)
collection = bpy.data.collections.new(NAME)
bpy.context.scene.collection.children.link(collection)
for obj in bpy.data.objects:
    if obj.name.startswith('Mosuo'):
        obj.hide_set(True); obj.hide_render = True

def xyz(p): return (p[0], -p[2], p[1])
def hexcolor(h):
    def lin(c): return c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4
    return tuple(lin(int(h[i:i+2],16)/255) for i in (0,2,4))+(1,)

def material(name, color, rough=.4, metal=0, anisotropy=0):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=hexcolor(color)
    p.inputs['Roughness'].default_value=rough
    p.inputs['Metallic'].default_value=metal
    p.inputs['Anisotropic'].default_value=anisotropy
    m.diffuse_color=hexcolor(color)
    m['ww_color']=color;m['ww_roughness']=rough;m['ww_metallic']=metal
    return m

mats={
 'braid':material('WW / black hair braid','18151d',.36,0,.65),
 'red':material('WW / scarlet seed beads','e92e44',.24,.08),
 'yellow':material('WW / yellow cord','e3c433',.36),
 'green':material('WW / green cord','659442',.4),
 'blue':material('WW / blue cord','2563a9',.38),
 'purple':material('WW / purple cord','873db4',.32),
 'pink':material('WW / flower crimson','ee334c',.4,0,.4),
 'pinklight':material('WW / flower edge','ff6870',.43),
 'ivory':material('WW / ivory piping','f0e2c7',.43),
 'piping':material('WW / red piping','be1b35',.32),
 'stripe':material('WW / skirt red stripe','a62652',.39),
 'sash':material('WW / broad woven waist sash','714152',.48,0,.45),
 'sashthread':material('WW / sash woven edge','bd8994',.46),
 'insole':material('WW / insole grey felt','a5a49a',.9),
 'insoleedge':material('WW / insole magenta binding','bf3871',.55),
 'blouse':bpy.data.objects['MosuoBlouse'].data.materials[0].copy(),
 'skirt':bpy.data.objects['MosuoPleatedSkirt'].data.materials[0].copy(),
}
for key in ('blouse','skirt'):
    mats[key].name='WW / photo textile '+key
    p=next(n for n in mats[key].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Anisotropic'].default_value=.65
    p.inputs['Coat Weight'].default_value=.12
    p.inputs['Coat Roughness'].default_value=.35

parts=[]
def mesh(name, verts, faces, mat, slot, uvs=None, arms=None):
    data=bpy.data.meshes.new(name)
    data.from_pydata([xyz(v) for v in verts],[],faces);data.update()
    for poly in data.polygons: poly.use_smooth=True
    if uvs:
        layer=data.uv_layers.new(name='TextileUV')
        for poly in data.polygons:
            for i in poly.loop_indices: layer.data[i].uv=(uvs[data.loops[i].vertex_index][0],1-uvs[data.loops[i].vertex_index][1])
    obj=bpy.data.objects.new(name,data);collection.objects.link(obj)
    obj.data.materials.append(mats[mat]);obj['ww_slot']=slot;obj['ww_material']=mat;obj['ww_part_name']=name
    obj['ww_source']='WW-MOS-001 / user photo; back inferred'
    if arms: obj['ww_arm_weights']=arms
    parts.append(obj);return obj

def tube_add(verts,faces,path,radius,sides=7,phase=0):
    start=len(verts)
    for i,p in enumerate(path):
        tangent=(Vector(path[min(i+1,len(path)-1)])-Vector(path[max(0,i-1)])).normalized()
        axis=Vector((0,1,0))
        if abs(tangent.dot(axis))>.9: axis=Vector((1,0,0))
        u=tangent.cross(axis).normalized();v=tangent.cross(u).normalized()
        r=radius[i] if isinstance(radius,list) else radius
        for j in range(sides): verts.append(tuple(Vector(p)+r*(cos(j*2*pi/sides+phase)*u+sin(j*2*pi/sides+phase)*v)))
    for i in range(len(path)-1):
        for j in range(sides):
            a=start+i*sides+j;b=start+i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(start+j for j in reversed(range(sides))))
    faces.append(tuple(start+(len(path)-1)*sides+j for j in range(sides)))

def tube(name,path,r,mat,slot='headwear',sides=8):
    v=[];f=[];tube_add(v,f,path,r,sides);return mesh(name,v,f,mat,slot)

def hat_point(a,r,y):
    # The bound mass tilts towards the wearer's right; not concentric level bands.
    x=r*sin(a);z=r*.91*cos(a)+.02
    return (x,y+.13*x+.022*sin(a*2)*min(1,r/.35),z)

# Soft black cap, then separately modeled three-strand hair ropes around it.
v=[];f=[];N=128
profile=[(2.465,.286),(2.51,.337),(2.58,.349),(2.66,.31),(2.73,.245),(2.76,.12),(2.77,.001)]
for y,r in profile:
    for j in range(N+1):
        a=j*2*pi/N;p=hat_point(a,r,y);v.append(p)
for i in range(len(profile)-1):
    for j in range(N):
        a=i*(N+1)+j;f.append((a,a+1,a+N+2,a+N+1))
mesh('MosuoBraidedCrown',v,f,'braid','headwear')
v=[];f=[]
for row,(rad,h) in enumerate([(.325,2.555)]):
    for strand in range(3):
        path=[]
        for j in range(385):
            a=2*pi*j/384;ph=a*12+strand*2*pi/3
            r=rad+.030*cos(ph);p=hat_point(a,r,h+.032*sin(2*ph))
            path.append(p)
        tube_add(v,f,path,.034,10)
mesh('MosuoCoiledFalseBraids',v,f,'braid','headwear')

# Red bead garlands drape round the front rim in three nested loops.
v=[];f=[]
for row in range(3):
    for j in range(143):
        a=2*pi*j/143;r=.455-row*.004
        center=Vector(hat_point(a,r,2.54+row*.035-.025*cos(a)))
        tangent=Vector((cos(a),0,-.91*sin(a))).normalized()
        tube_add(v,f,[tuple(center-tangent*.0039),tuple(center),tuple(center+tangent*.0039)],[.006,.010,.006],7)
mesh('MosuoCrownRedBeadGarlands',v,f,'red','headwear')

# Fine yellow / green / blue / purple cords cross the black crown on oblique paths.
for ci,mat in enumerate(('yellow','green','blue','purple','yellow','green','purple','blue')):
    path=[]
    for j in range(177):
        a=j*2*pi/176+ci*.39
        y=2.64+.068*sin(a+(ci%3)*1.75)+.012*(ci//3)
        rad=.447-max(0,y-2.64)*.15
        p=hat_point(a,rad+.007,y);path.append(p)
    tube('MosuoCrossedCord%02d'%ci,path,.0042 if ci<4 else .0032,mat)

# Side knot connects the purple falling bundle physically to the headdress.
for i,mat in enumerate(('purple','ivory','green','purple')):
    path=[]
    for j in range(65):
        a=j*2*pi/64;path.append((.305+.064*cos(a),2.48+.021*sin(a)+.012*i,.10+.025*sin(a)))
    tube('MosuoSideWrap%02d'%i,path,.007,mat)

# Layered fabric rosettes from the supplementary close-ups: broad cupped petals.
rng=random.Random(41)
for kind in ('pink','pinklight'):
    v=[];f=[]
    for flower in range(2):
        base=Vector((.247+flower*.065,2.76-flower*.055,.075+flower*.07))
        for layer in range(4):
            count=5+layer*2
            for petal in range(count):
                if (petal+layer)%4==(0 if kind=='pink' else 1): continue
                angle=petal*2*pi/count+layer*.65
                radius=.018+layer*.022;start=len(v)
                for row in range(9):
                    t=row/8
                    for col in range(9):
                        u=col/8*2-1;a=angle+u*(.75-.25*t)
                        r=radius*(.25+.9*t)+.009*sin(t*pi)
                        p=base+Vector((cos(a)*r,sin(a)*r,.012+layer*.006+.045*sin(t*pi*.85)-.015*u*u))
                        v.append(tuple(p))
                for row in range(8):
                    for col in range(8):
                        a=start+row*9+col;f.append((a,a+1,a+10,a+9))
    mesh('MosuoFlowerPetals'+kind,v,f,kind,'headwear')

# Tailored blouse with controlled fold relief; sleeves keep the shared rig's arm ramp.
torso=[(1.24,.310,.224,0),(1.32,.298,.213,0),(1.42,.285,.207,0),(1.52,.283,.201,0),(1.61,.276,.196,0),(1.70,.266,.189,0),(1.78,.252,.176,0),(1.85,.224,.160,0),(1.90,.190,.140,0),(1.935,.150,.120,0)]
def lerp_ring(rings,y):
    for a,b in zip(rings[:-1],rings[1:]):
        if min(a[0],b[0])<=y<=max(a[0],b[0]):
            t=(y-a[0])/(b[0]-a[0]);return [a[k]+(b[k]-a[k])*t for k in range(4)]
    return min(rings,key=lambda a:abs(a[0]-y))

v=[];f=[];uv=[];aw=[]
def cloth_tube(rings,segments,rows,side=0):
    start=len(v);lo=rings[0][0];hi=rings[-1][0]
    for row in range(rows+1):
        y=lo+(hi-lo)*row/rows;_,rx,rz,cx=lerp_ring(rings,y)
        for j in range(segments+1):
            a=2*pi*j/segments
            relief=(.004*sin(a*11+y*15)+.003*sin(a*7-y*19))*(.35+.65*(1-row/rows))
            v.append((cx+(rx+relief)*sin(a),y,(rz+relief)*cos(a)))
            uv.append((j/segments*(.75 if side else 1.6),(2-y)*1.65))
            t=max(0,min(1,(y-1.63)/.2));smooth=t*t*(3-2*t)
            aw.append(side*(1-smooth))
    for row in range(rows):
        for j in range(segments):
            a=start+row*(segments+1)+j;f.append((a,a+1,a+segments+2,a+segments+1))
cloth_tube(torso,96,36)
for side in (-1,1):
    rings=[(1.13,.112,.119,side*.301),(1.18,.119,.127,side*.296),(1.28,.121,.124,side*.284),(1.38,.117,.120,side*.268),(1.48,.109,.114,side*.248),(1.58,.098,.108,side*.224),(1.68,.09,.1,side*.198),(1.78,.08,.09,side*.168),(1.86,.07,.08,side*.15)]
    cloth_tube(rings,64,32,side)
mesh('MosuoBlouse',v,f,'blouse','top',uv,aw)

def front(x,y,offset=.008):
    _,rx,rz,_=lerp_ring(torso,min(y,1.935))
    return (x,y,rz*sqrt(max(.02,1-(x/rx)**2))+offset)
def polyline(points,steps=12):
    out=[]
    for a,b in zip(points[:-1],points[1:]):
        for j in range(steps):
            t=j/steps;out.append(tuple(a[k]*(1-t)+b[k]*t for k in range(3)))
    out.append(points[-1]);return out

# Stand collar and doubled opening: the lapel turns towards viewer-left chest.
v=[];f=[]
for row in range(3):
    for j in range(97):
        a=.075+(2*pi-.15)*j/96;frontdrop=.010*max(0,cos(a))**5
        y=1.936+row*.022-frontdrop
        v.append((.114*sin(a),y,.103*cos(a)))
for row in range(2):
    for j in range(96):
        a=row*97+j;f.append((a,a+1,a+98,a+97))
mesh('MosuoStandingCollar',v,f,'piping','top')
for row in (2,):
    path=[(.115*sin(a),1.936+row*.022-.010*max(0,cos(a))**5,.104*cos(a)) for a in [.075+j*(2*pi-.15)/128 for j in range(129)]]
    tube('MosuoCollarIvoryEdge%d'%row,path,.004,'ivory','top')
opening=[(.009,1.969),(.016,1.931),(-.035,1.897),(-.155,1.854),(-.204,1.78),(-.231,1.50),(-.247,1.275)]
points=[front(x,y,.015) for x,y in opening]
tube('MosuoOverlappingLapelIvory',polyline(points),.014,'ivory','top',10)
tube('MosuoOverlappingLapelRed',[(x+.004,y,z+.012) for x,y,z in polyline(points)],.0048,'piping','top',7)
# Short other collar edge meets the overlap; no stripe cutting diagonally across the whole torso.
tube('MosuoCollarReturn',polyline([(-.009,1.969,.104),(-.009,1.936,.107),front(-.035,1.897,.014)]),.004,'ivory','top')
for side in (-1,1):
    path=[(side*.301+.114*sin(j*2*pi/96),1.14,.122*cos(j*2*pi/96)) for j in range(97)]
    ob=tube('MosuoCuff%s'%side,path,.012,'piping','top')
    ob['ww_arm_weights']=[side]*len(ob.data.vertices)
    path=[(side*.301+.114*sin(j*2*pi/96),1.13,.122*cos(j*2*pi/96)) for j in range(97)]
    ob=tube('MosuoCuffIvory%s'%side,path,.006,'ivory','top')
    ob['ww_arm_weights']=[side]*len(ob.data.vertices)

# Drape is nearly vertical below the hips, with nonuniform narrow folds and an uneven hem.
# The broad muted red waist wrap is partly covered by the hands in the primary photo.
v=[];f=[]
for row in range(9):
    y=1.215+row*.014
    for j in range(129):
        a=2*pi*j/128;ripple=.002*sin(a*11+row*.5)
        v.append(((.316+ripple)*sin(a),y+.006*sin(a*3),(.231+ripple)*cos(a)))
for row in range(8):
    for j in range(128):
        a=row*129+j;f.append((a,a+1,a+130,a+129))
mesh('MosuoBroadWaistSash',v,f,'sash','top')
for row in (0,1,6,7):
    y=1.221+row*.014
    path=[(.318*sin(a),y+.006*sin(a*3),.233*cos(a)) for a in [j*2*pi/160 for j in range(161)]]
    tube('MosuoSashWovenLine%d'%row,path,.0015,'sashthread','top',5)

# Independent handcraft object. Outline and magenta binding follow the item identified by the user.
outline=[(-.042,0),(-.061,.025),(-.063,.07),(-.048,.115),(-.051,.16),(-.066,.22),(-.065,.27),(-.044,.307),(-.013,.322),(.025,.312),(.050,.281),(.057,.239),(.045,.192),(.03,.145),(.029,.10),(.04,.055),(.036,.02),(.015,0)]
v=[(0,.15,.004),(0,.15,-.004)];f=[]
for z in (.004,-.004):
    for x,y in outline: v.append((x,y,z))
L=len(outline)
for i in range(L):
    j=(i+1)%L;f.extend([(0,2+i,2+j),(1,2+L+j,2+L+i),(2+i,2+L+i,2+L+j,2+j)])
mesh('MosuoMagentaEdgedInsole',v,f,'insole','handcraft')
tube('MosuoInsoleBinding',[(x,y,0) for x,y in outline+[outline[0]]],.006,'insoleedge','handcraft',10)

def skirtpoint(t,a,offset=0):
    rx=.265+.077*(1-math.exp(-t*4))+.018*t*t
    rz=.194+.067*(1-math.exp(-t*4))+.016*t*t
    phase=a*56+.18*sin(a*5)+.12*t*sin(a*3)
    amp=.0015+.008*(1-math.exp(-t*8))
    fold=amp*cos(phase)
    large=.006*sin(a*9+.6*t)*sin(pi*t/2)
    y=1.34-1.22*t+(.005*sin(a*7)+.003*cos(a*13))*t**6
    return ((rx+fold+large+offset)*sin(a),y,(rz+fold+large+offset)*cos(a))
v=[];f=[];uv=[];N=672;rows=56
for row in range(rows+1):
    t=row/rows
    for j in range(N+1):
        a=2*pi*j/N;v.append(skirtpoint(t,a));uv.append((j/N*2.3,t*1.4))
for row in range(rows):
    for j in range(N):
        a=row*(N+1)+j;f.append((a,a+N+1,a+N+2,a+1))
mesh('MosuoPleatedSkirt',v,f,'skirt','bottom',uv)
v=[];f=[]
for t in (.660,.675):
    for j in range(N+1): v.append(skirtpoint(t,2*pi*j/N,.0013))
for j in range(N): f.append((j,j+N+1,j+N+2,j+1))
mesh('MosuoRaisedRedHemStripe',v,f,'stripe','bottom')

# Reference image stays in the editable scene at the same apparent height.
ref=bpy.data.objects.get('WW_Reference_Photo')
if not ref:
    ref=bpy.data.objects.new('WW_Reference_Photo',None);bpy.context.scene.collection.objects.link(ref)
ref.empty_display_type='IMAGE';ref.data=bpy.data.images.load(os.path.join(ROOT,'Docs/wiki-concept-2026-10-28/mosuo-example/source-user-upload.png'),check_existing=True)
ref.empty_display_size=3.35;ref.location=(-1.15,0,1.45);ref.rotation_euler=(pi/2,0,0)
ref.color[3]=1

# Consistent normal orientation for closed tubes / open textile shells.
for obj in parts:
    bpy.context.view_layer.objects.active=obj;obj.select_set(True)
    import bmesh
    bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(obj.data);bm.free()
    obj.select_set(False)

def export_geometry():
    records=[]
    for obj in parts:
        me=obj.data;me.calc_loop_triangles();head=obj['ww_slot']=='headwear'
        coords=[];normals=[];uvs=[];arms=[];indices=[];lookup={}
        arm_source=obj.get('ww_arm_weights')
        # Split on loop UVs to retain the textile seam in the handoff.
        for tri in me.loop_triangles:
            triangle=[]
            for li in tri.loops:
                vi=me.loops[li].vertex_index;vert=me.vertices[vi];p=obj.matrix_world@vert.co
                uv=me.uv_layers.active.data[li].uv if me.uv_layers else None
                key=(vi,round(uv.x,6),round(uv.y,6)) if uv is not None else (vi,)
                if key in lookup:
                    triangle.append(lookup[key]);continue
                lookup[key]=len(coords);triangle.append(len(coords))
                gp=[p.x,p.z-(2.02 if head else 0),-p.y-(.035 if head else 0)]
                coords.append([round(c,6) for c in gp]);n=vert.normal;normals.append([round(n.x,6),round(n.z,6),round(-n.y,6)])
                if me.uv_layers:
                    uvs.append([round(uv.x,6),round(1-uv.y,6)])
                arms.append(arm_source[vi] if arm_source is not None else 0)
            indices.extend([triangle[0],triangle[2],triangle[1]])
        records.append(dict(name=obj['ww_part_name'],slot=obj['ww_slot'],material=obj['ww_material'],vertices=coords,normals=normals,uv=uvs,arm_weights=arms,indices=indices))
    data=dict(schema='ww-blender-costume-geometry-v1',source='WW-MOS-001',coordinate_system='Godot Y-up; headwear relative to HeadRig',inferred=['back','hidden closures','exact fibre and weaving technique'],parts=records)
    with open(os.path.join(OUT,'blender_geometry.json'),'w',encoding='utf-8') as f: json.dump(data,f,separators=(',',':'))
    print('WW_GEOMETRY_EXPORTED',len(records),sum(len(p['vertices']) for p in records))

export_geometry()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'mosuo_photo_001.blend'))
print('WW_BLENDER_REFINEMENT_READY',len(parts))

