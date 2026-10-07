"""Rich mechanical infrastructure built around generated industrial materials.

Large forms and all moving parts are actual geometry. Reference-style texture
panels remain fixed on those surfaces across camera/animation samples.
"""
import math

import bpy
from mathutils import Matrix, Vector
from pathlib import Path

import hybrid_geometry as g
from hybrid_materials import palette, photographed, worn_paint

ROOT = Path(__file__).resolve().parents[1]


def source_prop(candidate, scale, location, rotation=0, parent=None):
    """Dress the site with the user's detailed source mesh, preserving its UVs."""
    with bpy.data.libraries.load(str(ROOT / 'graphics/imported' / candidate / 'normalized.blend'), link=False) as (src, dst):
        dst.objects = src.objects
    meshes = []
    transform = Matrix.Translation(Vector(location)) @ Matrix.Rotation(rotation, 4, 'Z') @ Matrix.Scale(scale, 4)
    for obj in dst.objects:
        if obj and obj.type == 'MESH':
            bpy.context.collection.objects.link(obj)
            obj.data = obj.data.copy()
            obj.data.transform(transform @ obj.matrix_world)
            obj.parent = parent
            obj.matrix_world = Matrix.Identity(4)
            obj.name = 'Site equipment / ' + candidate
            g.OBJECTS.append(obj)
            meshes.append(obj)
    for obj in dst.objects:
        if obj and obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
    return meshes


def pivot(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    return obj


def base(m):
    g.box('Thick cast concrete foundation', (0, 0, .09), (5.55, 5.35, .18), m['concrete'], bevel=.20)
    g.box('Armored floor perimeter', (0, 0, .20), (5.34, 5.14, .15), m['steel'], bevel=.16)
    for ix in range(5):
        for iy in range(5):
            g.box('Expansion-jointed service floor', (-2.04 + ix * 1.02, -1.95 + iy * .98, .29),
                  (.997, .957, .04), m['concrete'], bevel=.009)
    for x in (-2.52, 2.52):
        for iy in range(6):
            y = -2.08 + iy * .832
            g.box('Perimeter armor slab', (x, y, .49), (.20, .77, .37), m['graphite'], bevel=.03)
            g.box('Perimeter buttress', (x, y - .33, .57), (.32, .13, .58), m['steel'], bevel=.025)
    for y in (-2.43, 2.43):
        for ix in (-2, -1, 1, 2):
            g.box('Front rear armor slab', (ix * .91, y, .46), (.83, .20, .31), m['graphite'], bevel=.025)
    for x in (-2.49, 2.49):
        for y in (-2.41, 2.41):
            g.bolted_panel('Corner anchor', (x, y, .42), (.47, .47, .44), m, 'hatch')
            g.beacon('Corner navigation light', (x, y, .74), m)
    for y in (-2.43, 2.43):
        g.box('Access gate hazard plate', (0, y, .34), (.82, .23, .07), m['hazard'], bevel=.01)


def tank(name, location, radius, length, m, horizontal=False):
    x, y, z = location
    axis = (0, 1, 0) if horizontal else (0, 0, 1)
    g.cylinder(name + ' pressure vessel', (x, y, z), radius, length, m['paint'], axis=axis)
    for sign in (-1, 1):
        loc = (x, y + sign * length * .38, z) if horizontal else (x, y, z + sign * length * .38)
        g.cylinder(name + ' reinforcing band', loc, radius * 1.035, .045, m['edge'], axis=axis)
    g.cylinder(name + ' filler cap', (x, y, z + (radius if horizontal else length / 2) + .025), radius * .28, .045, m['steel'])
    for offset in (-.40, .40):
        band_z = z if horizontal else z + length * offset
        band_y = y + length * offset if horizontal else y
        g.ring(name + ' rolled vessel seam', (x, band_y, band_z), radius * 1.027, radius * .98,
               .021, m['ochre']) if not horizontal else None
    if horizontal:
        for sign in (-1, 1):
            g.box(name + ' cradle', (x, y + sign * length * .31, z - radius * .6), (radius * 2.25, .10, radius), m['steel'])


def service_cabinet(name, location, size, m):
    x, y, z = location
    w, d, h = size
    g.box(name + ' foot', (x, y, z - h / 2), (w * 1.15, d * 1.15, .12), m['steel'])
    g.box(name + ' housing', location, size, m['cabinet'])
    g.box(name + ' roof grille', (x, y, z + h / 2 + .014), (w * .83, d * .8, .025), m['vent'], bevel=.008)
    for dx in (-w * .29, w * .29):
        g.box(name + ' lifting eye foot', (x + dx, y, z + h / 2 + .08), (.10, .15, .07), m['edge'], bevel=.012)
    g.box(name + ' status slit', (x, y - d / 2 - .013, z + h * .20), (w * .35, .022, .035), m['amber'], bevel=.005)


def communications(name, location, m):
    x, y, z = location
    g.bolted_panel(name + ' equipment cabinet', (x, y, z + .18), (.46, .46, .36), m, 'console')
    for dx, dy in ((-.13, -.13), (.13, -.13), (.13, .13), (-.13, .13)):
        g.beam(name + ' lattice leg', (x + dx, y + dy, z + .38), (x + dx * .5, y + dy * .5, z + 1.25), .035, m['steel'])
    for height in (.5, .75, 1.0):
        g.beam(name + ' cross brace', (x - .12, y - .12, z + height), (x + .12, y - .12, z + height + .22), .024, m['edge'])
        g.beam(name + ' cross brace', (x + .12, y + .12, z + height), (x - .12, y + .12, z + height + .22), .024, m['edge'])
    g.cylinder(name + ' antenna mast', (x, y, z + 1.37), .02, .48, m['edge'])
    g.beacon(name + ' aerial beacon', (x, y, z + 1.63), m)
    g.cable(name + ' feeder cable', [(x, y, z + .4), (x + .18, y, z + .7), (x + .15, y, z + 1.2)], .023, m['rubber'])


def hangar_roof(m):
    # An open-front corrugated shell, with independent ribs and material panels.
    radius = 1.22
    center_y = .64
    for segment in range(16):
        a0 = segment * math.pi / 16
        a1 = (segment + 1) * math.pi / 16
        x0, z0 = math.cos(a0) * radius, .67 + math.sin(a0) * radius
        x1, z1 = math.cos(a1) * radius, .67 + math.sin(a1) * radius
        vertices = [(x0, center_y - .96, z0), (x1, center_y - .96, z1),
                    (x1, center_y + .96, z1), (x0, center_y + .96, z0)]
        mesh = bpy.data.meshes.new('Curved hangar armor segment')
        mesh.from_pydata(vertices, [], [(0, 1, 2, 3)])
        mesh.update()
        uv = mesh.uv_layers.new()
        for index, coordinate in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
            uv.data[index].uv = coordinate
        obj = bpy.data.objects.new('Curved hangar roof panel', mesh)
        bpy.context.collection.objects.link(obj)
        g.register(obj, obj.name, m['paint' if segment % 4 == 0 else 'roof'])
        thickness = obj.modifiers.new('Armored roof thickness', 'SOLIDIFY')
        thickness.thickness = .06
    for y in (-.36, .1, .65, 1.2, 1.65):
        points = [(math.cos(a * math.pi / 20) * 1.245, y, .68 + math.sin(a * math.pi / 20) * 1.245)
                  for a in range(21)]
        g.cable('Exposed curved hangar rib', points, .028, m['edge'])
        for index in range(1, 12):
            angle = index * math.pi / 12
            x, z = math.cos(angle) * 1.258, .68 + math.sin(angle) * 1.258
            g.cylinder('Roof rivet', (x, y, z), .018, .018, m['edge'], axis=(math.cos(angle), 0, math.sin(angle)), vertices=8)
    for x in (-1.22, 1.22):
        g.box('Hangar vertical side skirt', (x, .65, .49), (.10, 2.0, .35), m['olive'])
        g.box('Hangar foundation rail', (x, .65, .35), (.18, 2.12, .12), m['steel'])
    g.box('Dark hangar rear wall', (0, 1.58, .91), (2.30, .05, 1.18), m['dark'])
    g.box('Hangar internal grated floor', (0, .64, .34), (2.30, 1.82, .045), m['tread'])


def airfield(m):
    base(m)
    hangar_roof(m)
    movers = {}
    door = pivot('Hangar sliding door')
    movers[door.name] = door
    # Door leaves park at the jambs, leaving the dark interior readable.
    for x in (-1.04, 1.04):
        g.box('Hangar armored folding door', (x, -.40, .72), (.28, .09, .79), m['hatch'], door)
        g.box('Hangar door inner hazard strip', (x - math.copysign(.11, x), -.455, .72), (.035, .018, .75), m['ochre'], door, .003)
    g.box('Hangar doorway lamp', (0, -.40, 1.88), (.34, .05, .045), m['amber'])
    rotor = pivot('Airfield cooling fan')
    movers[rotor.name] = rotor
    g.fan('Primary roof ventilator', (-.43, .91, 1.97), .22, m, rotor)
    g.box('Roof intake scoop', (.35, .89, 1.98), (.44, .38, .15), m['vent'])
    for y in (-.1, .68, 1.43):
        service_cabinet('Ground support power pack', (-1.86, y, .57), (.50, .56, .40), m)
        g.fan('Power pack cooling fan', (-1.86, y, .80), .17, m)
    for y in (.66, 1.36):
        tank('Fuel drum', (1.76, y, .62), .25, .62, m)
    tank('Horizontal fuel reservoir', (-1.43, -1.93, .60), .27, .78, m, horizontal=True)
    communications('Airfield uplink', (1.89, 1.93, .35), m)
    for x in (-.71, .71):
        for i in range(8):
            g.box('Apron launch lane marking', (x, -.73 - i * .18, .325), (.045, .10, .012), m['ochre'], bevel=0)
    for x in (1.34, 2.10):
        g.box('Launch carriage steel rail', (x, -.97, .42), (.07, 2.15, .11), m['edge'])
    for y in (-1.89, -1.49, -1.09, -.69, -.29):
        g.box('Carriage rail cross member', (1.72, y, .37), (.91, .09, .07), m['steel'])
    g.bolted_panel('Launch carriage', (1.72, -1.69, .49), (.83, .47, .17), m, 'hazard')
    g.cable('Ground fuel feed', [(-1.55, -1.59, .42), (-2.13, -1.18, .40), (-2.17, 1.3, .40), (-1.28, 1.7, .41)], .045, m['rubber'])
    g.cable('Power conduit', [(1.82, 1.9, .42), (2.27, 1.5, .43), (2.27, -.9, .43), (1.8, -2.06, .43)], .031, m['copper'])
    for x, y in ((-.8, -2.17), (.91, 1.97)):
        g.bolted_panel('Maintenance crate', (x, y, .43), (.45, .38, .20), m, 'ammo')
    for x in (-.58, .58):
        source_prop('shahed-136', .158, (x, -.07, .47), math.pi)
        for y in (-.34, .26):
            g.box('Parked aircraft support trolley', (x, y, .39), (.27, .10, .12), m['steel'])
    source_prop('shahed-136', .166, (0, -1.35, .47), math.pi)
    for x in (-1.18, 1.18):
        g.box('Hangar threshold work light', (x, -.43, .94), (.033, .055, .23), m['amber'], bevel=.005)
    for x, y in ((-2.12, -1.0), (-1.51, -1.1), (2.18, -.02)):
        tank('Spare lubricant drum', (x, y, .49), .12, .35, m)
    for x in (-1.97, -.99, .98):
        g.bolted_panel('Apron drainage grille', (x, -2.18, .332), (.22, .25, .02), m, 'mesh')
    for radius in (.13, .17, .21):
        g.ring('Coiled service hose', (-1.77, -1.38, .355), radius, radius - .026, .026, m['rubber'])
    g.cable('Loose service hose end', [(-1.77, -1.56, .36), (-1.39, -1.55, .36), (-1.34, -1.03, .36)], .023, m['rubber'])
    for x in (1.28, 2.15):
        for y in (-1.5, -.45):
            g.cylinder('Launch rail roller', (x, y, .51), .064, .09, m['steel'], axis=(1, 0, 0))
    g.cylinder('Launch carriage winch', (1.71, -2.0, .47), .11, .35, m['steel'], axis=(1, 0, 0))
    g.cable('Launch tow cable', [(1.71, -2, .51), (1.71, -1.9, .52), (1.71, -.05, .52)], .012, m['edge'])
    return movers


def ballistic_site(m):
    base(m)
    movers = {}
    g.cylinder('Silo deep dark aperture', (0, -.05, .315), 1.14, .015, m['dark'])
    interior = bpy.data.materials.new('Unlit silo depth')
    interior.use_nodes = True
    interior.node_tree.nodes.clear()
    shade = interior.node_tree.nodes.new('ShaderNodeEmission')
    shade.inputs['Color'].default_value = (.002, .003, .004, 1)
    output = interior.node_tree.nodes.new('ShaderNodeOutputMaterial')
    interior.node_tree.links.new(shade.outputs[0], output.inputs[0])
    g.OBJECTS[-1].data.materials.clear()
    g.OBJECTS[-1].data.materials.append(interior)
    g.ring('Outer silo foundation collar', (0, -.05, .39), 1.37, 1.14, .15, m['concrete'])
    g.ring('Machined silo rim', (0, -.05, .52), 1.22, 1.035, .23, m['steel'])
    g.ring('Silo inner wear ring', (0, -.05, .62), 1.09, 1.018, .09, m['edge'])
    for i in range(16):
        angle = i * math.tau / 16
        x, y = math.sin(angle) * 1.24, -.05 + math.cos(angle) * 1.24
        obj = g.box('Silo radial armor segment', (x, y, .57), (.19, .25, .14), m['graphite'])
        obj.rotation_euler.z = -angle
        g.cylinder('Silo retaining bolt', (x, y, .66), .035, .045, m['edge'], vertices=6)
    for angle in (0, math.pi / 2, math.pi, math.pi * 1.5):
        g.beacon('Silo red warning', (math.sin(angle) * 1.30, -.05 + math.cos(angle) * 1.30, .64), m, color='red')
    hatch = pivot('Silo hatch')
    movers[hatch.name] = hatch
    g.cylinder('Sliding circular silo cover', (0, -.05, .78), 1.09, .15, m['paint'], hatch)
    g.ring('Silo cover reinforced lip', (0, -.05, .86), 1.09, .97, .065, m['edge'], hatch)
    for y in (-.69, -.37, -.05, .27, .59):
        length = 2 * math.sqrt(max(0, 1 - (y + .05) ** 2))
        g.box('Silo cover reinforcement', (0, y, .91), (length, .055, .065), m['steel'], hatch)
    for x in (-1.85, -1.36):
        tank('Coolant pressure reservoir', (x, -.22, .64), .19, 1.26, m, horizontal=True)
    for x in (-1.68, -.94, -.20):
        service_cabinet('Backup generator', (x, 1.80, .66), (.57, .58, .64), m)
        g.cylinder('Generator exhaust', (x + .16, 1.94, 1.16), .045, .43, m['copper'])
    for x in (.65, 1.27):
        for y in (1.45, 2.05):
            g.bolted_panel('Cooling array', (x, y, .49), (.55, .55, .29), m, 'vent')
            g.fan('Cooling array fan', (x, y, .69), .19, m)
    communications('Launch communications', (2.01, 1.33, .32), m)
    service_cabinet('Launch control console', (1.90, -.65, .66), (.62, .72, .67), m)
    service_cabinet('Power distribution cabinet', (1.81, -1.68, .59), (.73, .49, .51), m)
    for x in (-.73, .73):
        g.bolted_panel('Ground exhaust plenum', (x, -1.77, .41), (.64, .66, .13), m, 'mesh')
        g.fan('Ground exhaust turbine', (x, -1.77, .54), .20, m)
    for offset, material in ((0, 'rubber'), (.11, 'copper'), (.21, 'ochre')):
        g.cable('Protected launch services', [(-1.8, 1.4, .43), (-2.21 + offset, 1.13, .43),
                (-2.21 + offset, -1.71, .43), (-1.45, -2.11 + offset, .43),
                (1.81, -2.11 + offset, .43), (2.25 - offset, -1.61, .43)],
                .025 if material == 'ochre' else .038, m[material])
    for y in (-.82, .72):
        g.cylinder('Hatch hydraulic cylinder', (1.38, y, .56), .075, .62, m['steel'], axis=(1, 0, 0))
        g.cylinder('Hatch hydraulic polished rod', (1.00, y, .56), .028, .35, m['edge'], axis=(1, 0, 0))
    # Keep the closed rest pose unchanged for the fixed-view surface paint.
    hinge_location = Vector((1.1, -.05, .78))
    for child in list(hatch.children):
        child.location -= hinge_location
    hatch.location = hinge_location
    rocket = pivot('Silo rising missile')
    movers[rocket.name] = rocket
    pieces = source_prop('fateh-110', .46, (0, 0, 0), parent=rocket)
    for obj in pieces:
        obj.data.transform(Matrix.Translation((0, -.05, 1.39)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
        obj['no_paintover'] = True
        obj['rocket'] = True
        obj.hide_render = True
    rocket.location.z = -3.0
    material = bpy.data.materials.new('Below-ground launch occlusion')
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    holdout = nodes.new('ShaderNodeHoldout')
    output = nodes.new('ShaderNodeOutputMaterial')
    material.node_tree.links.new(holdout.outputs[0], output.inputs[0])
    plane = g.ring('Underground launch holdout', (0, -.05, .32), 15, 1.02, .012, material)
    plane['no_paintover'] = True
    plane['no_shadow'] = True
    plane['holdout'] = True
    plane.hide_render = True
    for z in (.345, .43):
        band = g.ring('Silo interior guide rail', (0, -.05, z), 1.015, .99, .028, m['steel'])
        band['no_paintover'] = True
    for index in range(12):
        angle = index * math.tau / 12
        guide = g.box('Silo internal rib', (math.sin(angle) * .99, -.05 + math.cos(angle) * .99, .40), (.045, .045, .17), m['edge'], bevel=.006)
        guide['no_paintover'] = True
        if index % 2 == 0:
            lamp = g.box('Silo interior red warning', (math.sin(angle) * .98, -.05 + math.cos(angle) * .98, .47), (.085, .035, .04), m['red'], bevel=.004)
            lamp.rotation_euler.z = -angle
            lamp['no_paintover'] = True
    return movers


def build(kind, paintover=False):
    g.OBJECTS.clear()
    materials = palette()
    materials['concrete'] = photographed('concrete_floor_worn_001', .65)
    materials['roof'] = worn_paint('weathered graphite roof', (.10, .135, .14))
    materials['paint'] = worn_paint('weathered olive enamel', (.22, .255, .13))
    movers = airfield(materials) if kind == 'airfield' else ballistic_site(materials)
    result = {'objects': list(g.OBJECTS), 'movers': movers, 'ortho_scale': 7.65}
    if paintover:
        import hybrid_projection
        filename = 'airfield-paintover-v2.png' if kind == 'airfield' else 'silo-paintover-v1.png'
        scale, offset = ((1.047, 1.047), (-.006, .005)) if kind == 'airfield' else ((1.13, 1.135), (-.055, -.026))
        result['objects'] = hybrid_projection.apply(result['objects'], ROOT / 'graphics/hybrid/materials' / filename, scale, offset, occlusion=kind == 'ballistic-site')
    animate(kind, 0, 0, 'full', result)
    return result


def ancestor(obj, target):
    while obj:
        if obj == target:
            return True
        obj = obj.parent
    return False


def animate(kind, direction, phase, mode, result):
    movers = result['movers']
    if kind == 'airfield':
        movers['Airfield cooling fan'].rotation_euler.z = phase * math.tau / (7 * 16)
        for obj in result['objects']:
            moving = ancestor(obj, movers['Airfield cooling fan']) or ancestor(obj, movers['Hangar sliding door'])
            obj.hide_render = moving if mode == 'base' else (not moving if mode == 'overlay' else False)
    else:
        hatch = movers['Silo hatch']
        rocket = movers['Silo rising missile']
        opening = min(1, phase / 5) * min(1, max(0, (19-phase) / 4))
        hatch.rotation_euler.y = math.radians(77) * opening if mode == 'launch' else 0
        rocket.location.z = -3 + 4.1 * max(0, (phase - 4) / 10) ** 1.8 if mode == 'launch' else -3
        for obj in result['objects']:
            moving = ancestor(obj, hatch)
            is_rocket = ancestor(obj, rocket)
            if mode == 'base':
                obj.hide_render = moving or is_rocket
            elif mode == 'overlay':
                obj.hide_render = not moving
            elif mode == 'launch':
                obj.hide_render = not (moving or (is_rocket and phase <= 14))
            else:
                obj.hide_render = is_rocket
            if obj.get('holdout'):
                obj.hide_render = mode != 'launch'
    bpy.context.view_layer.update()
