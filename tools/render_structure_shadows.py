"""Render geometry-cast building shadows on a wider, ground-anchored canvas."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

import bpy
from mathutils import Vector
import hybrid_defenses as defenses
import hybrid_infrastructure as infrastructure
import hybrid_renderer as renderer
from structure_shadow_assets import KINDS, SUN, frame_path, shadow_plans, source_digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=KINDS)
    parser.add_argument('--pilot', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    folder = ROOT / 'graphics/renders/structure-shadows'
    folder.mkdir(parents=True, exist_ok=True)
    metadata_path = folder / 'geometry.json'
    metadata = json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
    for kind in ([args.kind] if args.kind else KINDS):
        digest = source_digest(kind)
        plans = [p for p in shadow_plans() if p['kind'] == kind]
        pending = []
        for plan in plans:
            count = 1 if args.pilot else plan['directions'] * plan['frames']
            for index in range(count):
                path = frame_path(plan, index)
                stamp = path.with_suffix('.source.sha256')
                if not path.exists() or not stamp.exists() or stamp.read_text() != digest:
                    pending.append((plan, index, path, stamp))
        if pending:
            scene = renderer.setup()
            model = defenses if kind in ('aa', 'abm', 'radar') else infrastructure
            result = model.build(kind) if model is defenses else model.build(kind, paintover=True)
            # The same camera origin and pixels/world-unit keep the foundation
            # anchored. Only horizontal overscan grows; the body is unchanged.
            scene.camera.data.ortho_scale = result['ortho_scale'] * 2
            renderer.SUN = Vector(SUN).normalized()
            shadow = renderer.ShadowPass(result['objects'])
            for plan, index, path, stamp in pending:
                height = max(384, plan['size'] * 2)
                scene.render.resolution_x = height * 2
                scene.render.resolution_y = height
                # Infrastructure base mode excludes its moving hatch/fan. Their
                # idle footprint is part of the complete static ground pass.
                mode = 'full' if model is infrastructure else plan['mode']
                model.animate(kind, index // plan['frames'], index % plan['frames'], mode, result)
                shadow.render(path, result['objects'])
                stamp.write_text(digest)
                print(f'SHADOW_FRAME {kind} {plan["shadow"]} {index}', flush=True)
        if not args.pilot:
            metadata[kind] = {'source_digest': digest, 'sun': SUN,
                              'camera_location': [0, -10, 12], 'horizontal_overscan': 2,
                              'frame_count': sum(p['directions'] * p['frames'] for p in plans)}
            metadata_path.write_text(json.dumps(metadata, indent=2))
    print('PASS: structure shadow render completed', flush=True)


if __name__ == '__main__':
    main()
