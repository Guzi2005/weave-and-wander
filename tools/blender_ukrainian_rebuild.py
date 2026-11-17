"""Blender authoring source for the Ukrainian reference costume.
Run through the live Blender MCP; exports the same mesh data consumed by Godot.
"""
import bpy, bmesh, math, json, random
from mathutils import Vector
from pathlib import Path

ROOT = Path(r'D:/workspace/weave-and-wander')
TAU = 2 * math.pi
sin, cos, pi = math.sin, math.cos, math.pi
rng = random.Random(31)
SCENE = bpy.data.scenes.new('Ukrainian rebuild - cloth and yarn')
bpy.context.window.scene = SCENE
PARTS = {}
baseline=ROOT/'Docs/ukrainian-model/accepted-lower-garments.json'
if not baseline.exists():
    existing=json.loads((ROOT/'assets/collections/ukrainian_photo_001/blender_rebuild.json').read_text())
    baseline.write_text(json.dumps({k:existing[k] for k in ['UkrApron','UkrOverskirtWoven','UkrUnderskirt','UkrCuffs']}))
PRESERVED=json.loads(baseline.read_text())
WHITE = (.86,.82,.73,1)
GOLD = (.39,.29,.045,1)
PLUM = (.25,.075,.145,1)
TEAL = (.018,.075,.085,1)
BROWN = (.22,.095,.045,1)

def smooth(t):
    t = max(0,min(1,t)); return t*t*(3-2*t)

def point(x,y,z):
    return Vector((x,y,z))

def mix(a,b,t): return a+(b-a)*t

def linear_color(col, value=1): return [min(1,c*value) for c in col[:3]]+[1]

class Mesh:
    def __init__(self, name, color, slot='top'):
        self.name=name; self.color=color; self.slot=slot
        self.v=[];self.f=[];self.c=[];self.w=[];self.uv=[]
    def add(self,p,c=None,w=0):
        self.uv.append((p[0]*3.0,p[1]*3.0));self.v.append(tuple(p));self.c.append(c or self.color);self.w.append(w)
        return len(self.v)-1
    def grid(self,rows,cols,fn):
        start=len(self.v)
        for i in range(rows+1):
            for j in range(cols+1):
                p,c,w=fn(i/rows,j/cols);self.add(p,c,w);self.uv[-1]=(j/cols*6,i/rows*6)
        for i in range(rows):
            for j in range(cols):
                a=start+i*(cols+1)+j
                self.f.extend([(a,a+1,a+cols+2),(a,a+cols+2,a+cols+1)])
    def tube(self,path,radius,colors=None,sides=7):
        start=len(self.v)
        for i,p in enumerate(path):
            tangent=(path[min(i+1,len(path)-1)]-path[max(0,i-1)]).normalized()
            guide=Vector((0,0,1)) if abs(tangent.z)<.85 else Vector((1,0,0))
            u=tangent.cross(guide).normalized();v=tangent.cross(u).normalized()
            r=radius if isinstance(radius,float) else radius[i]
            for j in range(sides):
                self.add(p+r*(u*cos(TAU*j/sides)+v*sin(TAU*j/sides)),colors)
        for i in range(len(path)-1):
            for j in range(sides):
                a=start+i*sides+j;b=start+i*sides+(j+1)%sides
                self.f.extend([(a,b,b+sides),(a,b+sides,a+sides)])
    def finish(self):
        mesh=bpy.data.meshes.new(self.name)
        mesh.from_pydata([(x,-z,y) for x,y,z in self.v],[],self.f);mesh.update()
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
        for p in mesh.polygons:p.use_smooth=True
        uv_layer=mesh.uv_layers.new(name='FabricUV')
        for loop in mesh.loops: uv_layer.data[loop.index].uv=self.uv[loop.vertex_index]
        attr=mesh.color_attributes.new(name='ClothColor',type='FLOAT_COLOR',domain='POINT')
        for v,c in zip(attr.data,self.c):v.color=c
        mat=bpy.data.materials.new(self.name+' textile');mat.use_nodes=True
        shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        shader.inputs['Roughness'].default_value=.85
        vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='ClothColor'
        mat.node_tree.links.new(vc.outputs['Color'],shader.inputs['Base Color'])
        mesh.materials.append(mat)
        obj=bpy.data.objects.new(self.name,mesh);SCENE.collection.objects.link(obj)
        mesh.calc_loop_triangles()
        PARTS[self.name]={'vertices':self.v,'normals':[(v.normal.x,v.normal.z,-v.normal.y) for v in mesh.vertices],
            'uv':self.uv,'indices':[i for t in mesh.loop_triangles for i in reversed(t.vertices)],'colors':self.c,'arm_weights':self.w,'slot':self.slot}
        return obj

# Drape controls in doll units. A gather describes a seam pulling on a sheet:
# the trough opens out, bends with the grain and dies away in the free cloth.
NECK_GATHER = .013
WAIST_GATHER = .018
CUFF_GATHER = .014
SKIRT_FULLNESS = .031
APRON_EASE = .018
WAIST = 1.510
SKIRT_HEM = .357

def gather(angle, distance, pleats, depth):
    offset = 0.0
    for anchor, length, width, drift in pleats:
        if distance >= length:
            continue
        progress = distance / length
        axis = anchor + drift * progress * (1.4 - .4 * progress)
        delta = (angle - axis + pi) % TAU - pi
        across = delta / (width * (1.0 + .8 * progress))
        if abs(across) < 3.8:
            valley = math.exp(-across * across)
            rolled_edge = .48 * math.exp(-((across - 1.1) / 1.45) ** 2)
            offset += depth * (rolled_edge - valley) * (1.0 - smooth(progress))
    return offset

# Angular positions, run-out lengths, gathering widths, direction of lay.
neck_pleats = [(-.90,.66,.12,-.22),(-.50,.42,.09,-.10),(-.22,.55,.10,-.12),
               (.29,.43,.10,.16),(.67,.70,.13,.14),(1.15,.32,.10,.25),
               (2.31,.56,.13,-.11),(2.74,.44,.12,.16),(-3.04,.68,.14,-.16),(-2.57,.49,.13,.10)]
waist_pleats = [(-1.22,.41,.14,.19),(-.73,.56,.15,-.19),(-.29,.37,.11,-.15),
                (.12,.49,.13,.23),(.80,.58,.14,.20),(1.76,.43,.16,-.20),
                (2.44,.61,.16,.22),(3.04,.43,.14,-.24),(-2.54,.54,.17,-.13)]
cuff_pleats = [(-2.73,.43,.18,-.21),(-1.87,.31,.15,.25),(-.91,.50,.22,.30),
               (.11,.38,.20,-.26),(1.32,.57,.17,.39),(2.06,.31,.14,.20)]
shirt = Mesh('UkrShirt', WHITE)
rows, cols = 40, 128
hem_y = WAIST - .016
def torso(t,u):
    opening = .075 * smooth((t-.70)/.30)
    a = opening + u*(TAU-2*opening)
    fullness = sin(pi*t)**1.3
    shoulder = smooth((t-.38)/.62)
    rx = .247 + .026*fullness - .153*smooth((t-.52)/.48)
    # Distinct front ease and shallow back follow the doll's chest and scapulae.
    front = max(0,cos(a))
    back = max(0,-cos(a))
    rz = .159 + .022*front*fullness - .067*shoulder - .035*back*sin(pi*t)
    symmetric_angle=abs((a+pi)%TAU-pi)
    d = gather(symmetric_angle,1-t,neck_pleats,NECK_GATHER) + gather(symmetric_angle,t,waist_pleats,WAIST_GATHER)
    # A quiet fold of excess cloth rests above the compressed waistband.
    tuck=.018*math.exp(-((t-.25)/.13)**2)
    rx+=tuck;rz+=tuck*(.4+.6*front)
    y = mix(hem_y,1.943,t) - .093*t**3*front**4
    return (sin(a)*(rx+d), y, cos(a)*(rz+d)), WHITE, 0

shirt.grid(rows,cols,torso)
# Sew each sleeve directly into its armscye. The armhole boundary and sleeve
# cap share indices, so there is no overlapping tube or shading cut at the shoulder.
low, high, span = 13, 32, 12
def armhole(row, col):
    return low <= row < high and any(abs(col+.5-c) < span for c in (cols//4,3*cols//4))
shirt.f = [face for k, face in enumerate(shirt.f) if not armhole(k//2//cols, k//2%cols)]
for side, center_col in [(1,cols//4),(-1,3*cols//4)]:
    lo, hi = center_col-span, center_col+span
    edge = ([(high,j) for j in range(lo,hi)] + [(i,hi) for i in range(high,low,-1)]
          + [(low,j) for j in range(hi,lo,-1)] + [(i,lo) for i in range(low,high)])
    boundary = [i*(cols+1)+j for i,j in edge]
    previous = []
    for ring in range(45):
        t = ring/44
        current = []
        for k,(i,j) in enumerate(edge):
            if ring == 44:
                current.append(boundary[k])
                continue
            angle = math.atan2(-side*(j-center_col)/span, 2*(i-low)/(high-low)-1)
            # Sweep from the actual cuff into the sewn armscye. The control
            # cage follows the arm and gives the shoulder a single quiet arc.
            target=Vector(shirt.v[boundary[k]])
            p0=point(side*(.30+.084*cos(angle)),1.234,.030+.085*sin(angle))
            p1=point(side*(.30+.205*cos(angle)),1.435,.025+.173*sin(angle))
            neighbors=[]
            if i==high: neighbors.append(Vector(shirt.v[(i+1)*(cols+1)+j]))
            if i==low: neighbors.append(Vector(shirt.v[(i-1)*(cols+1)+j]))
            if j==lo: neighbors.append(Vector(shirt.v[i*(cols+1)+j-1]))
            if j==hi: neighbors.append(Vector(shirt.v[i*(cols+1)+j+1]))
            direction=(target-sum(neighbors,Vector())/len(neighbors)).normalized()
            p2=target+direction*.045
            p=(1-t)**3*p0+3*(1-t)**2*t*p1+3*(1-t)*t*t*p2+t**3*target
            ripple=gather(angle,t,cuff_pleats,CUFF_GATHER)*smooth(t/.08)
            p+=point(side*cos(angle),0,sin(angle))*ripple
            p.y+=.035*sin(pi*t)**2*max(0,cos(angle))
            x,y,z=p
            weight=side*(1-smooth((t-.48)/.52))
            idx = shirt.add((x,y,z), WHITE, weight)
            shirt.uv[idx]=(k/len(edge)*4,t*5)
            current.append(idx)
        if previous:
            for k in range(len(edge)):
                n=(k+1)%len(edge)
                shirt.f.extend([(previous[k], previous[n], current[n]),(previous[k],current[n],current[k])])
        previous=current
# Cut a short front slit under the bow. Remove unused armhole-interior vertices.
shirt.f=[f for f in shirt.f if not (sum(shirt.v[k][1] for k in f)/3>1.908 and abs(sum(shirt.v[k][0] for k in f)/3)<.003 and sum(shirt.v[k][2] for k in f)>0)]
used=sorted({k for face in shirt.f for k in face})
mapping={old:new for new,old in enumerate(used)}
shirt.f=[tuple(mapping[k] for k in face) for face in shirt.f]
for attr in ('v','c','w','uv'):
    data=getattr(shirt,attr)
    setattr(shirt,attr,[data[k] for k in used])
# Relax the sewn transition without changing neckline or cuff boundaries.
adj=[set() for _ in shirt.v]
for tri in shirt.f:
    for a,b in [(tri[0],tri[1]),(tri[1],tri[2]),(tri[2],tri[0])]:
        adj[a].add(b);adj[b].add(a)
for _ in range(10):
    old=[Vector(p) for p in shirt.v]
    for k,p in enumerate(old):
        if 1.59<p.y<1.89 and abs(p.x)>.105 and adj[k]:
            average=sum((old[j] for j in adj[k]),Vector())/len(adj[k])
            shirt.v[k]=tuple(p.lerp(average,.5))
# The continuous skin collar of VolumeDoll is wider over the clavicles.
# Keep a sewing allowance around its exact sampled profile throughout the cap.
neck_profile=[(1.48,.186,.134,.006),(1.62,.196,.138,.012),(1.76,.188,.126,.010),
              (1.84,.144,.108,.015),(1.92,.102,.088,.020),(1.98,.080,.078,.024)]
for k,(x,y,z) in enumerate(shirt.v):
    if neck_profile[0][0] <= y <= neck_profile[-1][0]:
        a,b=next((a,b) for a,b in zip(neck_profile,neck_profile[1:]) if a[0]<=y<=b[0])
        f=(y-a[0])/(b[0]-a[0])
        center=mix(a[3],b[3],f)
        coverage=math.hypot(x/(mix(a[1],b[1],f)+.012),(z-center)/(mix(a[2],b[2],f)+.012))
        if 0 < coverage < 1:
            shirt.v[k]=(x/coverage,y,center+(z-center)/coverage)
# Compress only the tucked base around the same waist used by the sash.
for k,(x,y,z) in enumerate(shirt.v):
    blend=1-smooth((y-WAIST-.032)/.060)
    if blend>0 and abs(shirt.w[k])<.01:
        radius=math.hypot(x/.272,z/.183)
        if radius>1: shirt.v[k]=(mix(x,x/radius,blend),y,mix(z,z/radius,blend))
shirt.finish()
cuffs=Mesh('UkrCuffs',WHITE)
for side in (-1,1):
    cuffs.grid(8,72,lambda t,u: ((side*.30+(.083+.002*t)*cos(TAU*u),1.188+.048*t,.030+(.085+.005*t)*sin(TAU*u)),WHITE,side))
cuffs.finish()
# Long chemise: narrow free hem, with enough room for the calves underneath.
under=Mesh('UkrUnderskirt',WHITE,'bottom')
def chemise(t,u):
    a = u*TAU
    roll=.007*t*(cos(3*a+.6)+.5*cos(5*a-.3))
    return ((.284+.055*t+roll)*sin(a),mix(WAIST,.310,t)+.005*t*cos(3*a-.4),(.210+.059*t+roll)*cos(a)),WHITE,0
under.grid(26,112,chemise)
under.finish()

# Large, uneven hanging flutes, independent of the woven stripe repeat.
skirt_pleats=[(-3.01,.97,.15,.07),(-2.45,.79,.12,-.12),(-2.06,1.34,.18,-.16),
              (-1.46,1.55,.17,.08),(-.96,.68,.13,.11),(-.52,.56,.13,-.03),
              (.19,.86,.17,-.10),(.72,.53,.13,.10),(1.15,1.56,.17,-.09),
              (1.81,1.22,.20,.13),(2.48,1.35,.17,-.12),(2.77,.54,.09,-.08)]
def skirt_position(t,u):
    a = u*TAU
    # Each fold has its own grain direction. Front under the apron is lightly pressed.
    fullness = .68 + .32*smooth((abs((a+pi)%TAU-pi)-.58)/.45)
    d = fullness*gather(a,t,skirt_pleats,SKIRT_FULLNESS)*(.45+1.5*t)
    hanging = t*t*(.014*cos(4*a+.36)+.009*cos(7*a-1.12))
    rx = .299 + .322*t + .019*sin(pi*t)
    rz = .220 + .190*t + .013*sin(pi*t)
    return (sin(a)*(rx+d+hanging),mix(WAIST,SKIRT_HEM,t)+t*t*(.010*sin(3*a+.52)+.006*cos(a)),cos(a)*(rz+d+hanging))

skirt=Mesh('UkrOverskirtWoven',TEAL,'bottom')
def outer(t,u):
    phase=(u*28)%1
    col=TEAL
    if .11<phase<.255:col=(.46,.32,.08,1)
    elif .31<phase<.34:col=(.30,.20,.065,1)
    elif .55<phase<.60:col=(.085,.13,.10,1)
    elif .70<phase<.74:col=(.14,.055,.10,1)
    return skirt_position(t,u),col,0
skirt.grid(36,1120,outer);skirt.finish()

apron=Mesh('UkrApron',PLUM,'bottom')
def apron_fn(t,u):
    # Cut panel spans the front with ease. Only the backing surface limits its
    # inward travel; the apron does not inherit the skirt's pleat field.
    a = mix(-.94,.94,u) + .032*t + .026*t*(1-(2*u-1)**2)
    hem=.464+.058*u*u-.009*cos(2.6*u)
    y = mix(WAIST-.003,hem,t)
    ratio=(WAIST-y)/(WAIST-SKIRT_HEM)
    rx=.300 + .322*ratio + .019*sin(pi*ratio)
    rz=.224 + .190*ratio + .013*sin(pi*ratio)
    laying=gather(a,t,[(-.68,1.32,.14,.13),(-.25,.46,.10,-.09),(.38,1.12,.15,.15),(.72,.37,.11,-.04)],APRON_EASE)
    free_edge=.007*t*t*cos(3*a-.3)
    ease=.012*smooth(t/.12)+.005
    x=sin(a)*(rx+ease+laying+free_edge)
    z=cos(a)*(rz+ease+laying+free_edge)
    # Compare surfaces at the same X/Y, rather than at equal UVs.
    lo,hi=-1.5,1.5
    for _ in range(9):
        mid=(lo+hi)*.5
        if skirt_position(ratio,mid/TAU)[0]<x: lo=mid
        else: hi=mid
    backing=skirt_position(ratio,(lo+hi)*.5/TAU)[2]
    z=max(z,backing+.006+.003*t)
    return (x,y,z),PLUM,0
apron.grid(42,100,apron_fn);apron.finish()
def apron_front(x,y):
    t=max(0,min(1,(WAIST-y)/(WAIST-.486)))
    lo,hi=0.,1.
    for _ in range(9):
        mid=(lo+hi)*.5
        if apron_fn(t,mid)[0][0]<x: lo=mid
        else: hi=mid
    return apron_fn(t,(lo+hi)*.5)[0][2]

exec(compile((ROOT/'tools/ukrainian_sash.py').read_text(), 'ukrainian_sash', 'exec'))
# Close seed-bead floral band, followed by two fine, gravity-draped strands.
beads=Mesh('UkrBeads',(.65,.62,.53,1))
def bead(cx,cy,cz,r,col):
    beads.grid(5,8,lambda t,u: ((cx+r*sin(pi*t)*cos(TAU*u),cy+r*cos(pi*t),cz+r*sin(pi*t)*sin(TAU*u)),col,0))
ivory=(.78,.75,.66,1)
dark=(.018,.021,.018,1)
from mathutils.bvhtree import BVHTree
# Contact uses final authoring triangles, including the clavicle clearance pass.
contact_points=list(shirt.v)
contact_faces=list(shirt.f)
neck_contact=neck_profile+[(2.04,.076,.074,.028)]
base=len(contact_points)
for y,rx,rz,center in neck_contact:
    for j in range(96):
        a=TAU*j/96
        contact_points.append((sin(a)*rx,y,center+cos(a)*rz))
for i in range(len(neck_contact)-1):
    for j in range(96):
        a=base+i*96+j
        b=base+i*96+(j+1)%96
        contact_faces.extend([(a,b,b+96),(a,b+96,a+96)])
contact_tree=BVHTree.FromPolygons(contact_points,contact_faces,all_triangles=True)
for row in range(3):
    path=[]
    for k in range(721):
        a=TAU*k/720
        fall=((1+cos(a))*.5)**1.3
        y=1.977-.017*row-(.100+.041*row)*fall+.004*sin(a)
        direction=Vector((sin(a),0,cos(a)))
        # Cast inward from outside to find the garment surface facing the string.
        hit,normal,index,distance=contact_tree.ray_cast(Vector((0,y,0))+direction*.8,-direction,1.0)
        if hit is None:
            hit=Vector((.096*sin(a),y,.088*cos(a)))
        path.append(hit+direction*.0084)
    lengths=[0.]
    for a,b in zip(path,path[1:]):
        lengths.append(lengths[-1]+(b-a).length)
    count=max(36,round(lengths[-1]/.016))
    segment=0
    for k in range(count):
        distance=lengths[-1]*k/count
        while segment<len(path)-2 and lengths[segment+1]<distance:
            segment+=1
        ratio=(distance-lengths[segment])/max(.000001,lengths[segment+1]-lengths[segment])
        p=path[segment].lerp(path[segment+1],ratio)
        col=dark if row==0 and k%9 in [0,1,7,8] else ivory
        bead(p.x,p.y,p.z,.0076,col)
beads.finish()
bow=Mesh('UkrNeckBow',(.12,.015,.032,1))
for side in [-1,1]:
    path=[point(side*.044*sin(pi*t),1.892+.018*sin(TAU*t),.128+.007*sin(pi*t)) for t in [i/24 for i in range(25)]]
    bow.tube(path,.0045)
    path=[]
    for k in range(23):
        t=k/22
        x=side*(.008+.018*t)
        y=1.890-(.166 if side<0 else .145)*t
        normalized=(y-hem_y)/(1.929-hem_y)
        front=torso(normalized,x/(TAU*.23))[0][2]
        path.append(point(x,y,front+.006))
    bow.tube(path,.004)
bow.finish()
# Individually swept locks authored against the shared head dimensions.
exec(compile((ROOT/'tools/ukrainian_bob.py').read_text(), 'ukrainian_bob', 'exec'))
hair_obj=build_reference_bob(Mesh,point,BROWN)
hair_obj.location=(0,-.035,2.02)
# Retain the already accepted lower garments and sleeve cuffs.
for label in ['UkrApron','UkrOverskirtWoven','UkrUnderskirt','UkrCuffs']:
    if label in PRESERVED:
        for obj in list(SCENE.objects):
            if obj.name.split('.')[0]==label:
                bpy.data.objects.remove(obj,do_unlink=True)
        raw=PRESERVED[label]
        replacement=Mesh(label,WHITE,raw['slot'])
        replacement.v=[(x,y-.055*smooth((y-.75)/.78),z) for x,y,z in raw['vertices']] if label!='UkrCuffs' else raw['vertices']
        if label in ['UkrApron','UkrOverskirtWoven','UkrUnderskirt']:
            fitted=[]
            for x,y,z in replacement.v:
                blend=smooth((y-(WAIST-.13))/.13)
                radius=math.hypot(x/(.261 if label=='UkrUnderskirt' else .277),z/(.174 if label=='UkrUnderskirt' else .192))
                if radius>1:
                    x=mix(x,x/radius,blend);z=mix(z,z/radius,blend)
                fitted.append((x,y,z))
            replacement.v=fitted
        replacement.c=raw['colors']
        replacement.w=raw['arm_weights'];replacement.uv=raw['uv']
        replacement.f=[tuple(reversed(raw['indices'][i:i+3])) for i in range(0,len(raw['indices']),3)]
        replacement.finish()

# Export editable source with deterministic game mesh data.
output=ROOT/'assets/collections/ukrainian_photo_001/blender_rebuild.json'
temporary=output.with_suffix('.tmp.json')
temporary.write_text(json.dumps(PARTS,separators=(',',':')))
try:
    temporary.replace(output)
except PermissionError:
    output.write_bytes(temporary.read_bytes())
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Docs/ukrainian-model/ukrainian-fit-refinement.blend'))
print('BLENDER_REBUILD',len(PARTS),'parts',sum(len(p['vertices']) for p in PARTS.values()),'vertices')
