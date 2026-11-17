"""Build isolated paper-diorama assets from the imagegen-approved direction sheet.
Run in Blender through MCP. Coordinates are Blender Z-up; GLB converts to Godot Y-up.
Leaves the user's original scene, selection and saved .blend untouched.
"""
import bpy, math, os
from mathutils import Vector

OUTPUT = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'assets', 'street_vendor')

def build():
    old_scene = bpy.context.window.scene
    scene = bpy.data.scenes.new('WW_Vendor_Asset_Study')
    bpy.context.window.scene = scene
    mats = {}
    def mat(name, color):
        if name in mats: return mats[name]
        m = bpy.data.materials.new('WW_Vendor_' + name)
        m.use_nodes = True
        srgb = tuple(int(color[i:i+2],16)/255 for i in (0,2,4))
        rgb = tuple(c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in srgb)
        bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        bsdf.inputs['Base Color'].default_value = (*rgb,1)
        bsdf.inputs['Roughness'].default_value = .88
        m.diffuse_color = (*rgb,1)
        mats[name] = m
        return m
    oak=mat('HoneyCard','936532'); edge=mat('PaperEdge','d4b879'); dark=mat('PrintedShadow','4b3826')
    green=mat('CanopyGreen','568a73'); cream=mat('WarmPaper','eee2b6'); indigo=mat('IndigoCloth','344681')
    rose=mat('Rose','b76e78'); blue=mat('Blue','779ab1'); teal=mat('Teal','6b9987'); gold=mat('Gold','d2a349')
    red=mat('Vermilion','b9503c'); glass=mat('WindowInk','293e3d')
    def empty(name,parent=None):
        obj=bpy.data.objects.new(name,None); scene.collection.objects.link(obj); obj.parent=parent; return obj
    def mesh(name,verts,faces,material,parent):
        me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
        ob=bpy.data.objects.new(name,me); scene.collection.objects.link(ob); ob.parent=parent
        me.materials.append(material); return ob
    def box(name,loc,size,material,parent,bevel=.008):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
        ob=bpy.context.object; ob.name=name; ob.dimensions=size
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        ob.parent=parent; ob.data.materials.append(material)
        if bevel:
            mod=ob.modifiers.new('CardEdge','BEVEL'); mod.width=bevel; mod.segments=1
            bpy.ops.object.modifier_apply(modifier=mod.name)
        return ob
    def cyl(name,loc,radius,depth,material,parent,axis='Z',vertices=32):
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc)
        ob=bpy.context.object; ob.name=name; ob.parent=parent; ob.data.materials.append(material)
        if axis=='Y': ob.rotation_euler.x=math.pi/2
        if axis=='X': ob.rotation_euler.y=math.pi/2
        return ob
    def ring(name,loc,outer,inner,thickness,material,parent):
        verts=[]; faces=[]; n=48
        for y in [-thickness/2,thickness/2]:
            for radius in [outer,inner]:
                verts += [(loc[0]+math.cos(i*math.tau/n)*radius,loc[1]+y,loc[2]+math.sin(i*math.tau/n)*radius) for i in range(n)]
        for i in range(n):
            j=(i+1)%n
            faces += [(i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),(i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)]
        return mesh(name,verts,faces,material,parent)
    def export(root,filename):
        bpy.ops.object.select_all(action='DESELECT')
        for obj in [root]+list(root.children_recursive): obj.select_set(True)
        bpy.context.view_layer.objects.active=root
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUTPUT,filename),export_format='GLB',use_selection=True,export_yup=True)

    try:
        cart=empty('NotionsCart')
        box('CartBed',(0,0,.95),(2.3,1.3,.12),oak,cart)
        for y in [-.65,.65]:
            box('SideRail',(0,y,1.17),(2.35,.07,.38),oak,cart)
            box('Rim',(0,y,1.39),(2.43,.09,.07),edge,cart)
        for x in [-1.14,1.14]: box('EndBoard',(x,0,1.16),(.08,1.3,.4),oak,cart)
        for x in [-1,-.5,0,.5,1]: box('BedPlank',(x,0,1.02),(.47,1.24,.035),edge,cart,.002)
        cyl('Axle',(0,0,.65),.07,1.95,dark,cart,'Y')
        for y,name in [(-.83,'WheelFront'),(.83,'WheelBack')]:
            wheel=empty(name,cart); wheel.location=(0,y,.65)
            ring('WoodenRim',(0,0,0),.64,.54,.11,oak,wheel)
            ring('RimPaperEdge',(0,-.063,0),.645,.622,.012,edge,wheel)
            cyl('Hub',(0,0,0),.13,.18,edge,wheel,'Y')
            for i in range(10):
                a=i*math.tau/10
                spoke=box('Spoke',(math.cos(a)*.32,0,math.sin(a)*.32),(.48,.075,.065),oak,wheel,.004)
                spoke.rotation_euler.y=-a
        for y in [-.44,.44]:
            handle=box('PullHandle',(1.54,y,1.07),(1.35,.07,.07),oak,cart)
            handle.rotation_euler.y=-.07
        for x in [-1.03,1.03]:
            for y in [-.56,.56]: box('CanopyPost',(x,y,1.93),(.065,.065,1.77),oak,cart)
        for side in [-1,1]:
            # Pitched textile roof, with actual card thickness and underside.
            verts=[(-1.32,0,2.98),(1.32,0,2.98),(1.32,side*.89,2.65),(-1.32,side*.89,2.65)]
            roof=mesh('CanopyLeaf',verts,[(0,1,2,3)],green,cart)
            solid=roof.modifiers.new('CardThickness','SOLIDIFY'); solid.thickness=.025
            bpy.context.view_layer.objects.active=roof; bpy.ops.object.modifier_apply(modifier=solid.name)
            for i in range(8):
                x=-1.32+i*.33
                verts=[(x,side*.89,2.65),(x+.33,side*.89,2.65)]+[(x+.165+.165*math.cos(a),side*.89,2.65-.18*math.sin(a)) for a in [j*math.pi/8 for j in range(9)]]
                scallop=mesh('ScallopedValance',verts,[tuple(range(len(verts)))],green,cart)
                solid=scallop.modifiers.new('FoldThickness','SOLIDIFY'); solid.thickness=.018
                bpy.context.view_layer.objects.active=scallop; bpy.ops.object.modifier_apply(modifier=solid.name)
        box('CanopyRidge',(0,0,2.99),(2.76,.055,.045),edge,cart)
        # Draped indigo cloth over counter: contiguous piece with diagonal printed checks.
        verts=[(-.9,-.72,.8),(.95,-.72,.8),(-.9,-.72,1.48),(.95,-.72,1.48),(-.9,.48,1.48),(.95,.48,1.48)]
        cloth=mesh('IndigoTableCloth',verts,[(0,1,3,2),(2,3,5,4)],indigo,cart)
        solid=cloth.modifiers.new('ClothThickness','SOLIDIFY'); solid.thickness=.012
        bpy.context.view_layer.objects.active=cloth; bpy.ops.object.modifier_apply(modifier=solid.name)
        for row in range(4):
            for col in range(10):
                if (row+col)%2: continue
                x=-.83+col*.18; z=.88+row*.16
                mesh('WhitePrintedDiamond',[(x,-.729,z+.07),(x+.07,-.729,z),(x,-.729,z-.07),(x-.07,-.729,z)],[(0,1,2,3)],cream,cart)
        for i,m in enumerate([cream,blue,rose]):
            box('FoldedFabric',(-.65,.20,1.53+i*.12),(.8,.48,.11),m,cart,.035)
        for i,m in enumerate([rose,blue,teal,gold]):
            box('SampleBook',(-.55+i*.19,-.35,1.65),(.15,.32,.34),m,cart)
            box('SampleLabel',(-.55+i*.19,-.518,1.69),(.08,.008,.1),cream,cart,.001)
        for i,m in enumerate([red,gold,blue,teal]):
            x=.05+i*.25
            cyl('ThreadCone',(x,.22,1.75),.105,.5,m,cart)
            cyl('ThreadCore',(x,.22,2.01),.045,.03,cream,cart)
            for j in range(9): cyl('ThreadWinding',(x,.22,1.52+j*.052),.109,.008,m,cart,vertices=20)
        export(cart,'notions_cart.glb')
        cart.hide_set(True)

        shop=empty('PaperTextileShop')
        box('CardFoundation',(0,0,.06),(5.7,1.8,.12),edge,shop)
        box('PaperPlaster',(0,.3,2.5),(5.5,.12,5),cream,shop)
        box('WindowShadow',(.65,.18,2.25),(3.6,.07,2.3),glass,shop)
        for x in [-2.65,-1.25,2.65]: box('TimberPost',(x,.05,2.5),(.15,.19,5.1),oak,shop)
        for z in [.35,1.05,3.48,4.65]: box('TimberLintel',(0,.04,z),(5.5,.2,.13),oak,shop)
        box('DoorInset',(-1.95,.13,1.65),(1.15,.08,2.8),dark,shop)
        for i in range(6): box('DoorSlat',(-2.48+i*.205,.06,1.65),(.15,.07,2.8),oak,shop,.003)
        cyl('DoorPull',(-1.55,-.005,1.7),.04,.03,gold,shop,'Y')
        for x in [-1.12,.65,2.42]: box('WindowFrame',(x,-.04,2.24),(.09,.18,2.4),oak,shop)
        for i in range(12): box('LatticeVertical',(-1.03+i*.30,-.06,3.16),(.038,.07,.52),edge,shop,.001)
        for z in [2.93,3.16,3.39]: box('LatticeHorizontal',(.65,-.065,z),(3.45,.07,.035),edge,shop,.001)
        box('DisplayShelf',(.65,-.31,1.12),(3.8,.75,.1),oak,shop)
        for i,m in enumerate([blue,rose,teal]):
            box('DisplayCloth',(.0,-.3,1.28+i*.2),(1.45,.52,.18),m,shop,.04)
        for i,m in enumerate([gold,rose,cream]): box('FabricSample',(1.25+i*.33,-.28,1.58),(.28,.35,.82),m,shop)
        # Roof slopes and folded edge strips create a silhouette rather than a flat sign.
        for side in [-1,1]:
            ob=mesh('RoofCard',[(-2.95,0,5.55),(2.95,0,5.55),(2.95,side*1.05,4.75),(-2.95,side*1.05,4.75)],[(0,1,2,3)],blue,shop)
            mod=ob.modifiers.new('RoofThickness','SOLIDIFY'); mod.thickness=.06
            bpy.context.view_layer.objects.active=ob; bpy.ops.object.modifier_apply(modifier=mod.name)
            for i in range(17):
                strip=box('PaperRoofRib',(-2.8+i*.35,side*.52,5.17),(.05,1.32,.045),cream,shop,.002)
                strip.rotation_euler.x=-side*.65
        box('ShopSign',(0,-.17,4.1),(2.5,.12,.55),indigo,shop)
        for side in [-1,1]:
            box('SignBorder',(0,-.24,4.1+side*.24),(2.46,.015,.025),edge,shop,.001)
        box('Awning',(.65,-.72,3.74),(3.95,1.3,.04),cream,shop)
        for i in range(10):
            x=-1.325+i*.395
            verts=[(x,-1.38,3.74),(x+.395,-1.38,3.74)]+[(x+.1975+.1975*math.cos(a),-1.38,3.74-.2*math.sin(a)) for a in [j*math.pi/8 for j in range(9)]]
            mesh('AwningScallop',verts,[tuple(range(len(verts)))],cream,shop)
        for x in [-2.58,2.58]:
            cyl('Lantern',(x,-.4,3.7),.19,.43,gold,shop)
            cyl('LanternCap',(x,-.4,3.94),.16,.05,red,shop)
            box('LanternTassel',(x,-.4,3.28),(.035,.035,.35),red,shop)
        export(shop,'paper_textile_shop.glb')
        print({'scene':scene.name,'objects':len(scene.objects),'outputs':['notions_cart.glb','paper_textile_shop.glb'],'original_scene_preserved':old_scene.name})
    finally:
        bpy.context.window.scene=old_scene

if __name__ == '__main__': build()
