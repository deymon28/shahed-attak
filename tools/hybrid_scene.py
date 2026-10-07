"""Render every hybrid asset from stable imported geometry and shared textures."""
import argparse
import json
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import hybrid_renderer as renderer
from hybrid_manifest import render_plan, fingerprint


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--kind')
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--pilot', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    out = ROOT / 'graphics/renders'
    out.mkdir(parents=True, exist_ok=True)
    plans = render_plan()
    (out / 'plan.json').write_text(json.dumps(plans, indent=2))
    metadata_path = out / 'hybrid-geometry.json'
    metadata = json.loads(metadata_path.read_text()) if metadata_path.exists() else {
        'generator': 'Imported 3D with shared generated surface art and fixed-camera site paint',
        'sun': list(renderer.SUN), 'camera_location': [0, -10, 12], 'camera_target': [0, 0, .7],
        'shadow_method': 'Projected evaluated geometry, cached meshes, uniform alpha',
        'models': {},
    }
    for kind in dict.fromkeys(p['kind'] for p in plans):
        if args.kind and kind not in args.kind.split(','):
            continue
        selected = [p for p in plans if p['kind'] == kind]
        digest = fingerprint(kind)
        if all(p['method'] == 'retained-2d' for p in selected):
            metadata['models'][kind] = {'render_method': 'retained-2d', 'source_digest': digest,
                                        'sources': sorted({p['retained_source'] for p in selected})}
            metadata_path.write_text(json.dumps(metadata, indent=2))
            continue
        renderer.setup()
        if kind in ('aa', 'abm', 'radar'):
            import hybrid_defenses as model
            result = model.build(kind)
        elif kind in ('airfield', 'ballistic-site'):
            import hybrid_infrastructure as model
            bpy.context.scene.camera.data.ortho_scale = 7.65
            result = model.build(kind, paintover=True)
        else:
            import hybrid_aircraft as model
            result = model.build(kind)
        scene = bpy.context.scene
        scene.camera.data.ortho_scale = result['ortho_scale']
        model.animate(kind, 0, 0, 'full', result)
        path = ROOT / 'graphics/hybrid/models' / (kind + '.blend')
        renderer.pack_scene(path)
        metadata['models'][kind] = {
            'render_method': 'hybrid-3d', 'source_digest': digest, 'scene_path': path.relative_to(ROOT).as_posix(),
            'meshes': len(result['objects']),
            'vertices': sum(len(obj.data.vertices) for obj in result['objects'] if obj.type == 'MESH'),
            'assemblies': list(result['movers']), 'ortho_scale': result['ortho_scale'],
        }
        shadows = renderer.ShadowPass(result['objects']) if any(p['shadow'] for p in selected) else None
        for plan in selected:
            folder = out / plan['name']
            folder.mkdir(exist_ok=True)
            size = 640 if plan['name'].startswith('icon-') else max(384, plan['size'] * 3)
            scene.render.resolution_x = scene.render.resolution_y = size
            for direction in range(plan['directions']):
                for phase in range(plan['frames']):
                    index = direction * plan['frames'] + phase
                    if args.pilot and direction % max(1, plan['directions'] // 8):
                        continue
                    path = folder / f'{index:04d}.png'
                    stamp = path.with_suffix('.source.sha256')
                    shadow_path = path.with_suffix('.shadow.png')
                    if (not args.force and path.exists() and stamp.exists() and stamp.read_text() == digest
                            and (not plan['shadow'] or shadow_path.exists())):
                        continue
                    pose_direction = plan.get('wreck_direction', direction)
                    pose_phase = phase
                    if plan['name'].startswith('icon-'):
                        pose_direction = {'aa': 8, 'abm': 24}.get(kind, 2)
                        pose_phase = 12 if kind == 'radar' else 0
                    model.animate(kind, pose_direction, pose_phase, plan['mode'], result)
                    renderer.render(path)
                    if plan['shadow']:
                        shadows.render(shadow_path, result['objects'])
                    stamp.write_text(digest)
                    print(f'HYBRID_FRAME {plan["name"]} {index+1}/{plan["directions"]*plan["frames"]}', flush=True)
        metadata_path.write_text(json.dumps(metadata, indent=2))
        print(f'HYBRID_KIND_COMPLETE {kind}', flush=True)


if __name__ == '__main__':
    main()
