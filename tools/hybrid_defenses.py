"""Editable hybrid defense assemblies retaining imported geometry and UV detail.

All directions are clockwise from north +Y. Geometry uses world-sized coordinates;
head and recoil empties have independent transforms and never own base objects.
"""
from pathlib import Path
import math
import bpy
import bmesh
from mathutils import Matrix, Vector
from hybrid_geometry import OBJECTS, box, cylinder, ring, cable, beam, bolted_panel, beacon
from hybrid_materials import palette, solid, finish_imported

ROOT = Path(__file__).resolve().parents[1]


def empty(name, parent=None):
    obj=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(obj)
    obj.parent=parent
    return obj


def imported(candidate, scale=.5, rotate=0, offset=(0,0,0)):
    with bpy.data.libraries.load(str(ROOT/'graphics/imported'/candidate/'normalized.blend'),link=False) as (src,dst):
        dst.objects=src.objects
    meshes=[]
    transform=Matrix.Translation(Vector(offset))@Matrix.Rotation(rotate,4,'Z')@Matrix.Scale(scale,4)
    # Appended parents are intentionally evaluated before unlinking so normalized
    # source coordinates survive without importing its cameras or world setup.
    for obj in dst.objects:
        if obj and obj.type=='MESH':
            bpy.context.collection.objects.link(obj)
            world=obj.matrix_world.copy()
            obj.data=obj.data.copy()
            obj.data.transform(transform@world)
            obj.parent=None
            obj.matrix_world=Matrix.Identity(4)
            meshes.append(obj)
    for obj in dst.objects:
        if obj and obj not in meshes:
            bpy.data.objects.remove(obj,do_unlink=True)
    return meshes


def split(obj,name,point,normal,upper):
    """Bisect source geometry with preserved loop UVs and close the real cut."""
    mesh=obj.data.copy()
    bm=bmesh.new();bm.from_mesh(mesh)
    cut=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        dist=1e-5,plane_co=Vector(point),plane_no=Vector(normal),
        clear_inner=upper,clear_outer=not upper)
    edges=[e for e in cut['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
    if edges:
        try: bmesh.ops.holes_fill(bm,edges=edges,sides=0)
        except RuntimeError: pass
    bm.to_mesh(mesh);bm.free();mesh.update()
    result=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(result);OBJECTS.append(result)
    return result


def tint_source(obj,name,tint):
    for i,old in enumerate(list(obj.data.materials)):
        mat=old.copy();mat.name=name+' / retained source UV'
        for node in mat.node_tree.nodes:
            if node.type=='BSDF_PRINCIPLED':
                node.inputs['Metallic'].default_value=.38
                node.inputs['Roughness'].default_value=.54
                inp=node.inputs['Base Color']
                if inp.is_linked:
                    old_link=inp.links[0].from_socket
                    mix=mat.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY'
                    mix.inputs[0].default_value=.72;mix.inputs[2].default_value=(*tint,1)
                    mat.node_tree.links.new(old_link,mix.inputs[1]);mat.node_tree.links.new(mix.outputs[0],inp)
        obj.data.materials[i]=mat


def footing(m,width=2.9,depth=2.9):
    box('Foundation / lower chamfered casting',(0,0,.09),(width,depth,.18),m['steel'],bevel=.16)
    box('Foundation / inset armored deck',(0,0,.20),(width-.14,depth-.14,.12),m['graphite'],bevel=.10)
    for sx in (-1,1):
        for sy in (-1,1):
            x=sx*(width/2-.23);y=sy*(depth/2-.23)
            bolted_panel('Foundation / anchor shoe',(x,y,.26),(.42,.42,.13),m,'hazard')
            cylinder('Foundation / hex hold-down',(x,y,.38),.075,.11,m['steel'],vertices=6)
            cylinder('Foundation / exposed anchor stud',(x,y,.46),.033,.08,m['edge'],vertices=12)
    for sx in (-1,1):
        cable('Foundation / perimeter feeder',[(sx*(width/2-.16),-.85,.3),(sx*(width/2-.1),0,.3),(sx*(width/2-.16),.85,.3)],.024,m['copper'])
        for y in (-.55,.55):
            box('Foundation / conduit saddle',(sx*(width/2-.12),y,.31),(.09,.07,.075),m['steel'])
    for y in (-depth/2+.1,depth/2-.1):
        for x in (-.8,0,.8):
            box('Foundation / worn edge segment',(x,y,.18),(.45,.035,.065),m['edge'],bevel=.008)


def race(m,z,radius,parent=None):
    cylinder('Azimuth / fixed housing',(0,0,z),radius,.14,m['steel'],parent)
    ring('Azimuth / exposed race',(0,0,z+.08),radius*.94,radius*.82,.055,m['edge'],parent)
    ring('Azimuth / labyrinth seal',(0,0,z+.115),radius*.81,radius*.68,.045,m['dark'],parent)
    for i in range(24):
        a=i*math.tau/24
        cylinder('Azimuth / race bolt',(math.sin(a)*radius*.89,math.cos(a)*radius*.89,z+.125),.022,.026,m['steel'],parent,vertices=6)
    for i in range(16):
        a=i*math.tau/16
        ob=box('Azimuth / encoder tooth',(math.sin(a)*radius*.77,math.cos(a)*radius*.77,z+.145),(.07,.08,.07),m['ochre'] if i%4==0 else m['steel'],parent,bevel=.01)
        ob.rotation_euler.z=-a


def service(m,location,size=(.48,.65,.55),parent=None):
    x,y,z=location;w,d,h=size
    box('Service / cabinet casing',location,size,m['steel'],parent,bevel=.055)
    bolted_panel('Service / access hatch',(x,y,z+h/2),(.9*w,.9*d,.035),m,'hatch',parent)
    box('Service / recessed cooling bank',(x,y-d/2-.016,z),(w*.8,.025,h*.67),m['dark'],parent)
    for i in range(6):
        box('Service / physical cooling louvre',(x,y-d/2-.043,z-h*.27+i*h*.105),(w*.78,.055,.017),m['edge'],parent,bevel=.006)
    box('Service / status optic',(x+w*.28,y-d/2-.045,z+h*.37),(.055,.018,.023),m['cyan'],parent,bevel=.006)
    cable('Service / flexible feed',[(x+w/2,y,z-.1),(x+w/2+.07,y-.15,z-.19),(x+w/2+.08,y-.35,.3)],.024,m['rubber'],parent)


def cone(name,location,radius,depth,material,parent,axis):
    bpy.ops.mesh.primitive_cone_add(vertices=24,radius1=radius,radius2=0,depth=depth,location=location)
    obj=bpy.context.object;obj.name=name;obj.parent=parent
    obj.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler()
    obj.data.materials.append(material);OBJECTS.append(obj)
    return obj


def build_aa(m,movers,effects):
    footing(m,3.0,2.9)
    source=imported('zenitka',offset=(0,.44,.24))[0]
    base=split(source,'AA / original fixed pedestal',(0,0,1.10),(0,0,1),False)
    rawhead=split(source,'AA / original upper assembly',(0,0,1.10),(0,0,1),True)
    bpy.data.objects.remove(source,do_unlink=True)
    head=movers['head']=empty('AA / azimuth drive')
    recoil=movers['recoil']=empty('AA / recoil slide',head)
    point=(0,1.43,2.96);axis=Vector((0,.81,.586))
    hull=split(rawhead,'AA / retained armored cradle',point,axis,False);hull.parent=head
    barrel=split(rawhead,'AA / recoiling original muzzle',point,axis,True);barrel.parent=recoil
    OBJECTS.remove(rawhead);bpy.data.objects.remove(rawhead,do_unlink=True)
    tint_source(base,'AA graphite pedestal',(.31,.35,.31))
    tint_source(hull,'AA olive armor',(.46,.51,.32))
    tint_source(barrel,'AA muzzle steel',(.24,.27,.27))
    race(m,1.065,1.0)
    cylinder('AA / closed rotating belly',(0,0,1.16),.73,.18,m['steel'],head)
    ring('AA / muzzle slide collar',point,.115,.073,.11,m['edge'],head).rotation_euler=axis.to_track_quat('Z','Y').to_euler()
    for sx in (-1,1):
        # Atlas access panel sits on the original broad armor shoulder.
        panel=box('AA / shoulder service plate',(sx*.65,-.20,1.91),(.44,.59,.055),m['olive'],head,bevel=.02)
        for y in (-.40,.08):
            cylinder('AA / shoulder bolt',(sx*.65,y,1.955),.025,.026,m['edge'],head,vertices=6)
        box('AA / shoulder cooling recess',(sx*.65,-.20,1.946),(.31,.34,.018),m['dark'],head,.005)
        for slot in range(7):
            box('AA / shoulder heat exchanger fin',(sx*.65,-.345+slot*.048,1.966),(.295,.021,.032),m['edge'],head,.006)
        cylinder('AA / elevation trunnion',(sx*.94,-.13,1.62),.19,.10,m['steel'],head,axis=(1,0,0))
        cylinder('AA / trunnion bright retaining ring',(sx*.998,-.13,1.62),.145,.023,m['edge'],head,axis=(1,0,0))
        cylinder('AA / trunnion hub',(sx*1.015,-.13,1.62),.105,.03,m['graphite'],head,axis=(1,0,0))
        cable('AA / protected elevation hose',[(sx*.92,-.1,1.3),(sx*1.02,-.42,1.37),(sx*.91,-.65,1.72)],.035,m['rubber'],head)
        for j in range(5):
            cylinder('AA / exposed feed roller',(sx*.88,-.61+j*.075,1.32),.035,.09,m['ochre'],head,axis=(1,0,0),vertices=16)
    for side in (-1,1):
        plate=box('AA / shroud inspection cover',(side*.155,.70,2.62),(.026,.49,.11),m['graphite'],head,.012)
        plate.rotation_euler.x=.63
        for y,z in ((.5,2.48),(.86,2.74)):
            cylinder('AA / shroud clamp screw',(side*.175,y,z),.022,.022,m['edge'],head,axis=(1,0,0),vertices=6)
    service(m,(-.80,-.90,.60),(.53,.45,.48))
    service(m,(.83,-.89,.60),(.43,.45,.48))
    box('AA / optical tracker hood',(-.48,.38,1.52),(.23,.25,.22),m['steel'],head)
    cylinder('AA / tracker lens',(-.48,.518,1.52),.073,.03,m['cyan'],head,axis=(0,1,0))
    beacon('AA / warning beacon',(.78,-.62,1.87),m,head)
    muzzle=Vector((0,1.80,3.205))
    flash=empty('AA / muzzle flash',recoil);movers['flash']=flash
    cone('AA / hot muzzle core',muzzle+axis*.055,.025,.16,solid('hot muzzle plasma',(1,.64,.17),emission=18),flash,axis)
    cone('AA / muzzle flare',muzzle+axis*.05,.050,.14,solid('muzzle flare plasma',(1,.12,.005),emission=12),flash,axis)
    effects.extend([o for o in OBJECTS if o.parent==flash])
    return {'source':'zenitka','recoil_axis':list(axis),'recoil_distance':.11,'ortho_scale':6.5}


def build_abm(m,movers,effects):
    footing(m,3.1,3.1)
    source=imported('nasams',rotate=-.144,offset=(-.045,0,.24))[0]
    # The spatial boundary is below every canister; it includes the elevation
    # actuator and entire rack, irrespective of duplicated OBJ seam vertices.
    base=split(source,'ABM / original fixed deployment frame',(0,0,.99),(0,0,1),False)
    rack=split(source,'ABM / original six-cell rack and elevation mount',(0,0,.99),(0,0,1),True)
    bpy.data.objects.remove(source,do_unlink=True)
    head=movers['head']=empty('ABM / azimuth drive');rack.parent=head
    tint_source(base,'ABM fixed frame',(.34,.38,.32));tint_source(rack,'ABM canister paint',(.54,.59,.44))
    race(m,.91,.80)
    cylinder('ABM / closed rotating pedestal',(0,0,1.04),.49,.19,m['steel'],head)
    for sx in (-1,1):
        beam('ABM / trunnion gusset',(sx*.47,-.3,1.02),(sx*.47,.12,1.47),.11,m['steel'],head)
        cylinder('ABM / elevation pivot',(sx*.50,.07,1.43),.13,.12,m['edge'],head,axis=(1,0,0))
    axis=Vector((0,.875,.484)).normalized();up=Vector((0,-axis.z,axis.y))
    orientation=axis.to_track_quat('Y','Z').to_euler()
    centers=[];doors=[]
    for row in range(2):
        for col in range(3):
            front=Vector(((col-1)*.375,.91+row*.182,2.295-row*.329))
            centers.append(list(front))
            rim=box('ABM / cell %d armored rim'%(row*3+col+1),front+axis*.012,(.342,.042,.342),m['steel'],head,.014);rim.rotation_euler=orientation
            door=empty('ABM / cell %d blast-door hinge'%(row*3+col+1),head)
            door.location=front-up*.15+axis*.041
            panel=box('ABM / cell %d launch lid'%(row*3+col+1),up*.15,(.294,.023,.294),m['graphite'],door,.012);panel.rotation_euler=orientation
            # A real crossed strengthening rib remains legible at sprite size.
            for s in (-1,1):
                a=up*.15+Vector((-.12,0,0))-up*.12*s
                b=up*.15+Vector((.12,0,0))+up*.12*s
                beam('ABM / lid diagonal rib',a+axis*.02,b+axis*.02,.016,m['edge'],door)
            doors.append(door)
            for back in (.35,1.35):
                center=front-axis*back
                for side in (-1,1):
                    rail=box('ABM / canister restraining strap',center+Vector((side*.169,0,0)),(.018,.065,.344),m['edge'],head,.007);rail.rotation_euler=orientation
                strap=box('ABM / upper restraining strap',center+up*.169,(.35,.065,.018),m['steel'],head,.006);strap.rotation_euler=orientation
            if row==0:
                hatch=box('ABM / long canister inspection panel',front-axis*.86+up*.175,(.23,.47,.014),m['olive'],head,.008);hatch.rotation_euler=orientation
    # Remove only the original front caps, using the known physical cell planes.
    bm=bmesh.new();bm.from_mesh(rack.data)
    caps=[]
    for face in bm.faces:
        center=face.calc_center_median()
        for front in map(Vector,centers):
            delta=center-front
            if abs(delta.dot(axis))<.05 and abs(delta.x)<.178 and abs(delta.dot(up))<.18 and abs(face.normal.dot(axis))>.85:
                caps.append(face);break
    bmesh.ops.delete(bm,geom=caps,context='FACES');bm.to_mesh(rack.data);bm.free();rack.data.update()
    for front in map(Vector,centers):
        cylinder('ABM / dark open canister interior',front-axis*.13,.14,.22,m['dark'],head,axis=axis,vertices=32)
    for index,door in enumerate(doors): movers['door_'+str(index)]=door
    service(m,(-.95,-.83,.65),(.49,.64,.63))
    service(m,(.86,-.93,.59),(.48,.48,.52))
    beacon('ABM / launch-ready beacon',(-1.1,.95,.49),m)
    for side in (-1,1):
        cable('ABM / hydraulic line',[(side*.62,-.65,.86),(side*.73,-.15,1.0),(side*.5,.05,1.35)],.023,m['copper'],head)
    rocket=movers['rocket']=empty('ABM / rapid launch rocket',head)
    cylinder('ABM / interceptor body',(0,0,0),.073,.58,m['white'],rocket,axis=axis,vertices=32)
    cone('ABM / interceptor nose',axis*.40,.073,.23,m['white'],rocket,axis)
    cylinder('ABM / interceptor tail',-axis*.29,.066,.04,m['steel'],rocket,axis=axis)
    for angle in range(4):
        a=angle*math.pi/2;side=Vector((math.cos(a),0,0))+up*math.sin(a)
        beam('ABM / interceptor fin',-axis*.16+side*.035,-axis*.26+side*.14,.018,m['steel'],rocket)
    flame=cone('ABM / launch exhaust',-axis*.50,.072,.4,m['amber'],rocket,-axis)
    glow=movers['launch_glow']=empty('ABM / launch-cell afterglow',head)
    cylinder('ABM / launch-cell light',(0,0,0),.075,.012,solid('launch-cell plasma',(1,.16,.012),emission=6),glow,axis=axis,vertices=24)
    effects.extend([o for o in OBJECTS if o.parent in (rocket,glow)])
    return {'source':'nasams','ortho_scale':5.8,'launch_axis':list(axis),'cell_centers':centers}


def build_radar(m,movers,effects):
    footing(m,2.9,2.9)
    source=imported('tps-59')
    antenna=next(o for o in source if 'antenna' in o.name)
    upper=split(antenna,'Radar / retained imported antenna lattice',(0,0,.48),(0,0,1),True)
    for obj in source: bpy.data.objects.remove(obj,do_unlink=True)
    # TPS-59's long array is reoriented horizontally while retaining its UVs,
    # real lattice and structural back. Lower vehicle hinges are replaced by
    # a purpose-built fixed pedestal and compact yaw carriage.
    transform=Matrix(((0,0,1,-1.43),(0,1,.32,-.40),(-1,0,0,1.88),(0,0,0,1)))
    upper.data.transform(transform)
    head=movers['head']=empty('Radar / azimuth drive');upper.parent=head
    tint_source(upper,'Radar original lattice',(.85,.89,.73))
    race(m,.44,.64)
    cylinder('Radar / fixed motor casing',(0,0,.80),.34,.65,m['steel'])
    for i in range(12):
        a=i*math.tau/12
        beam('Radar / motor cooling rib',(math.sin(a)*.32,math.cos(a)*.32,.54),(math.sin(a)*.32,math.cos(a)*.32,1.02),.034,m['edge'])
    ring('Radar / rotating shoulder bearing',(0,0,1.10),.37,.24,.08,m['edge'],head)
    for sx in (-1,1):
        beam('Radar / triangulated support',(sx*.25,0,1.09),(sx*.72,0,1.58),.10,m['steel'],head)
        beam('Radar / rear bracing',(sx*.25,-.23,1.15),(sx*.8,-.19,2.10),.06,m['steel'],head)
    # The array is a real framed lattice, with restrained ivory edge modules.
    for z in (1.35,2.41):
        beam('Radar / array perimeter rail',(-1.05,-.04,z),(1.06,-.04,z),.048,m['edge'],head)
    for x in (-1.04,1.04):
        beam('Radar / array end rail',(x,-.04,1.35),(x,-.04,2.41),.052,m['steel'],head)
    for x in (-.84,-.42,0,.42,.84):
        panel=box('Radar / replaceable ivory edge module',(x,-.073,2.32),(.35,.035,.13),m['aircraft'],head,.008)
        box('Radar / array calibration optic',(x,-.1,2.31),(.026,.018,.018),m['cyan'],head,.003)
    box('Radar / segmented ivory receiver face',(0,.225,1.89),(1.97,.035,.94),m['radar'],head,.015)
    for x in (-.33,.33):
        beam('Radar / receiver vertical joint',(x,.251,1.425),(x,.251,2.355),.014,m['steel'],head)
    for z in (1.735,2.045):
        beam('Radar / receiver horizontal joint',(-.975,.251,z),(.975,.251,z),.014,m['steel'],head)
    for x in (-.94,-.31,.31,.94):
        for z in (1.46,1.76,2.065,2.32):
            cylinder('Radar / receiver captive screw',(x,.256,z),.015,.018,m['steel'],head,axis=(0,1,0),vertices=6)
    cylinder('Radar / axis service hub',(0,-.20,1.87),.13,.13,m['edge'],head,axis=(0,1,0))
    cylinder('Radar / axis graphite cap',(0,-.28,1.87),.095,.03,m['steel'],head,axis=(0,1,0))
    service(m,(-.77,-.82,.59),(.66,.69,.58))
    service(m,(.59,-.78,.63),(.65,.74,.68))
    bolted_panel('Radar / maintenance tread',(0,.93,.32),(1.8,.58,.08),m,'tread')
    for sx in (-1,1):
        cable('Radar / pedestal power feed',[(sx*.72,-.6,.42),(sx*.50,-.4,.43),(sx*.28,-.21,.8)],.03,m['copper'])
    beam('Radar / communications mast',(1.0,.95,.35),(1.0,.95,1.36),.044,m['steel'])
    cylinder('Radar / mast insulator',(1.0,.95,1.06),.065,.18,m['white'])
    beam('Radar / whip antenna',(1.0,.95,1.4),(1.0,.95,1.87),.015,m['edge'])
    alert=movers['alert']=empty('Radar / alert beacon overlay')
    beacon('Radar / alert lamp',(1.0,.95,1.4),m,alert,color='amber')
    effects.extend([o for o in OBJECTS if o.parent==alert and 'glass' in o.name])
    return {'source':'tps-59','ortho_scale':5.4}


def build(kind):
    if kind not in ('aa','abm','radar'): raise ValueError('Unknown defense kind: '+kind)
    OBJECTS.clear();m=palette();movers={};effects=[]
    info=globals()['build_'+kind](m,movers,effects)
    for material in list(bpy.data.materials):
        if 'retained source UV' in material.name:
            finish_imported(material, .82 if kind=='aa' else .52,
                            (.28,.34,.36) if kind=='aa' else (.52,.59,.52))
    objects=list(OBJECTS)
    for obj in objects:
        moving=False;par=obj.parent
        while par:
            if par==movers.get('head'): moving=True
            par=par.parent
        obj['hybrid_part']='head' if moving else 'base'
        if obj in effects: obj['hybrid_part']='effect'
    result={'objects':objects,'movers':movers,'effects':effects,**info}
    animate(kind,0,0,'full',result)
    return result


def animate(kind,direction,phase,mode,result):
    movers=result['movers']
    movers['head'].rotation_euler.z=-math.tau*((phase%32)/32 if kind=='radar' and mode!='alert' else (direction%64)/64)
    for obj in result['objects']:
        part=obj.get('hybrid_part','base')
        visible=part!='effect'
        if mode=='base': visible=part=='base'
        elif mode in ('head','attack'): visible=part=='head'
        elif mode=='launch': visible=False
        elif mode=='alert': visible=False
        obj.hide_render=not visible;obj.hide_viewport=not visible
    if kind=='aa':
        recoil=(0,.11,.065,.018)[int(phase)%4] if mode=='attack' else 0
        movers['recoil'].location=-Vector(result['recoil_axis'])*recoil
        for obj in result['effects']:
            visible=mode=='attack' and int(phase)%4 in (0,1)
            obj.hide_render=not visible;obj.hide_viewport=not visible
    elif kind=='abm':
        p=int(phase)%12;cell=(int(phase)//12)%6
        for index in range(6): movers['door_'+str(index)].rotation_euler.x=0
        movers['rocket'].location=Vector(result['cell_centers'][cell])
        if mode in ('launch','launch-preview'):
            if mode=='launch-preview': movers['door_'+str(cell)].rotation_euler.x=min(1,p/2)*1.6
            movers['rocket'].location+=Vector(result['launch_axis'])*(-.55+2.2*(p/11)**1.6)
        movers['launch_glow'].location=Vector(result['cell_centers'][cell])+Vector(result['launch_axis'])*.06
        glow_scale = 1.04 - .027 * p if p < 8 else .60 - .04 * (p-8)
        movers['launch_glow'].scale=(glow_scale,glow_scale,glow_scale)
        for obj in result['effects']:
            visible=mode in ('launch','launch-preview') and (obj.parent==movers['launch_glow'] or 1<=p<=7)
            obj.hide_render=not visible;obj.hide_viewport=not visible
    elif mode=='alert':
        for obj in result['effects']:
            obj.hide_render=obj.hide_viewport=False
            strength=.65 + 4.35 * (.5 + .5 * math.sin(int(phase) * math.tau / 12 + .29))
            shader=obj.active_material.node_tree.nodes.get('Principled BSDF')
            shader.inputs['Emission Strength'].default_value=strength
    elif kind=='radar':
        for obj in result['effects']:
            obj.hide_render=obj.hide_viewport=False
            obj.active_material.node_tree.nodes.get('Principled BSDF').inputs['Emission Strength'].default_value=2.4
    bpy.context.view_layer.update()


