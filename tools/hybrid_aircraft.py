"""Imported, surface-detailed aircraft and ordnance with deterministic 3D motion.

Source UVs, normal maps and vertex colors remain part of the final shader.
All embellishments are locked to geometry, never independently painted frames.
"""
from pathlib import Path
import math

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import hybrid_geometry as geo
from hybrid_materials import palette, solid

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {'strike': 'shahed-136', 'recon': 'shahed-129', 'heavy': 'shahed-238',
           'wreck': 'shahed-136', 'ballistic-missile': 'fateh-110', 'interceptor': 'kh-38'}


def empty(name, parent=None, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent, obj.location = parent, location
    return obj


def imported(kind):
    path = ROOT / 'graphics/imported' / SOURCES[kind] / 'normalized.blend'
    with bpy.data.libraries.load(str(path), link=False) as (source, target):
        target.objects = source.objects
    loaded = [o for o in target.objects if o]
    for obj in loaded:
        bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.update()
    meshes = [obj for obj in loaded if obj.type == 'MESH']
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.data = obj.data.copy()
        obj.data.transform(world)
        obj.matrix_world = Matrix.Identity(4)
        obj.name = 'Imported source / ' + SOURCES[kind]
        obj['source'] = str(path.relative_to(ROOT))
        geo.OBJECTS.append(obj)
    for obj in loaded:
        if obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
    return meshes


def finish_source(obj, kind):
    """Keep original shader inputs and modulate the enamel with surface artwork."""
    if kind in ('strike', 'wreck', 'heavy', 'recon'):
        reference_uv=obj.data.uv_layers.new(name='Reference top surface UV',do_init=False)
        for loop in obj.data.loops:
            p=obj.data.vertices[loop.vertex_index].co
            reference_uv.data[loop.index].uv=(p.x*({'heavy':.235,'recon':.17}.get(kind,.211))+.5,p.y*(.22 if kind=='recon' else .160)+.51)
        # Original source maps continue to use their original active UV layer.
        obj.data.uv_layers.active_index=0
    for index, original in enumerate(obj.data.materials):
        material = original.copy()
        material.name = 'Aircraft preserved PBR / ' + kind
        obj.data.materials[index] = material
        nodes, links = material.node_tree.nodes, material.node_tree.links
        shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        incoming = shader.inputs['Base Color'].links
        source = incoming[0].from_socket if incoming else None
        tint = nodes.new('ShaderNodeMixRGB')
        tint.name = 'Graphite enamel over retained source markings'
        tint.blend_type = 'MULTIPLY'
        tint.inputs[0].default_value = 1
        tint.inputs[2].default_value = {
            'strike': (.21, .245, .22, 1), 'wreck': (.10, .115, .105, 1),
            'recon': (.58, .75, .86, 1), 'heavy': (.60, .64, .62, 1),
            'ballistic-missile': (.43, .47, .29, 1), 'interceptor': (.58, .63, .56, 1),
        }[kind]
        if source:
            links.new(source, tint.inputs[1])
        coord = nodes.new('ShaderNodeTexCoord')
        mapping = nodes.new('ShaderNodeVectorMath')
        mapping.operation = 'SCALE'
        mapping.inputs[3].default_value = .62
        links.new(coord.outputs['Object'], mapping.inputs[0])
        texture = nodes.new('ShaderNodeTexImage')
        texture.name = 'Generated worn enamel, object-locked box projection'
        texture.image = bpy.data.images.load(str(ROOT / 'graphics/hybrid/materials/worn-olive-v1.png'), check_existing=True)
        texture.projection, texture.projection_blend = 'BOX', .25
        links.new(mapping.outputs[0], texture.inputs['Vector'])
        worn = nodes.new('ShaderNodeMixRGB')
        worn.blend_type = 'MULTIPLY'
        worn.inputs[0].default_value = .38
        links.new(tint.outputs[0], worn.inputs[1])
        links.new(texture.outputs['Color'], worn.inputs[2])
        links.new(worn.outputs[0], shader.inputs['Base Color'])
        if kind in ('strike', 'wreck', 'heavy', 'recon'):
            # Original approved top-view artwork becomes an object-local material
            # layer. It follows real wing geometry through every heading and bank.
            ref = nodes.new('ShaderNodeTexImage')
            ref.name = 'Original reference panel artwork / local wing surface'
            reference={'heavy':'heavy-drone-v1.png','recon':'recon-drone-v1.png'}.get(kind,'strike-drone-v4.png')
            ref.image = bpy.data.images.load(str(ROOT / 'graphics/source' / reference),check_existing=True)
            ref.extension = 'CLIP'
            ref_uv=nodes.new('ShaderNodeUVMap')
            ref_uv.uv_map='Reference top surface UV'
            links.new(ref_uv.outputs[0],ref.inputs['Vector'])
            geometry=nodes.new('ShaderNodeNewGeometry')
            transform=nodes.new('ShaderNodeVectorTransform')
            transform.vector_type='NORMAL'
            transform.convert_from='WORLD'
            transform.convert_to='OBJECT'
            links.new(geometry.outputs['Normal'],transform.inputs[0])
            split=nodes.new('ShaderNodeSeparateXYZ')
            links.new(transform.outputs[0],split.inputs[0])
            mask=nodes.new('ShaderNodeMath')
            mask.operation='MULTIPLY'
            links.new(split.outputs['Z'],mask.inputs[0])
            links.new(ref.outputs['Alpha'],mask.inputs[1])
            strength=nodes.new('ShaderNodeMath')
            strength.operation='MULTIPLY'
            strength.inputs[1].default_value=.84 if kind!='wreck' else .62
            links.new(mask.outputs[0],strength.inputs[0])
            if kind in ('heavy','recon'):
                coord_split=nodes.new('ShaderNodeSeparateXYZ')
                links.new(ref_uv.outputs[0],coord_split.inputs[0])
                center=nodes.new('ShaderNodeMath')
                center.operation='SUBTRACT'
                center.inputs[1].default_value=.5
                links.new(coord_split.outputs['X'],center.inputs[0])
                absolute=nodes.new('ShaderNodeMath')
                absolute.operation='ABSOLUTE'
                links.new(center.outputs[0],absolute.inputs[0])
                wings=nodes.new('ShaderNodeMath')
                wings.operation='GREATER_THAN' if kind=='heavy' else 'LESS_THAN'
                wings.inputs[1].default_value=.095 if kind=='heavy' else .046
                links.new(absolute.outputs[0],wings.inputs[0])
                wing_mask=nodes.new('ShaderNodeMath')
                wing_mask.operation='MULTIPLY'
                links.new(wings.outputs[0],wing_mask.inputs[0])
                links.new(mask.outputs[0],wing_mask.inputs[1])
                links.new(wing_mask.outputs[0],strength.inputs[0])
            blend=nodes.new('ShaderNodeMixRGB')
            links.new(strength.outputs[0],blend.inputs[0])
            links.new(worn.outputs[0],blend.inputs[1])
            links.new(ref.outputs['Color'],blend.inputs[2])
            links.new(blend.outputs[0],shader.inputs['Base Color'])
        # Preserve normal and roughness maps; improve painted metal response.
        for link in list(shader.inputs['Metallic'].links):
            links.remove(link)
        shader.inputs['Metallic'].default_value = .42
        shader.inputs['Roughness'].default_value = .48
        if shader.inputs['Roughness'].links:
            rough=nodes.new('ShaderNodeMath')
            rough.operation='MULTIPLY_ADD'
            rough.inputs[1].default_value=.55
            rough.inputs[2].default_value=.12
            links.new(shader.inputs['Roughness'].links[0].from_socket,rough.inputs[0])
            links.new(rough.outputs[0],shader.inputs['Roughness'])
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .10
        bump.inputs['Distance'].default_value = .012
        if shader.inputs['Normal'].links:
            links.new(shader.inputs['Normal'].links[0].from_socket, bump.inputs['Normal'])
        links.new(texture.outputs['Color'], bump.inputs['Height'])
        links.new(bump.outputs[0], shader.inputs['Normal'])


def split_region(obj, predicate, name):
    """Split real source faces while retaining loops, UVs and vertex attributes."""
    part = obj.copy()
    part.data = obj.data.copy()
    bpy.context.collection.objects.link(part)
    part.name = name
    for target, keep in ((obj, False), (part, True)):
        bm = bmesh.new()
        bm.from_mesh(target.data)
        remove = [v for v in bm.verts if bool(predicate(v.co)) != keep]
        bmesh.ops.delete(bm, geom=remove, context='VERTS')
        bm.to_mesh(target.data)
        bm.free()
        target.data.update()
    geo.OBJECTS.append(part)
    return part


def attach_world(obj, parent):
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world


def machinery(body, kind, airframe, materials):
    """Surface-fit physical seams, raised fasteners, optics and service covers."""
    bpy.context.view_layer.update()
    tree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())

    def top(x, y):
        hit, normal, _, _ = tree.ray_cast(Vector((x, y, 5)), Vector((0, 0, -1)), 10)
        return (hit.z + .019) if hit is not None else None

    def seam(name, points, bolts=True):
        fitted = [(x, y, top(x, y)) for x, y in points]
        if any(p[2] is None for p in fitted):
            return
        geo.cable(name, fitted, .009, materials['dark'], airframe)
        if bolts:
            for x, y, z in fitted:
                geo.cylinder(name + ' rivet', (x, y, z + .012), .019, .013,
                             materials['edge'], airframe, vertices=8)

    if kind in ('strike', 'heavy', 'wreck'):
        for side in (-1, 1):
            for yy in (-1.8, -.95, -.1):
                width = min(1.8, (2.6 - yy) * .39)
                if kind == 'wreck' and side == 1:
                    width = min(width, .84)
                points = [(side * x, yy) for x in (.32, width * .60, width)]
                seam('Riveted wing access seam', points)
            seam('Inner wing spar seam', [(side * .42, .55), (side * .7, -.3), (side * .96, -1.2), (side * 1.2, -2.0)] if not (kind == 'wreck' and side == 1) else [(side * .4, .55),(side * .65, -.3),(side * .82, -1.2)])
    else:
        for side in (-1, 1):
            for x in (.85, 1.7, 2.55):
                seam('Recon wing rib seam', [(side*x, yy) for yy in (-.29, -.15, .035)])

    for y in ((.9, -.25, -1.5) if kind != 'recon' else (.65, -.35)):
        z = top(0, y)
        if z:
            geo.bolted_panel('Dorsal avionics access', (0, y, z), (.26, .39, .035), materials, 'graphite', airframe)
    lens = 'cyan' if kind == 'recon' else ('red' if kind in ('heavy', 'wreck') else 'amber')
    z = top(0, 1.35 if kind != 'recon' else 1.0)
    if z:
        yy = 1.35 if kind != 'recon' else 1.0
        geo.cylinder('Optical sensor collar', (0, yy, z), .11, .07, materials['steel'], airframe)
        geo.cylinder('Optical sensor lens', (0, yy, z+.045), .073, .018, materials[lens], airframe)
    for side in (-1, 1):
        xx, yy = ((side*2.55, 0) if kind == 'recon' else (side*1.70, -1.95))
        if kind == 'wreck' and side == 1:
            continue
        z = top(xx, yy)
        if z:
            geo.box('Wingtip navigation enclosure', (xx, yy, z+.02), (.10, .18, .06), materials['steel'], airframe)
            geo.box('Wingtip navigation lens', (xx, yy-.02, z+.058), (.06, .10, .022), materials[lens], airframe, .008)


def ordnance_details(body, kind, airframe, materials):
    vertices = [v.co for v in body.data.vertices]
    z = (min(v.z for v in vertices) + max(v.z for v in vertices)) / 2
    # Physical collar bands and metallic nozzle make the thin icons legible.
    for yy in (-1.85, -.1, 1.7):
        radius = .205 if kind == 'ballistic-missile' else .17
        collar = geo.ring('Ordnance segmented collar', (0, yy, z), radius, radius-.035, .065,
                          materials['ochre'] if yy > 1 else materials['steel'], airframe)
        collar.rotation_euler.x = math.pi/2
    return z


def ammo(kind, materials):
    assembly = empty('Ordnance icon assembly')
    if kind == 'flak-round':
        geo.cylinder('Brass cartridge case', (0, 0, .6), .24, 1.1, materials['copper'], assembly)
        geo.cylinder('Cartridge extraction rim', (0, 0, .08), .27, .09, materials['edge'], assembly)
        geo.cylinder('Projectile crimp collar', (0, 0, 1.14), .24, .09, materials['ochre'], assembly)
        bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=.23, radius2=.065, depth=.61, location=(0, 0, 1.46))
        geo.register(bpy.context.object, 'Flak projectile ogive', materials['steel'], assembly, .025)
        assembly.rotation_euler = (math.radians(65), math.radians(-20), math.radians(35))
        assembly.location = Vector((0,0,.7)) - assembly.rotation_euler.to_matrix() @ Vector((0,0,.85))
        return assembly, 2.5
    geo.box('Armored ammunition box', (0, 0, .42), (1.55, 1.0, .82), materials['ammo'], assembly, .075)
    geo.box('Ammo lid flange', (0, 0, .88), (1.66, 1.09, .12), materials['steel'], assembly)
    for x in (-.53, .53):
        geo.box('Locking strap', (x, 0, .98), (.09, 1.10, .07), materials['edge'], assembly)
        geo.box('Lid clasp', (x, -.565, .78), (.20, .08, .25), materials['ochre'], assembly)
    geo.cable('Folded carrying handle', [(-.3, 0, 1.0),(-.28, 0, 1.21),(.28, 0, 1.21),(.3, 0, 1.0)], .045, materials['steel'], assembly)
    for x in (-.48, -.16, .16, .48):
        geo.cylinder('Displayed flak shell', (x, .21, 1.16), .10, .62, materials['copper'], assembly, axis=(0,1,0))
        geo.cylinder('Displayed projectile tip', (x, -.15, 1.16), .087, .14, materials['steel'], assembly, axis=(0,1,0))
    return assembly, 2.7


def build(kind):
    geo.OBJECTS.clear()
    materials = palette()
    heading = empty('Aircraft heading / clockwise north')
    airframe = empty('Airframe bank and pitch', heading)
    movers = {'heading': heading, 'airframe': airframe}
    if kind in ('flak-round', 'flak-magazine'):
        assembly, scale = ammo(kind, materials)
        return {'objects': list(geo.OBJECTS), 'movers': movers, 'ortho_scale': scale}
    meshes = imported(kind)
    body = meshes[0]
    for obj in meshes:
        finish_source(obj, kind)
        obj.parent = airframe
    if kind in ('strike', 'wreck', 'recon'):
        cutoff = -2.80 if kind != 'recon' else -2.04
        rotor_mesh = split_region(body, lambda p: p.y < cutoff and abs(p.x) < .85, 'Retained imported rotating propeller')
        center = Vector((0, -2.87, .56)) if kind != 'recon' else Vector((0, -2.10, .92))
        rotor = empty('Independent pusher propeller shaft', airframe, center)
        rotor_mesh.parent = rotor
        rotor_mesh.data.transform(Matrix.Translation(-center))
        rotor_mesh.matrix_basis = Matrix.Identity(4)
        movers['propeller'] = rotor
    if kind == 'wreck':
        debris_mesh = split_region(body, lambda p: p.x > 1.0 + .08*math.sin(p.y*21), 'Torn detached imported starboard wing')
        pivot = Vector((1.35, -1.3, .5))
        debris = empty('Detached starboard wing tumble', airframe, pivot)
        debris_mesh.parent = debris
        debris_mesh.data.transform(Matrix.Translation(-pivot))
        debris_mesh.matrix_basis = Matrix.Identity(4)
        movers['debris'] = debris
        for yy in (-1.9, -1.55, -1.2, -.9):
            geo.beam('Exposed bent wing spar', (.80, yy, .43), (1.20, yy+.06, .61), .044, materials['edge'], airframe)
            geo.cable('Severed wing wiring', [( .82, yy, .50),(1.03,yy-.08,.42),(1.24, yy-.04,.35)], .018, materials['copper'], airframe)
    if kind in ('strike', 'wreck', 'recon', 'heavy'):
        machinery(body, kind, airframe, materials)
        if kind == 'heavy':
            nozzle = empty('Independent jet exhaust pulse', airframe, (0, -2.83, .52))
            movers['exhaust'] = nozzle
            rim = geo.ring('Jet nozzle metal rim', (0,0,0), .18, .115, .20, materials['steel'], nozzle)
            rim.rotation_euler.x = math.pi/2
            geo.cylinder('Glowing jet throat', (0,-.09,0), .11, .035, materials['amber'], nozzle, axis=(0,1,0))
            for side in (-1,1):
                geo.cable('Jet cooling conduit', [(side*.25,-1.4,.7),(side*.40,-1.9,.7),(side*.27,-2.6,.50)], .035, materials['copper'], airframe)
    else:
        ordnance_details(body, kind, airframe, materials)
    result = {'objects': list(geo.OBJECTS), 'movers': movers,
              'ortho_scale': {'wreck':9.15,'strike':8.6,'heavy':8.0,'recon':7.85}.get(kind,7.7),
              'source': SOURCES[kind]}
    animate(kind, 0, 0, 'flight', result)
    return result


def animate(kind, direction, phase, mode, result):
    """Integer directional/phase API: 16x8 flight, 8x12 wreck, north +Y."""
    movers = result['movers']
    count = 8 if kind == 'wreck' else 16
    p = (phase % (12 if kind == 'wreck' else 8)) / (12 if kind == 'wreck' else 8)
    angle = math.tau * p
    movers['heading'].rotation_euler.z = -math.tau * direction / count
    frame = movers['airframe']
    frame.location = (0, 0, .12 + .035*math.sin(angle))
    frame.rotation_euler = (.025*math.cos(angle), .075*math.sin(angle), 0)
    if 'propeller' in movers:
        movers['propeller'].rotation_euler.y = angle/(3 if kind=='recon' else 2)
    if 'exhaust' in movers:
        movers['exhaust'].scale = (1+.12*math.sin(angle), 1+.25*math.sin(angle), 1+.12*math.sin(angle))
    if kind == 'wreck':
        # A non-looping physical fall: pitch, roll and independently spinning wing.
        frame.location.z = .1 + .36*(1-p)
        frame.rotation_euler = (.12 + p*.85, -.28 + p*2.1, p*.30)
        movers['debris'].location = (1.35 + p*.30, -1.3-p*.12, .5-p*.12)
        movers['debris'].rotation_euler = (.35+p*2.3, -.35-p*1.9, .13+p*.7)
    bpy.context.view_layer.update()
