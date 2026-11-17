"""A single woven ribbon: hanging end, two turns, overhand tie, hanging end.

Executed by the Blender authoring script with its mesh and contact helpers.
"""
sash = Mesh('UkrSashWrap', GOLD)
stations = []

def station(p, width, guide):
    stations.append((Vector(p), width, Vector(guide)))

def tail_center(t, side):
    x = side*(.132+.030*t)
    y = WAIST - .005 - .370 * t
    return point(x, y, apron_front(x, y) + .014 + .008 * (1-smooth(t/.25)))

# The left end rises from its fringe and folds diagonally into the first wrap.
for k in range(61):
    t = 1-k/60
    station(tail_center(t, -1), .087, (1, 0, 0))

def bridge(controls, widths, guides, steps=12):
    # Catmull-Rom preserves a continuous tangent through the cloth folds.
    for i in range(len(controls)-1):
        a,b,c,d = [Vector(controls[max(0,min(len(controls)-1,j))]) for j in [i-1,i,i+1,i+2]]
        for k in range(1,steps+1):
            t=k/steps
            p=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
            station(p,mix(widths[i],widths[i+1],smooth(t)),Vector(guides[i]).lerp(Vector(guides[i+1]),smooth(t)))

start_angle=.36
def winding(t):
    a=start_angle+2*TAU*t
    overlap=.008*smooth((t-.48)/.04)
    return point(sin(a)*(.288-.006*t+overlap),WAIST+.012+.052*t+.022*sin(a-.6),cos(a)*(.212-.008*t+overlap))

bridge([tail_center(0,-1),point(-.098,WAIST+.028,.247),point(.018,WAIST+.034,.231),winding(0)],
       [.087,.070,.067,.065],[(1,0,0),(1,.6,0),(.3,1,0),(0,1,0)])
wrap_begin=len(stations)
for k in range(1,481):
    t=k/480
    station(winding(t),.065,(0,1,0))

wrap_end=len(stations)
knot_begin=len(stations)
# Compact overhand tie, with one compressed passage tucked beneath the other.
# Separate depth levels keep the crossing surfaces apart.
bridge([winding(1),point(.130,WAIST+.065,.239),point(.150,WAIST+.035,.260),
        point(.131,WAIST+.002,.268),point(.090,WAIST+.006,.270),
        point(.071,WAIST+.033,.248),point(.105,WAIST+.058,.242),
        point(.133,WAIST+.029,.291),point(.129,WAIST-.012,.280),
        tail_center(.12,1),tail_center(.22,1)],
       [.065,.056,.050,.046,.045,.042,.041,.047,.060,.079,.087],
       [(0,1,0),(0,1,0),(.6,1,0),(1,.3,0),(1,0,0),(1,1,0),(.5,1,0),(1,.2,0),(1,0,0),(1,0,0),(1,0,0)],16)
for k in range(1,49):
    station(tail_center(mix(.22,1,k/48),1),.087,(1,0,0))

# A thin closed lenticular cross-section gives an actual cloth edge, not a cord.
segments=16
for i,(p,width,guide) in enumerate(stations):
    tangent=(stations[min(i+1,len(stations)-1)][0]-stations[max(0,i-1)][0]).normalized()
    across=(guide-tangent*guide.dot(tangent)).normalized()
    normal=tangent.cross(across).normalized()
    for j in range(segments):
        a=TAU*j/segments
        q=p+across*(.5*width*cos(a))+normal*(.006*sin(a))
        # Lower edge meets the skirt; upper edge fits the narrower blouse waist.
        if wrap_begin<=i<wrap_end:
            radial=Vector((q.x,0,q.z)).normalized()
            layer=(i-wrap_begin)/(wrap_end-wrap_begin)
            taper=smooth((q.y-WAIST+.018)/.115)
            rx=mix(.286,.277,taper);rz=mix(.205,.190,taper)
            radius=1/math.sqrt((radial.x/rx)**2+(radial.z/rz)**2)
            q=Vector((0,q.y,0))+radial*(radius+.008+.014*smooth((layer-.48)/.04)+.006*sin(a))
        sash.add(q,linear_color(GOLD,.96+.04*sin(a)))
        sash.uv[-1]=(j/segments,i/60)
for i in range(len(stations)-1):
    for j in range(segments):
        a=i*segments+j;b=i*segments+(j+1)%segments
        sash.f.extend([(a,b,b+segments),(a,b+segments,a+segments)])
sash.finish()

knot=Mesh('UkrSashKnot',GOLD)
for idx in range(2):
    loop=[point(.112-idx*.030+.020*sin(TAU*k/40),WAIST-.013-(.054+idx*.012)*(1-cos(TAU*k/40)),.278+.004*sin(pi*k/40)) for k in range(41)]
    knot.tube(loop,.0033,GOLD,7)
knot.finish()

for side,suffix in [(-1,'L'),(1,'R')]:
    tassel=Mesh('UkrTassel'+suffix,GOLD)
    mid=tail_center(1,side)
    # Yarn stems emerge across the full flat edge, gathering into compact tufts.
    for bundle in range(9):
        theta=TAU*bundle/9
        cx=mid.x+.051*cos(theta)
        cy=mid.y-.054+.016*sin(theta*2+.5) - (.018 if bundle in [2,6] else 0)
        cz=apron_front(cx,cy)+.040+.019*sin(theta)
        top=mid+point(.040*cos(theta),0,0)
        tassel.tube([top.lerp(point(cx,cy,cz),k/12)+point(0,0,.004*sin(pi*k/12)) for k in range(13)],.0030,GOLD,6)
        color=GOLD if bundle in [2,6] else PLUM
        for fiber in range(30):
            a=TAU*fiber/30
            length=rng.uniform(.046,.065)
            path=[];radii=[]
            for k in range(9):
                t=k/8
                spread=sin(pi*.5*t)**.72
                path.append(point(cx+.041*cos(a)*spread+.005*cos(theta)*t,cy-length*t+.008*sin(pi*t),cz+.037*sin(a)*spread))
                radii.append(.0059*(1-.35*t))
            tassel.tube(path,radii,linear_color(color,rng.uniform(.90,1.05)),6)
    tassel.finish()
