"""Editable industrial miniatures and true azimuth rendering for Factorio.

Run with Blender --background --python tools/blender_scene.py -- --pilot.
The camera and lights never rotate. Only named mechanical assemblies move.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Quaternion
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(__file__).resolve().parents[1]
TAU = math.tau
SUN = Vector((-0.6, -0.8, 2.0)).normalized()
OBJECTS = []
MOVERS = {}


def material(name, color, metallic=0.0, roughness=0.6, glow=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Metallic'].default_value = metallic
    node.inputs['Roughness'].default_value = roughness
    if name in ('Worn olive enamel', 'Concrete plinth'):
        noise = mat.node_tree.nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = 27
        noise.inputs['Detail'].default_value = 2
        ramp = mat.node_tree.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position = .28
        ramp.color_ramp.elements[0].color = (*(v*.72 for v in color),1)
        ramp.color_ramp.elements[1].position = .76
        ramp.color_ramp.elements[1].color = (*(v*1.09 for v in color),1)
        mat.node_tree.links.new(noise.outputs['Fac'],ramp.inputs['Fac'])
        mat.node_tree.links.new(ramp.outputs['Color'],node.inputs['Base Color'])
    if glow:
        node.inputs['Emission Color'].default_value = (*color, 1)
        node.inputs['Emission Strength'].default_value = glow
    return mat


def finish(obj, name, mat, parent=None, bevel=0.03):
    obj.name = name
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    if bevel:
        mod = obj.modifiers.new('Machined edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    OBJECTS.append(obj)
    return obj


def box(name, loc, scale, mat, parent=None, bevel=0.03):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, parent, bevel)


def cylinder(name, loc, radius, depth, mat, parent=None, axis=None, vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    if axis:
        obj.rotation_euler = Vector(axis).to_track_quat('Z', 'Y').to_euler()
    return finish(obj, name, mat, parent, 0.014)


def cone(name, loc, r1, r2, depth, mat, parent=None, axis=None):
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=r1, radius2=r2, depth=depth, location=loc)
    obj = bpy.context.object
    if axis:
        obj.rotation_euler = Vector(axis).to_track_quat('Z', 'Y').to_euler()
    return finish(obj, name, mat, parent, 0.01)


def mesh(name, verts, faces, mat, parent=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat, parent, 0.015)


def pivot(name, loc=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.parent = parent
    MOVERS[name] = obj
    return obj


def plate(name, xy, z, thick, mat, parent=None):
    verts = [(x, y, z + h) for h in (-thick / 2, thick / 2) for x, y in xy]
    n = len(xy)
    faces = [tuple(range(n-1, -1, -1)), tuple(range(n, n*2))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    return mesh(name, verts, faces, mat, parent)


def setup():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 12
    scene.cycles.use_denoising = True
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.12
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_percentage = 100
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 12
    scene.world.color = (0.3, 0.3, 0.3)
    scene.view_settings.view_transform = 'AgX'
    bpy.ops.object.camera_add(location=(0, -10, 12))
    cam = bpy.context.object
    cam.name = 'Fixed oblique orthographic camera'
    cam.rotation_euler = (Vector((0, 0, 0.7))-cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.type = 'ORTHO'
    scene.camera = cam
    bpy.ops.object.light_add(type='SUN', location=SUN*10)
    light = bpy.context.object
    light.name = 'Fixed northwest sun'
    light.rotation_euler = (-SUN).to_track_quat('-Z', 'Y').to_euler()
    light.data.energy = 3
    light.data.angle = 0.08
    bpy.ops.object.light_add(type='AREA', location=(2, -4, 6))
    light = bpy.context.object
    light.name = 'Soft sky fill'
    light.rotation_euler = (-light.location).to_track_quat('-Z', 'Y').to_euler()
    light.data.energy = 180
    light.data.shape = 'DISK'
    light.data.size = 6
    global STEEL, PAINT, DARK, RUBBER, BRASS, WHITE, ORANGE, CYAN, RED, CONCRETE, SCAR
    STEEL = material('Brushed gunmetal', (0.26, .30, .31), .72, .4)
    PAINT = material('Worn olive enamel', (.23, .28, .16), .35, .6)
    DARK = material('Recesses and barrel bores', (.022, .028, .031), .35, .7)
    RUBBER = material('Rubber seals', (.035, .04, .035), 0, .9)
    BRASS = material('Hazard ochre and cartridge brass', (.68, .43, .065), .45, .4)
    WHITE = material('Aircraft ceramic pale grey', (.61, .66, .61), .22, .53)
    ORANGE = material('Hot exhaust', (1, .21, .015), 0, .35, 4)
    CYAN = material('Tracking optics', (.03, .45, .52), .2, .15, 1)
    RED = material('Warning lamps', (.7, .018, .005), 0, .4, 3)
    CONCRETE = material('Concrete plinth', (.22, .23, .21), 0, .92)
    SCAR = material('Edge wear', (.4, .38, .28), .55, .8)
    return scene


def bolts(radius, z, parent=None, count=12):
    for i in range(count):
        a = i*TAU/count
        cylinder('Anchor bolt', (math.sin(a)*radius, math.cos(a)*radius, z), .042, .035, STEEL, parent, vertices=6)


def foundation(width, z=0.16):
    box('Concrete footing', (0, 0, z/2), (width, width, z), CONCRETE, bevel=.12)
    for x in (-1, 1):
        for y in (-1, 1):
            box('Outrigger foot', (x*width*.37, y*width*.37, .24), (.42, .42, .22), STEEL)
            cylinder('Foundation bolt', (x*width*.37, y*width*.37, .38), .07, .06, BRASS, vertices=6)
    cylinder('Fixed rotation race', (0, 0, .4), width*.32, .45, STEEL)
    cylinder('Rubber slewing seal', (0, 0, .64), width*.3, .08, RUBBER)
    bolts(width*.275, .7)
    for i in range(5):
        box('Hazard stripe', (-.65+i*.29, -width*.45, .18), (.13, .17, .015), BRASS, bevel=0)


def aa():
    foundation(2.55)
    head = pivot('AA azimuth')
    cylinder('Turret lower crown', (0, 0, .83), .73, .27, PAINT, head)
    box('Armored rotating head', (0, 0, 1.13), (1.18, 1.04, .51), PAINT, head, .11)
    for x in (-.67, .67):
        box('Ammo cassette', (x, -.1, 1.05), (.25, .7, .5), STEEL, head)
        for j in range(4):
            box('Ammo cooling groove', (x, -.39+j*.17, 1.315), (.2, .052, .012), DARK, head, 0)
    barrels = pivot('AA recoil', parent=head)
    for x in (-.32, .32):
        cylinder('Cannon breech', (x, .52, 1.32), .16, .65, STEEL, barrels, (0,1,0))
        cylinder('Twin cannon barrel', (x, 1.12, 1.32), .095, 1.0, STEEL, barrels, (0,1,0))
        cylinder('Muzzle brake', (x, 1.64, 1.32), .135, .22, DARK, barrels, (0,1,0))
        cylinder('Muzzle rim', (x, 1.76, 1.32), .133, .035, STEEL, barrels, (0,1,0))
        cylinder('Deep bore', (x, 1.782, 1.32), .079, .01, DARK, barrels, (0,1,0))
        for j in range(4):
            cylinder('Barrel cooling collar', (x, .79+j*.13, 1.32), .118, .045, DARK, barrels, (0,1,0))
        flame = cone('Muzzle flash', (x, 1.96, 1.32), .13, .018, .36, ORANGE, barrels, (0,1,0))
        flame['flash'] = True
    box('Optical tracker', (0, .22, 1.52), (.3,.38,.25), STEEL, head)
    cylinder('Tracker lens', (0,.43,1.52), .085,.03,CYAN,head,(0,1,0))
    box('Access hatch', (0,-.23,1.413),(.46,.35,.04),STEEL,head)
    return head


def abm():
    foundation(2.85)
    head = pivot('ABM azimuth')
    cylinder('Launcher crown', (0,0,.85), .8,.3, PAINT,head)
    for x in (-.72,.72):
        box('Trunnion support', (x,0,1.16),(.2,.55,.76), STEEL,head)
        cylinder('Elevation pivot',(x,0,1.47),.19,.26,BRASS,head,(1,0,0))
    rack = pivot('ABM elevation',(0,0,1.45),head)
    rack.rotation_euler.x = math.radians(-52)
    for x in (-.46,0,.46):
        for y in (-.29,.29):
            box('Interceptor launch cell',(x,y,0),(.42,.5,1.65),PAINT,rack,.05)
            box('Cell dark aperture',(x,y,.84),(.33,.40,.025),DARK,rack)
            cylinder('Missile nose in cell',(x,y,.85),.105,.07,WHITE,rack)
            box('Cell brass lip',(x,y-.22,.86),(.40,.045,.045),BRASS,rack)
            for z in (-.55,.43):
                box('Canister retention band',(x,y,z),(.44,.52,.065),STEEL,rack)
    box('Tracking computer',(0,-.61,1.05),(.58,.3,.34),STEEL,head)
    cylinder('Tracking receiver',(.95,-.3,1.51),.20,.13,CYAN,head,(0,1,0))
    launch = pivot('ABM launch projectile',(0,.5,1.4),head)
    missile(launch, small=True)
    return head


def radar():
    foundation(2.45)
    box('Stationary radar cabinet',(0,-.25,.98),(.9,.78,.65),PAINT)
    cylinder('Fixed mast',(0,0,1.42),.23,1.55,STEEL)
    for x in (-.55,.55):
        box('Cooling radiator',(x,-.3,.91),(.18,.7,.58),DARK)
        for i in range(6):
            box('Radiator fin',(x,-.58+i*.11,.92),(.23,.037,.52),STEEL)
    head=pivot('Radar antenna azimuth',(0,0,2.07))
    cylinder('Antenna rotation bearing',(0,0,0),.35,.16,BRASS,head)
    box('Antenna backing',(0,0,.55),(2.35,.18,.88),STEEL,head)
    box('Active phased array face',(0,.105,.55),(2.18,.035,.73),DARK,head)
    for x in range(12):
        for z in range(4):
            box('Antenna emitter',(x*.175-.963,.14,z*.17+.30),(.115,.065,.09),PAINT,head,.009)
    for x in (-1.12,1.12):
        cylinder('Antenna guard',(x,0,.57),.034,1.1,BRASS,head)
    box('Back signal processor',(0,-.24,.5),(.52,.36,.45),PAINT,head)
    cylinder('Identification beacon',(0,0,1.06),.065,.15,RED,head)
    return head


def drone(role):
    root=pivot(role+' airframe')
    span={'recon':1.9,'strike':2.1,'heavy':2.3}[role]
    length={'recon':1.9,'strike':2.25,'heavy':2.2}[role]
    radius={'recon':.15,'strike':.21,'heavy':.28}[role]
    cylinder('Streamlined fuselage',(0,0,.8),radius,length*.65,WHITE,root,(0,1,0))
    cone('Nose fairing',(0,length*.43,.8),radius,0,length*.3,WHITE,root,(0,1,0))
    cone('Tapered tail',(0,-length*.41,.8),.07,radius,length*.26,PAINT,root,(0,1,0))
    if role=='strike':
        xy=[(-span/2,-.6),(-.18,.69),(.18,.69),(span/2,-.6),(.20,-.44),(-.2,-.44)]
    else:
        xy=[(-span/2,-.10),(-span/2,.2),(-.16,.38),(.16,.38),(span/2,.2),(span/2,-.10)]
    plate('Main lifting wing',xy,.8,.075,PAINT if role=='strike' else WHITE,root)
    plate('Tail stabilizer',[(-.5,-.82),(-.37,-.59),(.37,-.59),(.5,-.82)],.85,.05,STEEL,root)
    fin=plate('Vertical rudder',[(-.15,-.13),(.12,-.13),(.03,.25)],0,.045,PAINT,root)
    fin.rotation_euler.x=math.pi/2
    fin.location=(0,-.83,1.03)
    rotor=pivot('Propeller',(0,-length*.6,.8),root)
    rotor.rotation_euler.x=math.pi/2
    cylinder('Propeller hub',(0,0,0),.075,.16,STEEL,rotor)
    for a in (0,TAU/3,TAU*2/3):
        blade=box('Physical propeller blade',(-math.sin(a)*.18,math.cos(a)*.18,0),(.065,.40,.035),DARK,rotor,.02)
        blade.rotation_euler.z=a
    cylinder('Underside camera',(0,.48,.60),.12,.14,DARK,root)
    cylinder('Camera glass',(0,.5,.51),.075,.02,CYAN,root)
    for x in (-span*(.39 if role=='strike' else .43),span*(.39 if role=='strike' else .43)):
        box('Wing marking',(x,-.44 if role=='strike' else 0,.844),(.10,.10 if role=='strike' else .21,.01),BRASS,root,0)
    if role=='heavy':
        for x in (-.52,.52):
            cylinder('Payload pod',(x,-.13,.61),.13,.78,PAINT,root,(0,1,0))
            cone('Pod nose',(x,.35,.61),.13,0,.2,STEEL,root,(0,1,0))
    return root


def missile(parent=None, small=False):
    root=parent or pivot('Missile airframe')
    r=.10 if small else .18
    length=1.2 if small else 2.0
    cylinder('Rocket body',(0,0,.75),r,length,WHITE,root,(0,1,0))
    cone('Ogive nose',(0,length*.65,.75),r,0,length*.30,PAINT,root,(0,1,0))
    cylinder('Exhaust nozzle',(0,-length*.53,.75),r*.85,.15,DARK,root,(0,1,0))
    for i in range(4):
        a=i*math.pi/2
        fin=plate('Rocket guidance fin',[(0,-length*.48),(.35,-length*.55),(.12,-length*.20),(0,-length*.2)],0,.035,STEEL,root)
        fin.rotation_euler.y=a
        fin.location.z=.75
    cylinder('Recognition band',(0,.21,.75),r*1.03,.14,BRASS,root,(0,1,0))
    return root


def infrastructure(kind):
    box('Reinforced concrete apron',(0,0,.1),(4.8,4.4,.2),CONCRETE,bevel=.15)
    for x in (-2.1,2.1):
        for y in (-1.8,1.8):
            box('Ground lamp housing',(x,y,.26),(.19,.2,.3),STEEL)
            box('Apron lamp',(x,y,.43),(.13,.14,.04),BRASS)
    if kind=='airfield':
        box('Hangar lower block',(0,.86,.48),(3.15,1.85,.65),PAINT,bevel=.1)
        box('Hangar roof',(0,.86,.87),(3.35,2,.18),STEEL,bevel=.10)
        for x in (-1.45,1.45):
            box('Door jamb',(x,-.15,.54),(.18,.21,.82),BRASS)
        box('Hangar darkness',(0,-.085,.5),(2.7,.025,.7),DARK)
        gate=pivot('Hangar sliding door')
        for x in (-.68,.68):
            box('Hangar door',(x,-.13,.52),(1.32,.10,.72),PAINT,gate)
        fan=pivot('Airfield cooling fan',(-1,.85,1.0))
        cylinder('Ventilator rim',(0,0,0),.36,.11,DARK,fan)
        for a in (0,TAU/3,TAU*2/3):
            blade=box('Ventilator blade',(-math.sin(a)*.15,math.cos(a)*.15,.07),(.09,.32,.035),STEEL,fan)
            blade.rotation_euler.z=a
        for i in range(6):
            box('Apron center marking',(0,-.5-i*.24,.211),(.065,.13,.012),WHITE,bevel=0)
        for x in (-1.6,1.6):
            box('Runway side line',(x,-1.3,.213),(.06,1.1,.012),BRASS,bevel=0)
    else:
        cylinder('Launch well armored ring',(0,0,.34),1.25,.34,STEEL)
        cylinder('Launch well darkness',(0,0,.53),1.03,.08,DARK)
        door=pivot('Silo hatch')
        box('Sliding armored silo hatch',(0,0,.61),(1.85,1.75,.16),PAINT,door,.1)
        for x in (-.7,-.35,0,.35,.7):
            box('Hatch reinforcing rib',(x,0,.72),(.08,1.75,.07),STEEL,door)
        box('Service bunker',(-1.75,.6,.54),(.8,2.25,.83),PAINT)
        for i in range(5):
            box('Bunker cooling grille',(-1.75,.1+i*.23,.973),(.57,.1,.023),DARK)
        box('Hydraulic power pack',(1.72,.8,.48),(.62,1.1,.63),STEEL)
        for y in (-.7,.7):
            cylinder('Hatch actuator',(1.52,y,.49),.075,1.03,BRASS,axis=(0,1,0))
        rocket=pivot('Silo rising missile',(0,0,.0))
        missile(rocket)
        rocket.rotation_euler.x=math.pi/2
        holdout=bpy.data.materials.new('Launch ground holdout')
        holdout.use_nodes=True
        nodes=holdout.node_tree.nodes
        nodes.clear()
        shader=nodes.new('ShaderNodeHoldout')
        output=nodes.new('ShaderNodeOutputMaterial')
        holdout.node_tree.links.new(shader.outputs[0],output.inputs['Surface'])
        box('Ground launch holdout',(0,0,.54),(100,100,.02),holdout,bevel=0)
    return None


def build_model(kind):
    global OBJECTS, MOVERS
    OBJECTS=[]
    MOVERS={}
    scene=setup()
    if kind=='aa': aa()
    elif kind=='abm': abm()
    elif kind=='radar': radar()
    elif kind in ('recon','strike','heavy','wreck'):
        root=drone('strike' if kind=='wreck' else kind)
        if kind=='wreck':
            for obj in OBJECTS:
                if obj.parent==root: obj.location.z-=.8
            MOVERS['Propeller'].location.z-=.8
            root.location.z=.8
            WHITE.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.24,.25,.21,1)
    elif kind in ('airfield','ballistic-site'): infrastructure(kind)
    elif kind in ('ballistic-missile','interceptor'): missile(small=kind=='interceptor')
    elif kind=='flak-round':
        root=pivot('Bullet')
        cylinder('Tracer body',(0,0,.75),.07,.5,BRASS,root,(0,1,0))
        cone('Glowing tracer',(0,-.4,.75),.01,.09,.35,ORANGE,root,(0,1,0))
    elif kind=='flak-magazine':
        box('Ammunition cassette',(0,0,.5),(1.3,.7,.6),PAINT)
        for i in range(6):
            cylinder('Brass cartridge',(-.5+i*.2,0,.91),.075,.5,BRASS)
            cone('Projectile tip',(-.5+i*.2,0,1.24),.075,0,.16,STEEL)
    return scene


def ancestor(obj, name):
    while obj:
        if obj.name==name: return True
        obj=obj.parent
    return False


def animate(kind,direction,phase,mode):
    for o in OBJECTS: o.hide_render=False
    if kind=='aa':
        MOVERS['AA azimuth'].rotation_euler.z=-direction*TAU/64
        MOVERS['AA recoil'].location.y=-(0,.08,.17,.04)[phase%4] if mode=='attack' else 0
        for o in OBJECTS:
            moving=ancestor(o,'AA azimuth')
            o.hide_render=(moving if mode=='base' else not moving) if mode in ('base','head','attack') else False
            if o.get('flash'): o.hide_render=mode!='attack' or phase%4 not in (1,2)
    elif kind=='abm':
        MOVERS['ABM azimuth'].rotation_euler.z=-direction*TAU/64
        MOVERS['ABM launch projectile'].rotation_euler.x=math.radians(38)
        MOVERS['ABM launch projectile'].scale=(.65,.65,.65)
        MOVERS['ABM launch projectile'].location.y=.35+phase*.065
        MOVERS['ABM launch projectile'].location.z=1.05+phase*.028
        for o in OBJECTS:
            launch=ancestor(o,'ABM launch projectile')
            moving=ancestor(o,'ABM azimuth')
            o.hide_render=(moving if mode=='base' else not moving) if mode in ('base','head') else False
            if launch: o.hide_render=mode!='launch'
            elif mode=='launch': o.hide_render=True
    elif kind=='radar':
        MOVERS['Radar antenna azimuth'].rotation_euler.z=-phase*TAU/32
        if mode=='alert':
            for o in OBJECTS:
                o.hide_render=o.name.split('.')[0]!='Identification beacon'
            beacon=next(o for o in OBJECTS if o.name.startswith('Identification beacon'))
            beacon.scale=(1+phase/20,1+phase/20,1+phase/30)
    elif kind in ('recon','strike','heavy','wreck'):
        root=MOVERS[('strike' if kind=='wreck' else kind)+' airframe']
        root.rotation_euler.z=-direction*TAU/(8 if kind=='wreck' else 16)
        MOVERS['Propeller'].rotation_mode='QUATERNION'
        MOVERS['Propeller'].rotation_quaternion=Quaternion((1,0,0),math.pi/2) @ Quaternion((0,0,1),phase*TAU/24)
        if kind=='wreck':
            root.rotation_euler.x=.22+phase*.075
            root.rotation_euler.y=.16+phase*.07
            root.rotation_euler.z-=phase*.11
            root.location.z=.8-phase*.025
            for o in OBJECTS:
                if o.name.startswith('Main lifting wing'): o.rotation_euler.y=.30
                if o.name.startswith('Nose fairing'): o.hide_render=True
                if o.name.startswith('Wing marking'): o.hide_render=True
    elif kind=='airfield':
        MOVERS['Airfield cooling fan'].rotation_euler.z=phase*TAU/48
        MOVERS['Hangar sliding door'].location.z=.15*(1-math.cos(phase*TAU/16))
        if mode=='overlay':
            for o in OBJECTS: o.hide_render=not(ancestor(o,'Airfield cooling fan') or ancestor(o,'Hangar sliding door'))
        if mode=='base':
            for o in OBJECTS: o.hide_render=ancestor(o,'Airfield cooling fan') or ancestor(o,'Hangar sliding door')
    elif kind=='ballistic-site':
        MOVERS['Silo hatch'].location.x=(phase/19*1.85 if mode=='launch' else .10*(1-math.cos(phase*TAU/16)))
        MOVERS['Silo rising missile'].location.y=.75
        MOVERS['Silo rising missile'].location.z=-1.65+phase/19*2.1
        for o in OBJECTS:
            hatch=ancestor(o,'Silo hatch'); rocket=ancestor(o,'Silo rising missile')
            if mode=='base': o.hide_render=hatch or rocket
            elif mode=='overlay': o.hide_render=not hatch
            elif mode=='launch': o.hide_render=not(hatch or rocket)
            if rocket and mode!='launch': o.hide_render=True
            if o.name=='Ground launch holdout': o.hide_render=mode!='launch'
    bpy.context.view_layer.update()


def render_plan():
    plans=[]
    def add(kind,name,size,directions=1,frames=1,columns=1,mode='full',scale=4.8,shadow=None):
        plans.append(dict(kind=kind,name=name,size=size,directions=directions,frames=frames,columns=columns,mode=mode,scale=scale,shadow=shadow))
    for kind,size in [('aa',160),('abm',192)]:
        prefix='aa-turret' if kind=='aa' else 'abm-battery'
        add(kind,prefix+'-base',size,mode='base',shadow=prefix+'-base-shadow')
        add(kind,prefix+'-head-prepared',size,64,1,8,'head',shadow=prefix+'-head-prepared-shadow')
    add('aa','aa-turret-head-attacking',160,64,4,16,'attack',shadow='aa-turret-head-attacking-shadow')
    add('abm','abm-battery-launch-sheet',192,1,12,4,'launch')
    add('radar','early-warning-radar-sheet',192,1,32,8,scale=5.1,shadow='early-warning-radar-shadow-sheet')
    add('radar','radar-alert-overlay-sheet',192,1,12,4,'alert',5.1)
    for kind,size in [('recon',72),('strike',80),('heavy',96)]:
        add(kind,kind+'-drone-sheet',size,16,8,16,scale=3.65,shadow=kind+'-drone-shadow-sheet')
    for direction in range(8):
        add('wreck',f'falling-wreck-{direction}',96,1,12,12,scale=4.2,shadow=f'falling-wreck-shadow-{direction}')
        plans[-1]['wreck_direction']=direction
    for kind in ('airfield','ballistic-site'):
        add(kind,kind+'-base',320,mode='base',scale=6.8,shadow=kind+'-shadow')
        add(kind,kind+'-overlay-sheet',320,1,16,4,'overlay',6.8)
    add('ballistic-site','ballistic-site-launch-sheet',320,1,20,5,'launch',6.8)
    add('ballistic-missile','ballistic-missile',128,scale=3.65)
    add('interceptor','interceptor',128,scale=2.8)
    add('flak-round','flak-round',32,scale=1.5)
    for kind in ('aa','abm','radar','recon','strike','heavy','airfield','ballistic-site','ballistic-missile','interceptor','flak-magazine'):
        name={'aa':'aa-turret','abm':'abm-battery','radar':'early-warning-radar'}.get(kind,kind+('-drone' if kind in ('recon','strike','heavy') else ''))
        add(kind,'icon-'+name,128,scale=6.4 if kind in ('airfield','ballistic-site') else (5.1 if kind=='radar' else 4.2))
    return plans


def shadow_polygons(scene):
    """Project actual transformed mesh faces onto z=0 along the fixed sun.

    The compositing stage supersamples these world-space cast silhouettes; no
    image rotation or screen-space shadow offset is used.
    """
    polys=[]
    for obj in OBJECTS:
        if obj.hide_render or obj.get('flash'): continue
        coords=[]
        for vertex in obj.data.vertices:
            v=obj.matrix_world@vertex.co
            v-=SUN*(v.z/SUN.z)
            uv=world_to_camera_view(scene,scene.camera,v)
            coords.append((round(uv.x,6),round(1-uv.y,6)))
        polys.extend([[coords[i] for i in poly.vertices] for poly in obj.data.polygons])
    return polys


def main():
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser=argparse.ArgumentParser()
    parser.add_argument('--pilot',action='store_true')
    parser.add_argument('--kind')
    parser.add_argument('--force',action='store_true')
    args=parser.parse_args(argv)
    source_hash=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    out=ROOT/'graphics'/'renders'
    out.mkdir(parents=True,exist_ok=True)
    models=ROOT/'graphics'/'models'; models.mkdir(parents=True,exist_ok=True)
    plans=render_plan()
    (out/'plan.json').write_text(json.dumps(plans,indent=2))
    metadata=dict(generator='Blender real geometry v1',sun=list(SUN),camera_location=[0,-10,12],camera_target=[0,0,.7],azimuth_convention='north +Y, clockwise, fixed camera and lights',shadow_method='world-space mesh projection onto ground along fixed sun',models={})
    for kind in dict.fromkeys(p['kind'] for p in plans):
        if args.kind and kind!=args.kind: continue
        if args.pilot and kind not in ('aa','abm','radar'): continue
        scene=build_model(kind)
        model_plans=[p for p in plans if p['kind']==kind]
        metadata['models'][kind]=dict(meshes=len(OBJECTS),vertices=sum(len(o.data.vertices) for o in OBJECTS),assemblies=list(MOVERS))
        scene.camera.data.ortho_scale=model_plans[0]['scale']
        scene.render.resolution_x=scene.render.resolution_y=model_plans[0]['size']*2
        animate(kind,0,0,'full')
        bpy.ops.wm.save_as_mainfile(filepath=str(models/(kind+'.blend')))
        for p in model_plans:
            if args.pilot and p['mode'] not in ('head','full','base'): continue
            folder=out/p['name'];folder.mkdir(exist_ok=True)
            scene.camera.data.ortho_scale=p['scale']
            scene.render.resolution_x=scene.render.resolution_y=p['size']*2
            for direction in range(p['directions']):
                for phase in range(p['frames']):
                    index=direction*p['frames']+phase
                    if args.pilot and (direction not in (0,8,16,24,32,40,48,56) or phase not in (0,4,8,12,16,20,24,28)):continue
                    path=folder/f'{index:04d}.png'
                    stamp=path.with_suffix('.source.sha256')
                    if path.exists() and stamp.exists() and stamp.read_text()==source_hash and not args.force: continue
                    animate(kind,p.get('wreck_direction',direction),phase,p['mode'])
                    scene.render.filepath=str(path)
                    bpy.ops.render.render(write_still=True)
                    if p['shadow']:
                        path.with_suffix('.shadow.json').write_text(json.dumps(shadow_polygons(scene),separators=(',',':')))
                    stamp.write_text(source_hash)
                    print(f'ASSET_FRAME {p["name"]} {index+1}/{p["directions"]*p["frames"]}',flush=True)
    previous=out/'geometry.json'
    if previous.exists():
        saved=json.loads(previous.read_text());saved['models'].update(metadata['models']);metadata=saved
    previous.write_text(json.dumps(metadata,indent=2))


if __name__=='__main__': main()
