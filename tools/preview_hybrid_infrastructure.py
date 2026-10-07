"""Render the custom hybrid infrastructure before runtime sheet production."""
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import hybrid_renderer
import hybrid_infrastructure


for kind in ('airfield', 'ballistic-site'):
    scene = hybrid_renderer.setup(960, 7.65, 64)
    result = hybrid_infrastructure.build(kind)
    scene.camera.location = (0, -10, 12)
    scene.camera.rotation_euler = (Vector((0, 0, .70)) - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera.data.ortho_scale = result['ortho_scale']
    scene.render.resolution_x = scene.render.resolution_y = 960
    scene.render.resolution_percentage = 100
    output = ROOT / 'build/hybrid-overhaul/infrastructure-review'
    output.mkdir(parents=True, exist_ok=True)
    scenes = ROOT / 'graphics/hybrid/models'
    scenes.mkdir(parents=True, exist_ok=True)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(scenes / (kind + '.blend')))
    scene.render.filepath = str(output / (kind + '.png'))
    bpy.ops.render.render(write_still=True)
    shadow = hybrid_renderer.ShadowPass(result['objects'])
    shadow.render(output / (kind + '.shadow.png'), result['objects'])
    print(f'HYBRID_INFRA_PREVIEW {kind} objects={len(result["objects"])}', flush=True)
