"""Import, normalize, audit and render supplied models with fixed world lighting.

Example: blender --background --disable-autoexec --python tools/preview_imported_models.py -- --names nasams --directions 4
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
import math
import sys
import time
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "graphics/imported"
REVIEW = ROOT / "build/hybrid-overhaul/import-review"
MANIFEST = json.loads((DEST / "manifest.json").read_text(encoding="utf-8"))
Z_UP = {"nasams", "shahed-238"}
# Heading adjustments are recorded here after visual inspection. +Y is north.
HEADING = {"kh-38": 90, "fateh-110": 180, "shahed-136": 0, "shahed-238": 0,
           "shahed-129": 180, "nasams": 0, "radar-system": 0, "tps-59": 180, "zenitka": -90}


def texture(nodes, path, color=False):
    node = nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(str(path), check_existing=True)
    node.image.colorspace_settings.name = "sRGB" if color else "Non-Color"
    node.label = path.name
    return node


def pbr(name, maps, vertex_color=None, glass=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (.19, .22, .14, 1)
    shader.inputs["Roughness"].default_value = .62
    shader.inputs["Metallic"].default_value = .15
    if vertex_color:
        node = nodes.new("ShaderNodeVertexColor")
        node.layer_name = vertex_color
        links.new(node.outputs["Color"], shader.inputs["Base Color"])
    for key, slot in (("base", "Base Color"), ("roughness", "Roughness"), ("metallic", "Metallic")):
        if maps.get(key):
            node = texture(nodes, maps[key], key == "base")
            links.new(node.outputs["Color"], shader.inputs[slot])
    if maps.get("normal"):
        node = texture(nodes, maps["normal"])
        normal = nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value = .65
        links.new(node.outputs["Color"], normal.inputs["Color"])
        links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    if maps.get("alpha"):
        node = texture(nodes, maps["alpha"])
        links.new(node.outputs["Color"], shader.inputs["Alpha"])
    if glass:
        shader.inputs["Base Color"].default_value = (.035, .052, .063, 1)
        shader.inputs["Roughness"].default_value = .18
        shader.inputs["Metallic"].default_value = .7
    return mat


def repair_materials(name, meshes, record):
    if name == "zenitka":
        return {"mode": "Preserved source node materials and packed texture coordinates"}
    files = [ROOT / p for p in record["textures"]]
    def find(basename):
        return next((p for p in files if p.name == basename), None)
    maps = {}
    if name in {"shahed-136", "shahed-129", "radar-system"}:
        maps = {key: find("texture_" + suffix + ".png") for key, suffix in
                (("base", "diffuse"), ("roughness", "roughness"), ("metallic", "metallic"), ("normal", "normal"))}
    elif name == "fateh-110":
        maps = {key: find("Untitled_3_default_" + suffix + ".png") for key, suffix in
                (("base", "BaseColor"), ("roughness", "Roughness"), ("metallic", "Metallic"), ("normal", "Normal"))}
    elif name == "nasams":
        maps = {"base": find("nasams_hull.png"), "roughness": find("nasams_1_roughness.jpeg"), "normal": find("nasams_normal.jpeg")}
    elif name == "kh-38":
        maps = {"base": find("su_kh38_mt_missile_c.jpeg"), "normal": find("su_kh38_mt_missile_n_n.jpeg")}
    elif name == "tps-59":
        mapping = {
            "2b1ff96d-363a-4730-9e4b-bed24ab8c3c5": ("mim_23_hawk_wheels_tex", False),
            "366a1801-90cb-4ec4-b0e2-001bcccb385e": ("mim_23_hawk_wheels_tex", True),
            "7004411b-74bd-4ca0-89cf-a5002d003b49": ("tps_59_radar_tex", False),
            "ea47916c-cf11-4b93-8982-ef0bb30d0197": ("tps_59_radar_tex", True),
        }
        replacements = {}
        for old, (prefix, alpha) in mapping.items():
            materials = {"base": find(prefix + "_d.jpeg"), "normal": find(prefix + "_n_n.jpeg")}
            if alpha:
                materials["alpha"] = find(prefix + "_d_a.png")
            replacements[old] = pbr("Restored " + old, materials)
        for obj in meshes:
            for slot in obj.material_slots:
                if slot.material and slot.material.name in replacements:
                    slot.material = replacements[slot.material.name]
        return {"mode": "Restored four source UUID material slots; base, normal and cutout masks", "unused_maps": "Specular/AO maps retained; no invented metallic/roughness channel interpretation"}
    if name == "shahed-238":
        for obj in meshes:
            color = obj.data.color_attributes.active_color
            mat = pbr("Source vertex colors", {}, color.name if color else None)
            obj.data.materials.clear()
            obj.data.materials.append(mat)
        return {"mode": "Source OBJ per-vertex colors", "issue": "No UVs or texture maps; retain color attributes and use generated detail separately"}
    mat = pbr("Restored source PBR " + name, maps)
    seeker = pbr("Dark seeker glass", {}, glass=True) if name == "kh-38" else None
    for obj in meshes:
        old = [slot.material.name if slot.material else "" for slot in obj.material_slots]
        if not old:
            obj.data.materials.append(mat)
        else:
            for index, old_name in enumerate(old):
                obj.material_slots[index].material = seeker if seeker and old_name.startswith("851d92fe") else mat
    return {"mode": "Reconstructed maps on retained source UVs", "maps": {k: str(v.relative_to(ROOT)) if v else None for k, v in maps.items()},
            "unmapped_inputs": "Any source specular or AO maps retained without guessing channel packing"}


def components(mesh):
    parent = list(range(len(mesh.vertices)))
    def root(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index
    for edge in mesh.edges:
        a, b = (root(i) for i in edge.vertices)
        if a != b:
            parent[b] = a
    counts = Counter(root(i) for i in range(len(parent)))
    largest = counts.most_common(16)
    return {"count": len(counts), "largest_vertex_counts": [n for _, n in largest]}


def setup_scene(samples, resolution):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    preferences = bpy.context.preferences.addons["cycles"].preferences
    preferences.compute_device_type = "OPTIX"
    preferences.get_devices()
    devices = []
    for device in preferences.devices:
        device.use = device.type == "OPTIX"
        devices.append({"name": device.name, "type": device.type, "enabled": device.use})
    if not any(d["enabled"] for d in devices):
        raise RuntimeError("No OptiX device found; refusing to claim GPU rendering")
    scene.cycles.device = "GPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.world = bpy.data.worlds.new("Neutral audit world")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.42, .47, .53, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = .65
    scene.view_settings.view_transform = "AgX"
    bpy.ops.object.camera_add(location=(0, -10, 12))
    camera = bpy.context.object
    camera.name = "Fixed oblique orthographic audit camera"
    camera.rotation_euler = (Vector((0, 0, 1.4)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 8.4
    scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(-4, -6, 10))
    light = bpy.context.object
    light.name = "Fixed upper-left softbox"
    light.data.energy = 1550
    light.data.shape = "DISK"
    light.data.size = 5
    light.rotation_euler = (-light.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.light_add(type="AREA", location=(5, 2, 7))
    light = bpy.context.object
    light.name = "Fixed cool fill"
    light.data.energy = 850
    light.data.size = 4
    light.rotation_euler = (-light.location).to_track_quat("-Z", "Y").to_euler()
    return devices


def frame_candidate(meshes, pivot, directions):
    """Fit all headings once; retain identical camera, lens and lights for every view."""
    camera = bpy.context.scene.camera
    inverse = camera.matrix_world.inverted()
    points = []
    for index in range(directions):
        pivot.rotation_euler.z = -index * math.tau / directions
        bpy.context.view_layer.update()
        points.extend(inverse @ obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box)
    low = [min(p[i] for p in points) for i in range(2)]
    high = [max(p[i] for p in points) for i in range(2)]
    scale = max(high[i] - low[i] for i in range(2)) * 1.12
    camera.data.ortho_scale = scale
    camera.data.shift_x = (high[0] + low[0]) / 2 / scale
    camera.data.shift_y = (high[1] + low[1]) / 2 / scale
    pivot.rotation_euler.z = 0
    bpy.context.view_layer.update()
    return {"ortho_scale": scale, "shift_x": camera.data.shift_x, "shift_y": camera.data.shift_y,
            "method": "Union of projected bounds over all rendered headings, 12 percent padding"}


def run(record, args):
    start = time.time()
    name = record["name"]
    model_paths = [ROOT / p for p in record["models"]]
    source = next((p for p in model_paths if p.name == "base_basic_pbr.fbx"), model_paths[0])
    print(f"IMPORT_START {name} {source}", flush=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if source.suffix == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    elif source.suffix == ".obj":
        bpy.ops.wm.obj_import(filepath=str(source), forward_axis="Y" if name in Z_UP else "NEGATIVE_Z", up_axis="Z" if name in Z_UP else "Y")
    elif source.suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(source), use_image_search=False)
    else:
        raise ValueError(source)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    worlds = {obj.name: obj.matrix_world.copy() for obj in meshes}
    for obj in meshes:
        obj.parent = None
        obj.matrix_world = worlds[obj.name]
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    repair = repair_materials(name, meshes, record)
    rotation = Matrix.Rotation(math.radians(HEADING[name]), 4, "Z")
    points = [rotation @ obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    source_size = high - low
    factor = 6 / max(source_size)
    center = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
    transform = Matrix.Scale(factor, 4) @ Matrix.Translation(-center) @ rotation
    audits = []
    pivot = bpy.data.objects.new("MODEL_ROOT_north_positive_Y", None)
    bpy.context.collection.objects.link(pivot)
    for obj in meshes:
        obj.data = obj.data.copy()
        obj.data.transform(transform @ obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        obj.parent = pivot
        obj.hide_render = False
        obj.hide_set(False)
        audits.append({"name": obj.name, "vertices": len(obj.data.vertices), "faces": len(obj.data.polygons),
                       "uv_layers": [uv.name for uv in obj.data.uv_layers], "color_attributes": [c.name for c in obj.data.color_attributes],
                       "components": components(obj.data), "materials": [slot.material.name if slot.material else None for slot in obj.material_slots]})
    devices = setup_scene(args.samples, args.resolution)
    bpy.context.view_layer.update()
    framing = frame_candidate(meshes, pivot, args.directions)
    for mat in list(bpy.data.materials):
        if mat.users == 0:
            bpy.data.materials.remove(mat)
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
    bpy.context.scene.render.filepath = str(REVIEW / name / "north.png")
    output = DEST / name / "normalized.blend"
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(output), check_existing=False)
    folder = REVIEW / name
    folder.mkdir(parents=True, exist_ok=True)
    audit = {"name": name, "source_model": str(source.relative_to(ROOT)), "normalized_blend": str(output.relative_to(ROOT)),
             "source_bounds_after_axis_conversion": [list(low), list(high)], "scale_factor": factor,
             "normalized_dimensions": list(source_size * factor), "heading_correction_degrees": HEADING[name],
             "material_repair": repair, "objects": audits, "devices": devices, "samples": args.samples,
             "resolution": args.resolution, "camera": [0, -10, 12], "camera_target": [0, 0, 1.4], "framing": framing,
             "images": [{"name": img.name, "size": list(img.size), "color_space": img.colorspace_settings.name,
                         "packed": bool(img.packed_file)} for img in bpy.data.images if img.type == "IMAGE"],
             "azimuth_convention": "north +Y, headings rotate clockwise, camera and lights fixed", "renders": []}
    for index in range(args.directions):
        degrees = index * 360 / args.directions
        pivot.rotation_euler.z = -math.radians(degrees)
        path = folder / f"heading-{round(degrees):03d}.png"
        bpy.context.scene.render.filepath = str(path)
        begin = time.time()
        bpy.ops.render.render(write_still=True)
        audit["renders"].append({"heading_degrees": degrees, "path": str(path.relative_to(ROOT)), "seconds": round(time.time() - begin, 3)})
        print(f"RENDER_COMPLETE {name} {degrees} {path}", flush=True)
    audit["elapsed_seconds"] = round(time.time() - start, 3)
    (folder / "audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    record["selected_model"] = str(source.relative_to(ROOT))
    record["normalized_blend"] = str(output.relative_to(ROOT))
    record["audit"] = str((folder / "audit.json").relative_to(ROOT))
    record["material_and_uv_notes"] = repair
    (DEST / "manifest.json").write_text(json.dumps(MANIFEST, indent=2), encoding="utf-8")
    print(f"CANDIDATE_COMPLETE {name} {audit['elapsed_seconds']} seconds", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--names", nargs="+", default=[record["name"] for record in MANIFEST])
    parser.add_argument("--directions", type=int, default=4)
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--resolution", type=int, default=640)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    REVIEW.mkdir(parents=True, exist_ok=True)
    for record in MANIFEST:
        if record["name"] in args.names:
            run(record, args)


if __name__ == "__main__":
    main()
