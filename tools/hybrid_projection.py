"""Bake an inspected fixed-camera paintover into stable mesh UV coordinates.

This is for non-rotating site architecture, never a rotating turret shortcut.
The camera projection is frozen at the rest pose; moving geometry carries its
surface with it. Hidden recesses retain real dark materials to avoid printing
an occluding hatch onto the interior behind it.
"""
from pathlib import Path

import bpy
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def apply(objects, image_path, scale=(1.0, 1.0), offset=(0.0, 0.0), occlusion=False):
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    material = bpy.data.materials.new('Generated fixed-view surface paint / ' + Path(image_path).stem)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    image = bpy.data.images.load(str(image_path), check_existing=True)
    image.colorspace_settings.name = 'sRGB'
    texture = nodes.new('ShaderNodeTexImage')
    texture.name = 'Inspected generated paintover'
    texture.image = image
    texture.extension = 'EXTEND'
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'Frozen reference projection'
    links.new(uv.outputs['UV'], texture.inputs['Vector'])
    emission = nodes.new('ShaderNodeEmission')
    links.new(texture.outputs['Color'], emission.inputs['Color'])
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(emission.outputs[0], output.inputs[0])
    inverse_camera = scene.camera.matrix_world.inverted()
    output_objects = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tree = None
    if occlusion:
        for obj in objects:
            if obj.type == 'MESH' and 'service floor' in obj.name.lower():
                bm = bmesh.new()
                bm.from_mesh(obj.data)
                bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=10, use_grid_fill=True)
                bm.to_mesh(obj.data)
                bm.free()
        vertices, polygons = [], []
        for obj in objects:
            if obj.type != 'MESH' or obj.hide_render:
                continue
            start = len(vertices)
            vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
            polygons.extend(tuple(start + index for index in polygon.vertices) for polygon in obj.data.polygons)
        tree = BVHTree.FromPolygons(vertices, polygons)
    masked_materials = {}

    def masked(original):
        if original.name in masked_materials:
            return masked_materials[original.name]
        combined = original.copy()
        combined.name = 'Visible generated paint / ' + original.name
        cn, cl = combined.node_tree.nodes, combined.node_tree.links
        target = next(n for n in cn if n.type == 'OUTPUT_MATERIAL')
        surface = target.inputs['Surface'].links[0].from_socket
        tex = cn.new('ShaderNodeTexImage')
        tex.image = image
        tex.extension = 'EXTEND'
        coords = cn.new('ShaderNodeUVMap')
        coords.uv_map = 'Frozen reference projection'
        cl.new(coords.outputs[0], tex.inputs['Vector'])
        paint = cn.new('ShaderNodeEmission')
        cl.new(tex.outputs[0], paint.inputs[0])
        visibility = cn.new('ShaderNodeAttribute')
        visibility.attribute_name = 'Visible at projection rest pose'
        blend = cn.new('ShaderNodeMixShader')
        cl.new(visibility.outputs['Fac'], blend.inputs[0])
        cl.new(surface, blend.inputs[1])
        cl.new(paint.outputs[0], blend.inputs[2])
        cl.new(blend.outputs[0], target.inputs['Surface'])
        masked_materials[original.name] = combined
        return combined

    view_direction = scene.camera.matrix_world.to_quaternion() @ Vector((0, 0, -1))
    for obj in objects:
        if obj.get('no_paintover') or 'recess' in obj.name.lower() or 'dark' in obj.name.lower():
            output_objects.append(obj)
            continue
        if obj.type == 'CURVE':
            mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), depsgraph=depsgraph)
            replacement = bpy.data.objects.new(obj.name + ' / projected curve', mesh)
            bpy.context.collection.objects.link(replacement)
            replacement.parent = obj.parent
            replacement.matrix_world = obj.matrix_world
            bpy.data.objects.remove(obj, do_unlink=True)
            obj = replacement
        if obj.type != 'MESH':
            output_objects.append(obj)
            continue
        # A vectorized orthographic projection handles imported dense meshes.
        vertices = np.empty(len(obj.data.vertices) * 3, np.float32)
        obj.data.vertices.foreach_get('co', vertices)
        transform = np.asarray(inverse_camera @ obj.matrix_world, np.float32)
        camera = vertices.reshape(-1, 3) @ transform[:3, :3].T + transform[:3, 3]
        projected = (camera[:, :2] / scene.camera.data.ortho_scale + .5)
        projected = projected * np.asarray(scale) + np.asarray(offset)
        loops = np.empty(len(obj.data.loops), np.int32)
        obj.data.loops.foreach_get('vertex_index', loops)
        layer = obj.data.uv_layers.get('Frozen reference projection') or obj.data.uv_layers.new(name='Frozen reference projection')
        layer.data.foreach_set('uv', projected[loops].astype(np.float32).ravel())
        if tree:
            visible = np.ones(len(obj.data.vertices), np.float32)
            for index, vertex in enumerate(obj.data.vertices):
                world = obj.matrix_world @ vertex.co
                hit, normal, face, distance = tree.ray_cast(world - view_direction * 100, view_direction, 100.04)
                visible[index] = float(hit is None or distance > 99.965)
            attribute = obj.data.attributes.get('Visible at projection rest pose') or obj.data.attributes.new('Visible at projection rest pose', 'FLOAT', 'POINT')
            attribute.data.foreach_set('value', visible)
            for index, original in enumerate(list(obj.data.materials)):
                obj.data.materials[index] = masked(original)
        else:
            obj.data.materials.clear()
            obj.data.materials.append(material)
            for polygon in obj.data.polygons:
                polygon.material_index = 0
        output_objects.append(obj)
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0
    return output_objects
