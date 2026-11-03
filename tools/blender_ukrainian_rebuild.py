"""Blender authoring source for the Ukrainian reference costume.
Run through the live Blender MCP; exports the same mesh data consumed by Godot.
"""
import bpy, bmesh, math, json, random
from mathutils import Vector
from pathlib import Path

ROOT = Path(r'D:/GodotProjects/weave-and-wander/prototypes/dollhouse-3d')
TAU = 2 * math.pi
sin, cos, pi = math.sin, math.cos, math.pi
rng = random.Random(31)
SCENE = bpy.data.scenes.new('Ukrainian rebuild - cloth and yarn')
bpy.context.window.scene = SCENE
PARTS = {}
WHITE = (.86,.82,.73,1)
GOLD = (.39,.29,.045,1)
PLUM = (.25,.075,.145,1)
TEAL = (.018,.075,.085,1)
BROWN = (.13,.055,.025,1)

def smooth(t):
    t = max(0,min(1,t)); return t*t*(3-2*t)

def point(x,y,z):
    return Vector((x,y,z))

def mix(a,b,t): return a+(b-a)*t

def linear_color(col, value=1): return [min(1,c*value) for c in col[:3]]+[1]

class Mesh:
    def __init__(self, name, color, slot='top'):
        self.name=name; self.color=color; self.slot=slot
        self.v=[];self.f=[];self.c=[];self.w=[]
    def add(self,p,c=None,w=0):
        self.v.append(tuple(p));self.c.append(c or self.color);self.w.append(w)
        return len(self.v)-1
    def grid(self,rows,cols,fn):
        start=len(self.v)
        for i in range(rows+1):
            for j in range(cols+1):
                p,c,w=fn(i/rows,j/cols);self.add(p,c,w)
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
            'indices':[i for t in mesh.loop_triangles for i in reversed(t.vertices)],'colors':self.c,'arm_weights':self.w,'slot':self.slot}
        return obj

# Blouse torso, gathered at the neck and into the sash.
shirt=Mesh('UkrShirt',WHITE)
def torso(t,u):
    a=u*TAU; y=mix(1.405,1.927,t)
    rx=.304-.142*smooth((t-.57)/.43)+.018*sin(pi*t)
    rz=.229-.102*smooth((t-.60)/.40)+.016*sin(pi*t)
    fold=(.010+.008*sin(pi*t))*sin(a*18+ .55*sin(t*4+a))+.004*cos(a*37-t*2)
    fold*=.4+.6*sin(pi*t)**.5
    shade=.92+.08*(.5+.5*sin(a*18+.55*sin(t*4+a)))
    return (sin(a)*(rx+fold),y,cos(a)*(rz+fold)),linear_color(WHITE,shade),0
shirt.grid(44,144,torso)
# Subtle slit, only in the last two centimetres under the tied collar.
shirt.f=[f for f in shirt.f if not (sum(shirt.v[k][1] for k in f)/3>1.905 and abs(sum(shirt.v[k][0] for k in f)/3)<.004 and sum(shirt.v[k][2] for k in f)>0)]
for side in [-1,1]:
    def sleeve(t,u):
        a=u*TAU;y=mix(1.145,1.855,t)
        center=side*(.30-.145*smooth((t-.55)/.45)+.043*sin(pi*t))
        r=.060+.080*sin(pi*t)**.65
        r+=.012*cos(a*10+.65*sin(t*5))*sin(pi*t)**.55
        p=(center+cos(a)*r,y,sin(a)*(r*1.03)+.012)
        return p,linear_color(WHITE,.90+.10*(.5+.5*cos(a*10+.65*sin(t*5)))),side*(1-smooth((y-1.70)/.155))
    shirt.grid(48,64,sleeve)
shirt.finish()
cuffs=Mesh('UkrCuffs',WHITE)
for side in [-1,1]:
    cuffs.grid(5,64,lambda t,u: ((side*.30+.065*cos(TAU*u),1.135+.045*t,.012+.069*sin(TAU*u)),linear_color(WHITE,.9+.08*cos(t*pi*4)),side))
cuffs.finish()
collar=Mesh('UkrShirtCollar',WHITE)
collar.grid(5,128,lambda t,u: ((sin(TAU*u)*(.163-.003*t),1.922+.014*t,cos(TAU*u)*(.129-.003*t)),linear_color(WHITE,.93+.06*sin(pi*t)),0))
collar.finish()
# White underdress is a soft straight tube rather than a flounce.
under=Mesh('UkrUnderskirt',WHITE,'bottom')
under.grid(30,120,lambda t,u: ((.315+.023*t+.004*sin(u*TAU*15))*sin(TAU*u),None,None)) if False else None
under.grid(30,120,lambda t,u: (((.315+.023*t+.004*sin(u*TAU*15))*sin(TAU*u),mix(1.42,.18,t),(.235+.033*t+.003*sin(u*TAU*15))*cos(TAU*u)),linear_color(WHITE,.91+.07*sin(u*TAU*15)),0))
under.finish()
# Broad soft folds under many narrower warp stripes, slightly uneven gathered hem.
def skirt_position(t,u,lift=0):
    a=u*TAU
    flare=.32*t+.025*sin(pi*t)
    fold=(.007+.015*t)*sin(26*a+.18*sin(a*3))+.006*t*sin(a*11)
    return (sin(a)*(.306+flare+fold+lift),mix(1.43,.285,t)+.007*t*sin(a*7),cos(a)*(.233+.185*t+fold+lift))
skirt=Mesh('UkrOverskirtWoven',TEAL,'bottom')
def outer(t,u):
    phase=(u*28)%1
    col=TEAL
    if .11<phase<.255:col=(.46,.32,.08,1)
    elif .31<phase<.34:col=(.30,.20,.065,1)
    elif .55<phase<.60:col=(.085,.13,.10,1)
    elif .70<phase<.74:col=(.14,.055,.10,1)
    shade=.82+.18*(.5+.5*sin(u*TAU*26+.18*sin(u*TAU*3)))
    return skirt_position(t,u),linear_color(col,shade),0
skirt.grid(44,1120,outer);skirt.finish()
apron=Mesh('UkrApron',PLUM,'bottom')
def apron_fn(t,u):
    a=mix(-.86,.86,u)
    x,y,z=skirt_position(t,(a%TAU)/TAU,.017)
    # apron finishes above skirt, with asymmetric weight at the lower edge
    y=mix(1.425,.405+.035*sin(a+.4),t)
    z+=.012*(.4+.6*t)*cos(a*11+.45*sin(t*3))
    return (x,y,z),linear_color(PLUM,.82+.18*(.5+.5*cos(a*11+.45*sin(t*3)))),0
apron.grid(48,128,apron_fn);apron.finish()
# Wrapped band is continuous, with overlapping soft rolls in a single cloth strip.
sash=Mesh('UkrSashWrap',GOLD)
for wrap in range(3):
    def band(t,u):
        a=u*TAU
        y=1.397+wrap*.029+(t-.5)*.047+.010*sin(a+wrap*.7)
        rx=.321+.008*sin(pi*t)+.004*wrap
        rz=.252+.008*sin(pi*t)+.004*wrap
        return (sin(a)*rx,y,cos(a)*rz),linear_color(GOLD,.79+.21*sin(pi*t)**.4),0
    sash.grid(10,160,band)
sash.finish()
# Knot with two flattened folded loops, a cinched diagonal core.
knot=Mesh('UkrSashKnot',GOLD)
for side in [-1,1]:
    def bow(t,u):
        a=t*TAU;w=(u-.5)*.042
        return (.085+side*.069*sin(a/2),1.435+.033*sin(a)+w,.284+.025*sin(a/2)+.009*cos((u-.5)*pi)),linear_color(GOLD,.78+.2*sin(pi*u)),0
    knot.grid(36,12,bow)
for i in range(7):
    path=[point(.079+.013*sin(TAU*j/36),1.425+.026*cos(TAU*j/36),.304+i*.0008) for j in range(37)]
    knot.tube(path,.0035)
knot.finish()
for side,suffix in [(-1,'L'),(1,'R')]:
    tail=Mesh('UkrSashTail'+suffix,GOLD)
    def tail_fn(t,u):
        center=side*(.128+.055*t+.009*sin(t*pi))
        x=center+(u-.5)*.09
        y=1.412-.40*t+.008*sin(t*5+u)
        z=.279+.091*t+.010*sin(t*6)+.007*cos(u*pi*2)
        return (x,y,z),linear_color(GOLD,.79+.15*sin(pi*u)+.025*sin(u*TAU*30)+.025*sin(t*TAU*65)),0
    tail.grid(72,32,tail_fn);tail.finish()
    # Individual looped yarn bundles form an irregular hanging fringe, no visible ball cores.
    tassel=Mesh('UkrTassel'+suffix,GOLD)
    for bundle in range(9):
        theta=TAU*bundle/9
        x=side*.183+.038*cos(theta); z=.377+.024*sin(theta)
        length=.105+rng.uniform(-.012,.012)
        col=PLUM if bundle%3 else GOLD
        for fiber in range(24):
            theta2=TAU*fiber/24
            radius=rng.uniform(.007,.017)
            path=[]
            for step in range(11):
                t=step/10
                path.append(point(x+radius*sin(theta2)*sin(pi*t)+.003*sin(t*TAU*2+theta2),.94-length*t,z+radius*cos(theta2)*sin(pi*t)))
            tassel.tube(path,[.0021*(.75+.25*sin(pi*k/10)) for k in range(11)],linear_color(col,rng.uniform(.75,1.1)),5)
        # Suspended mustard cords lead from flat sash end to tuft heads.
        path=[point(mix(side*.183,x,t),1.015-.078*t,.374+.012*sin(pi*t)+mix(0,z-.374,t)) for t in [i/10 for i in range(11)]]
        tassel.tube(path,.0022,GOLD,6)
    tassel.finish()
# Jewellery and burgundy neck tie.
beads=Mesh('UkrBeads',(.65,.62,.53,1))
for row in range(3):
    for k in range(72):
        a=k*TAU/72;r=.0057 if row else .0068
        cx=sin(a)*(.105+.012*row);cz=cos(a)*(.098+.011*row);cy=1.975-.014*row-.004*cos(a)
        col=(.025,.025,.022,1) if row==0 and k%4<2 else (.76,.73,.64,1)
        beads.grid(6,8,lambda t,u: ((cx+r*sin(pi*t)*cos(TAU*u),cy+r*cos(pi*t),cz+r*sin(pi*t)*sin(TAU*u)),col,0))
beads.finish()
bow=Mesh('UkrNeckBow',(.12,.015,.032,1))
for side in [-1,1]:
    path=[point(side*.044*sin(pi*t),1.917+.018*sin(TAU*t),.147+.007*sin(pi*t)) for t in [i/24 for i in range(25)]]
    bow.tube(path,.0045)
    path=[point(side*(.008+.018*t),1.915-(.17 if side<0 else .145)*t,.148+.073*t) for t in [i/18 for i in range(19)]]
    bow.tube(path,.004)
bow.finish()
# Coherent side-part bob: textured sheet surface, open around face, scalloped ends.
hair=Mesh('ReferenceBob',BROWN,'hair')
def hair_surface(t,u):
    a=u*TAU
    front=max(0,cos(a))
    end=2.45-(1.38*front**7)
    end+=.07*sin(a*11)*(1-front**7)
    phi=.025+t*end
    wave=.012*sin(14*a+.9*sin(phi*3))*(sin(phi)**2)
    r=.014+wave
    x=(.282+r)*sin(phi)*sin(a)
    y=.292+(.313+r)*cos(phi)
    z=(.302+r)*sin(phi)*cos(a)
    shade=.75+.25*(.5+.5*sin(14*a+.9*sin(phi*3)))
    return (x,y,z),linear_color(BROWN,shade),0
hair.grid(60,144,hair_surface)
# Broad sweeping front locks crest above forehead and turn into the temples.
for side in [-1,1]:
    for lock in range(3):
        def fringe(t,u):
            a=side*(.08+1.22*t+.07*lock)
            phi=.20+1.34*t
            width=(u-.5)*.16*sin(pi*(.08+.88*t))
            a+=width
            r=.023+.012*sin(pi*u)
            return ((.28+r)*sin(phi)*sin(a),.292+(.312+r)*cos(phi),(.303+r)*sin(phi)*cos(a)),linear_color(BROWN,.80+.22*sin(pi*u)),0
        hair.grid(36,14,fringe)
hair_obj=hair.finish();hair_obj.location=(0,-.035,2.02)
# Export editable source with deterministic game mesh data.
output=ROOT/'assets/collections/ukrainian_photo_001/blender_rebuild.json'
output.write_text(json.dumps(PARTS,separators=(',',':')))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Docs/ukrainian-model/ukrainian-rebuild.blend'))
print('BLENDER_REBUILD',len(PARTS),'parts',sum(len(p['vertices']) for p in PARTS.values()),'vertices')
