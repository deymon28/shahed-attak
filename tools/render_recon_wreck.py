"""Render a falling reconnaissance drone from its unchanged textured airframe."""
from pathlib import Path
import json
import math
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import bpy
import hybrid_aircraft as aircraft
import hybrid_renderer as renderer
from recon_wreck_assets import source_digest


def main():
    scene = renderer.setup(384, 10.5, 48)
    result = aircraft.build('recon')
    # A larger canvas preserves the live recon's apparent size in a 96 px cell.
    scene.camera.data.ortho_scale = 10.5
    path = ROOT / 'graphics/hybrid/models/recon-wreck.blend'
    renderer.pack_scene(path)
    digest = source_digest()
    shadow = renderer.ShadowPass(result['objects'])
    for direction in range(8):
        folder = ROOT / 'graphics/renders' / f'falling-recon-wreck-{direction}'
        folder.mkdir(parents=True, exist_ok=True)
        for phase in range(12):
            output = folder / f'{phase:04d}.png'
            stamp = output.with_suffix('.source.sha256')
            if output.exists() and output.with_suffix('.shadow.png').exists() and stamp.exists() and stamp.read_text() == digest:
                continue
            aircraft.animate('recon', direction * 2, phase % 8, 'flight', result)
            p = phase / 11
            body = result['movers']['airframe']
            body.location.z = .12 + .22 * p
            body.rotation_euler = (.025 + .7*p, 1.15*p, .18*p)
            bpy.context.view_layer.update()
            renderer.render(output)
            shadow.render(output.with_suffix('.shadow.png'), result['objects'])
            stamp.write_text(digest)
    metadata = {'source_digest':digest, 'scene_path':path.relative_to(ROOT).as_posix(),
                'source_family':'recon', 'directions':8, 'frames':12, 'ortho_scale':10.5}
    (ROOT / 'graphics/renders/recon-wreck-geometry.json').write_text(json.dumps(metadata, indent=2))
    print('PASS: reconnaissance wreck rendered in all eight headings', flush=True)


if __name__ == '__main__':
    main()
