"""Shared physical materials and generated panel art for the hybrid models.

The atlas is used as surface color, not as independently regenerated frames.
All angles therefore share the same physical detail positions.
"""
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / 'graphics/hybrid/materials/industrial-atlas-v1.png'
TILES = {
    'hatch': 0, 'olive': 1, 'radar': 2, 'graphite': 3,
    'vent': 4, 'mesh': 5, 'fan': 6, 'cabinet': 7,
    'hazard': 8, 'cables': 9, 'trim': 10, 'tread': 11,
    'aircraft': 12, 'ammo': 13, 'console': 14, 'concrete': 15,
}


def _base(name):
    material = bpy.data.materials.get(name)
    if material:
        return material
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    return material


def solid(name, color, metallic=0.0, roughness=0.45, emission=0.0):
    """Make a physically shaded surface with restrained microtexture."""
    material = _base('Hybrid / ' + name)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    if emission:
        shader.inputs['Emission Color'].default_value = (*color, 1)
        shader.inputs['Emission Strength'].default_value = emission
    elif len(nodes) == 2:
        noise = nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = 95
        noise.inputs['Detail'].default_value = 2
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = 0.12
        bump.inputs['Distance'].default_value = 0.008
        links.new(noise.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])
        ramp = nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].color = (*[v * .66 for v in color], 1)
        ramp.color_ramp.elements[1].color = (*color, 1)
        links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
        links.new(ramp.outputs['Color'], shader.inputs['Base Color'])
    return material


def panel(tile, metallic=None, roughness=0.52):
    """Map one cell of the generated atlas to normalized face UVs."""
    index = TILES[tile]
    name = 'Hybrid atlas / ' + tile
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    material = _base(name)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Metallic'].default_value = (
        (0.03 if tile == 'concrete' else .42) if metallic is None else metallic
    )
    shader.inputs['Roughness'].default_value = roughness
    image = bpy.data.images.load(str(ATLAS), check_existing=True)
    image.colorspace_settings.name = 'sRGB'
    texture = nodes.new('ShaderNodeTexImage')
    texture.name = 'Generated reference-style surface detail'
    texture.image = image
    texture.extension = 'EXTEND'
    coord = nodes.new('ShaderNodeTexCoord')
    scale = nodes.new('ShaderNodeVectorMath')
    scale.operation = 'MULTIPLY'
    scale.inputs[1].default_value = (.244, .244, 1)
    offset = nodes.new('ShaderNodeVectorMath')
    offset.operation = 'ADD'
    offset.inputs[1].default_value = (
        (index % 4) / 4 + .003, (3 - index // 4) / 4 + .003, 0,
    )
    links.new(coord.outputs['UV'], scale.inputs[0])
    links.new(scale.outputs['Vector'], offset.inputs[0])
    links.new(offset.outputs['Vector'], texture.inputs['Vector'])
    links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    # Low amplitude keeps depicted screws/edges from becoming swollen embossing.
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .19
    bump.inputs['Distance'].default_value = .018
    links.new(texture.outputs['Color'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    return material


def palette():
    return {
        'steel': solid('machined dark steel', (.18, .21, .22), .8, .32),
        'edge': solid('exposed bevel steel', (.42, .45, .46), .85, .27),
        'dark': solid('deep recesses', (.017, .022, .026), .25, .68),
        'rubber': solid('cable rubber', (.018, .021, .023), .05, .74),
        'ochre': solid('aged ochre enamel', (.55, .29, .035), .35, .48),
        'copper': solid('copper conduit', (.33, .075, .025), .65, .39),
        'red': solid('red warning lens', (.6, .008, .002), .0, .25, 2.8),
        'amber': solid('amber warning lens', (1, .2, .008), .0, .25, 2.4),
        'cyan': solid('blue optical glass', (.005, .26, .55), .2, .2, 1.7),
        'white': solid('white stencil paint', (.65, .67, .60), .1, .7),
        **{name: panel(name) for name in TILES},
    }


def photographed(asset, scale=1.0, metallic=0.0):
    """Use a photographed seamless surface with object-locked box mapping."""
    name = 'Photographed / ' + asset
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    material = _base(name)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Metallic'].default_value = metallic
    coord = nodes.new('ShaderNodeTexCoord')
    mapping = nodes.new('ShaderNodeVectorMath')
    mapping.operation = 'SCALE'
    mapping.inputs[3].default_value = scale
    links.new(coord.outputs['Object'], mapping.inputs[0])
    for channel, socket in [('diff', 'Base Color'), ('rough', 'Roughness')]:
        filename = ROOT / 'graphics/hybrid/materials/photographed' / asset / f'{asset}_{channel}_2k.png'
        texture = nodes.new('ShaderNodeTexImage')
        texture.image = bpy.data.images.load(str(filename), check_existing=True)
        texture.image.colorspace_settings.name = 'sRGB' if channel == 'diff' else 'Non-Color'
        texture.projection = 'BOX'
        texture.projection_blend = .18
        links.new(mapping.outputs[0], texture.inputs['Vector'])
        links.new(texture.outputs['Color'], shader.inputs[socket])
        if channel == 'rough':
            bump = nodes.new('ShaderNodeBump')
            bump.inputs['Strength'].default_value = .25
            bump.inputs['Distance'].default_value = .023
            links.new(texture.outputs['Color'], bump.inputs['Height'])
            links.new(bump.outputs[0], shader.inputs['Normal'])
    return material


def worn_paint(name, color):
    """Layer chipped enamel, rough corrosion and metallic exposed edges."""
    key = 'Worn paint / ' + name
    existing = bpy.data.materials.get(key)
    if existing:
        return existing
    material = _base(key)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Metallic'].default_value = .48
    shader.inputs['Roughness'].default_value = .55
    coord = nodes.new('ShaderNodeTexCoord')
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 16
    noise.inputs['Detail'].default_value = 6
    noise.inputs['Roughness'].default_value = .8
    links.new(coord.outputs['Object'], noise.inputs['Vector'])
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
    for index, (position, rgba) in enumerate([
        (.23, (.027, .015, .008, 1)), (.36, (.13, .054, .016, 1)),
        (.40, tuple(v * .30 for v in color) + (1,)),
        (.44, tuple(v * .68 for v in color) + (1,)),
        (.59, (*color, 1)), (.75, tuple(min(v * 1.4, 1) for v in color) + (1,)),
    ]):
        element = ramp.color_ramp.elements[0] if index == 0 else ramp.color_ramp.elements.new(position)
        element.position, element.color = position, rgba
    links.new(noise.outputs['Fac'], ramp.inputs[0])
    links.new(ramp.outputs[0], shader.inputs['Base Color'])
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .16
    bump.inputs['Distance'].default_value = .015
    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs[0], shader.inputs['Normal'])
    return material


def finish_imported(material, strength=.55, tone=(1, 1, 1)):
    """Bind generated enamel wear to mesh coordinates, retaining source maps."""
    if material.get('generated_surface_finish'):
        return
    material['generated_surface_finish'] = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = next(node for node in nodes if node.type == 'BSDF_PRINCIPLED')
    base = shader.inputs['Base Color']
    previous = base.links[0].from_socket if base.is_linked else None
    previous_color = tuple(base.default_value)
    texture = nodes.new('ShaderNodeTexImage')
    texture.name = 'Generated continuous worn enamel'
    texture.image = bpy.data.images.load(str(ROOT / 'graphics/hybrid/materials/worn-olive-v1.png'), check_existing=True)
    texture.projection = 'BOX'
    texture.projection_blend = .23
    coord = nodes.new('ShaderNodeTexCoord')
    mapping = nodes.new('ShaderNodeVectorMath')
    mapping.operation = 'SCALE'
    mapping.inputs[3].default_value = .63
    links.new(coord.outputs['Object'], mapping.inputs[0])
    links.new(mapping.outputs[0], texture.inputs['Vector'])
    mix = nodes.new('ShaderNodeMixRGB')
    mix.inputs[0].default_value = strength
    mix.inputs[1].default_value = previous_color
    if previous:
        links.new(previous, mix.inputs[1])
    links.new(texture.outputs['Color'], mix.inputs[2])
    tone_mix = nodes.new('ShaderNodeMixRGB')
    tone_mix.blend_type = 'MULTIPLY'
    tone_mix.inputs[0].default_value = 1
    links.new(mix.outputs[0], tone_mix.inputs[1])
    tone_mix.inputs[2].default_value = (*tone, 1)
    # Actual rounded geometric edges get rubbed-metal accents. This mask is
    # evaluated on the mesh; highlights never drift between animation frames.
    geometry = nodes.new('ShaderNodeNewGeometry')
    bevel = nodes.new('ShaderNodeBevel')
    bevel.inputs['Radius'].default_value = .025
    bevel.samples = 4
    dot = nodes.new('ShaderNodeVectorMath')
    dot.operation = 'DOT_PRODUCT'
    links.new(geometry.outputs['Normal'], dot.inputs[0])
    links.new(bevel.outputs['Normal'], dot.inputs[1])
    mask = nodes.new('ShaderNodeMapRange')
    mask.inputs['From Min'].default_value = 1.0
    mask.inputs['From Max'].default_value = .94
    mask.inputs['To Max'].default_value = .60
    links.new(dot.outputs['Value'], mask.inputs['Value'])
    wear = nodes.new('ShaderNodeMixRGB')
    links.new(mask.outputs['Result'], wear.inputs[0])
    links.new(tone_mix.outputs[0], wear.inputs[1])
    wear.inputs[2].default_value = (.42, .43, .40, 1)
    links.new(wear.outputs[0], base)
    rough = nodes.new('ShaderNodeMapRange')
    rough.inputs['From Min'].default_value = .02
    rough.inputs['From Max'].default_value = .35
    rough.inputs['To Min'].default_value = .66
    rough.inputs['To Max'].default_value = .32
    links.new(texture.outputs['Color'], rough.inputs['Value'])
    links.new(rough.outputs['Result'], shader.inputs['Roughness'])
    shader.inputs['Metallic'].default_value = .54


def face_uvs(mesh):
    """Give every cuboid face the entire normalized panel tile."""
    uv = mesh.uv_layers.active or mesh.uv_layers.new(name='Panel surface UV')
    for polygon in mesh.polygons:
        normal = polygon.normal
        major = max(range(3), key=lambda axis: abs(normal[axis]))
        axes = [axis for axis in range(3) if axis != major]
        points = [mesh.vertices[mesh.loops[index].vertex_index].co for index in polygon.loop_indices]
        lower = [min(point[axis] for point in points) for axis in axes]
        upper = [max(point[axis] for point in points) for axis in axes]
        for index, point in zip(polygon.loop_indices, points):
            uv.data[index].uv = [
                (point[axis] - low) / max(high - low, 1e-8)
                for axis, low, high in zip(axes, lower, upper)
            ]
