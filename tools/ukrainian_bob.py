"""Centre-parted, turned-under bob for the shared VolumeDoll head slot (Y up)."""

from math import atan2, cos, exp, pi, sin, sqrt, tau


def build_reference_bob(Mesh, point, color):
    hair = Mesh("ReferenceBob", color, "hair")

    def ease(x):
        x = min(1.0, max(0.0, x))
        return x * x * (3.0 - 2.0 * x)

    def tint(value):
        return tuple(c * value for c in color[:3]) + (1.0,)

    # The crown stays continuous under the swept front pieces. Its part sits
    # slightly left of centre. Each interval is one individually laid hank;
    # the bends travel across the back and tuck alternately over one another.
    part = -.16
    divisions = (0, .91, 1.54, 2.30, 3.08, 3.96, 4.76, 5.45, tau)
    sway = (.07, .13, .20, .15, -.12, -.23, -.15, -.09)
    lengths = (.014, .024, .033, .021, .037, .029, .026, .018)
    shades = (1.02, .96, 1.00, .91, .98, .95, 1.04, .98)
    rings, slices = 46, 160
    crown = hair.add((-.025, .634, -.012), tint(1.01))
    previous = None

    def surface(t, u):
        arc = tau * u
        hank = next((i for i in range(8) if arc < divisions[i + 1]), 7)
        local = (arc - divisions[hank]) / (divisions[hank + 1] - divisions[hank])
        crest = sin(pi * local) ** 2
        a = arc + part
        signed = atan2(sin(a), cos(a))
        # At the part the fringe opens high; over the temples it falls to the
        # cheek, leaving the eyes clear. Back hem sits just above the collar.
        openness = 1.0 - ease((abs(signed + .10) - .20) / 1.04)
        hem = .030 + .461 * openness
        hem -= (1.0 - openness) * lengths[hank] * crest
        y = hem + (.634 - hem) * cos(.5 * pi * t)
        if y >= .29:
            dome = sqrt(max(0.0, 1.0 - ((y - .29) / .344) ** 2))
        else:
            dome = 1.0 - .15 * ease((.29 - y) / .26)
        # Shared boundary angle at every hank edge, including the UV seam.
        wave = (.12 * sin(2*a-.4) + .14 * sin(a+.2)) * sin(t * pi * 1.85)
        a += wave + sway[hank] * crest * sin(t * pi * 2.18 - .6) * ease(t/.4)
        under = (1.0 - openness) * ease((t-.61)/.39)
        turn = .018 * under * (sin(2.3*pi*(t-.61)/.39) + .5)
        relief = dome * (.021 * crest + .023 * under * crest) + turn
        relief += .014*sin(3*pi*t+.7*hank)*ease(t/.4)*(1-openness)
        return ((.343*dome+relief)*sin(a)-.025*(1.0-dome),
                y,
                (.322*dome+relief)*cos(a)-.012*(1.0-dome)), tint(
                    1.0 + dome*((shades[hank]-1.0)*crest - .105*(1.0-crest)**3))

    for i in range(1, rings + 1):
        row = []
        for j in range(slices):
            pos, ink = surface(i / rings, j / slices)
            idx = hair.add(pos, ink)
            hair.uv[idx] = (j/slices, 1.0-i/rings)
            row.append(idx)
        for j in range(slices):
            n = (j+1) % slices
            if previous is None:
                hair.f.append((crown, row[j], row[n]))
            else:
                hair.f.extend(((previous[j], row[j], row[n]), (previous[j], row[n], previous[n])))
        previous = row
    # Fold the cut edge back into the hair mass for a soft, solid silhouette
    # where a low camera can see beneath the free ends.
    inner = []
    for j, outer in enumerate(previous):
        x,y,z = hair.v[outer]
        inner.append(hair.add((.87*x, y+.024, .87*z), tint(.76)))
    for j in range(slices):
        n=(j+1) % slices
        hair.f.extend(((previous[j], inner[j], inner[n]), (previous[j], inner[n], previous[n])))

    # These locks are broad, flattened volumes. A section spreads along the
    # head surface and has a separate thickness in the radial direction. Each
    # guide includes its own curl, rather than copying rotations of one lock.
    from mathutils.bvhtree import BVHTree
    scalp = BVHTree.FromPolygons(hair.v, hair.f, all_triangles=True)

    def lock(guide, shade):
        def sample(t):
            at = min(t,1.0) * (len(guide)-1)
            k = min(int(at),len(guide)-2)
            f = at-k
            a,b,c,d = (guide[min(len(guide)-1,max(0,k+i))] for i in (-1,0,1,2))
            return tuple(.5 * (2*b[j]+(-a[j]+c[j])*f+
                         (2*a[j]-5*b[j]+4*c[j]-d[j])*f*f+
                         (-a[j]+3*b[j]-3*c[j]+d[j])*f*f*f) for j in range(5))

        def body(t,u):
            x,y,z,width,depth = sample(t)
            before=sample(max(0.0,t-.001))
            after=sample(min(1.0,t+.001))
            tangent=point(*(after[i]-before[i] for i in range(3))).normalized()
            normal=point(x/.30,(y-.29)/.34,z/.31).normalized()
            width_axis=tangent.cross(normal).normalized()
            outward=width_axis.cross(tangent).normalized()
            p=point(x*.95,y,z*.97) + width_axis*(max(.001,width*1.35)*cos(tau*u)) + outward*(max(.0003,depth*.38*ease(t/.38))*sin(tau*u))
            # The first half grows out of the crown surface; a separate curl
            # becomes free only after it passes the temple.
            if t < .52:
                hit,normal,index,distance=scalp.find_nearest(p)
                if hit is not None:
                    root=hit+normal*(.0012+.002*ease(t/.25)*max(0,sin(tau*u)))
                    p=root.lerp(p,ease((t-.20)/.32))
            return p,tint(shade*(.92+.08*max(0,sin(tau*u)))),0
        hair.grid(42,18,body)

    # Shorter swept-back left section; a fuller wave on the wearer's other
    # temple. The guide positions are measured from the shared head centre.
    lock([(-.025,.623,-.012,.001,.001),(-.050,.603,.105,.025,.010),(-.081,.563,.204,.050,.022),
          (-.158,.544,.205,.058,.034),(-.201,.471,.218,.054,.029),
          (-.227,.365,.220,.054,.028),(-.275,.293,.181,.056,.030),
          (-.311,.237,.136,.052,.027),(-.315,.158,.136,.041,.023),
          (-.348,.116,.127,.026,.017),(-.365,.130,.109,.002,.002)],1.07)
    lock([(-.025,.623,-.012,.001,.001),(.016,.604,.101,.028,.010),(.020,.573,.206,.047,.024),
          (.107,.580,.198,.069,.043),(.175,.532,.204,.075,.041),
          (.199,.457,.223,.064,.038),(.222,.382,.217,.058,.032),
          (.282,.320,.181,.062,.035),(.322,.243,.134,.054,.032),
          (.305,.157,.126,.043,.026),(.334,.104,.112,.030,.022),
          (.372,.119,.077,.002,.002)],1.00)
    # Fuse the swept roots and crown into one surface. Intersecting hair cards
    # produce hard patches in the game's flat shading, even when very thin.
    import bpy
    obj=hair.finish()
    bpy.context.view_layer.objects.active=obj
    obj.select_set(True)
    shell=obj.modifiers.new('Hair shell','SOLIDIFY')
    shell.thickness=.010
    shell.offset=-1
    bpy.ops.object.modifier_apply(modifier=shell.name)
    fuse=obj.modifiers.new('Continuous crown','REMESH')
    fuse.mode='VOXEL'
    fuse.voxel_size=.005
    fuse.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=fuse.name)
    relax=obj.modifiers.new('Soft hair transitions','SMOOTH')
    relax.factor=.75
    relax.iterations=4
    bpy.ops.object.modifier_apply(modifier=relax.name)
    budget=obj.modifiers.new('Game hair budget','DECIMATE')
    budget.ratio=.16
    bpy.ops.object.modifier_apply(modifier=budget.name)
    obj.data.calc_loop_triangles()
    merged=Mesh('ReferenceBob',color,'hair')
    for vertex in obj.data.vertices:
        x,z,y=vertex.co
        z=-z
        angle=atan2(x,z)
        shade=.98+.024*cos(5*angle+1.7*y)+.012*sin(9*y+angle)
        merged.add((x,y,z),tint(shade))
        merged.uv[-1]=(angle/tau+.5,y/.65)
    merged.f=[tuple(triangle.vertices) for triangle in obj.data.loop_triangles]
    bpy.data.objects.remove(obj,do_unlink=True)
    return merged.finish()
