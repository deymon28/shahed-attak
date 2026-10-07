"""Fixed-camera GPU rendering with real geometry-projected shadow images.

Dense imported meshes must not be serialized to millions of per-frame JSON
polygons. Shadow meshes are cached once and transformed in bulk for each pose.
"""
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector


SUN = Vector((-.6, -.8, 2.0)).normalized()


def setup(resolution=640, ortho_scale=5.8, samples=48):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    preferences = bpy.context.preferences.addons['cycles'].preferences
    preferences.compute_device_type = 'OPTIX'
    preferences.get_devices()
    for device in preferences.devices:
        device.use = device.type == 'OPTIX'
    if not any(device.use for device in preferences.devices):
        raise RuntimeError('No verified OptiX device available for hybrid rendering')
    scene.cycles.device = 'GPU'
    scene.render.use_persistent_data = True
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = .035
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_x = scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new('Fixed neutral studio sky')
    scene.world.use_nodes = True
    sky = scene.world.node_tree.nodes.get('Background')
    sky.inputs['Color'].default_value = (.42, .47, .53, 1)
    sky.inputs['Strength'].default_value = .65
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = .30
    bpy.ops.object.camera_add(location=(0, -10, 12))
    camera = bpy.context.object
    camera.name = 'Fixed Factorio oblique camera'
    camera.rotation_euler = (Vector((0, 0, .7)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = ortho_scale
    scene.camera = camera
    bpy.ops.object.light_add(type='SUN', location=SUN * 10)
    sun = bpy.context.object
    sun.name = 'Fixed northwest world sun'
    sun.rotation_euler = (-SUN).to_track_quat('-Z', 'Y').to_euler()
    sun.data.energy = 2.7
    sun.data.angle = .06
    bpy.ops.object.light_add(type='AREA', location=(2, -4, 6))
    fill = bpy.context.object
    fill.name = 'Broad reflected sky fill'
    fill.rotation_euler = (-fill.location).to_track_quat('-Z', 'Y').to_euler()
    fill.data.energy = 140
    fill.data.size = 5
    return scene


class ShadowPass:
    def __init__(self, objects):
        self.sources = [obj for obj in objects if obj.type in ('MESH', 'CURVE') and not obj.get('flash') and not obj.get('no_shadow') and obj.get('hybrid_part') != 'effect']
        self.records = []
        depsgraph = bpy.context.evaluated_depsgraph_get()
        material = bpy.data.materials.new('Uniform projected shadow silhouette')
        material.use_nodes = True
        nodes = material.node_tree.nodes
        nodes.clear()
        shader = nodes.new('ShaderNodeEmission')
        shader.inputs['Color'].default_value = (.004, .006, .009, 1)
        shader.inputs['Strength'].default_value = 1
        output = nodes.new('ShaderNodeOutputMaterial')
        material.node_tree.links.new(shader.outputs[0], output.inputs['Surface'])
        self.material = material
        for source in self.sources:
            mesh = bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph), preserve_all_data_layers=False, depsgraph=depsgraph)
            # The silhouette needs neither original materials nor large UV maps.
            mesh.materials.clear()
            mesh.materials.append(material)
            for polygon in mesh.polygons:
                polygon.material_index = 0
            shadow = bpy.data.objects.new('Shadow / ' + source.name, mesh)
            bpy.context.collection.objects.link(shadow)
            shadow.matrix_world = Matrix.Identity(4)
            shadow.hide_render = True
            vertices = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
            mesh.vertices.foreach_get('co', vertices)
            self.records.append((source, shadow, vertices.reshape(-1, 3)))

    def render(self, path, body_objects):
        scene = bpy.context.scene
        bpy.context.view_layer.update()
        body_states = [(obj, obj.hide_render) for obj in body_objects]
        visible = {obj.name: not hidden for obj, hidden in body_states}
        for source, shadow, vertices in self.records:
            shadow.hide_render = not visible.get(source.name, False)
            if shadow.hide_render:
                continue
            transform = np.asarray(source.matrix_world, dtype=np.float32)
            world = vertices @ transform[:3, :3].T + transform[:3, 3]
            world[:, :2] -= world[:, 2, None] * np.asarray((SUN.x / SUN.z, SUN.y / SUN.z), dtype=np.float32)
            world[:, 2] = .005
            shadow.data.vertices.foreach_set('co', world.ravel())
            shadow.data.update()
        for obj, _ in body_states:
            obj.hide_render = True
        samples, denoise = scene.cycles.samples, scene.cycles.use_denoising
        scene.cycles.samples = 8
        scene.cycles.use_denoising = False
        try:
            render(path)
        finally:
            scene.cycles.samples, scene.cycles.use_denoising = samples, denoise
            for _, shadow, _ in self.records:
                shadow.hide_render = True
            for obj, hidden in body_states:
                obj.hide_render = hidden


def render(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def pack_scene(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(path), check_existing=False)
