"""Production contracts and source fingerprints for the complete hybrid art set."""
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def render_plan():
    plans = []
    def add(kind, name, size, directions=1, frames=1, columns=1, mode='full', shadow=None, **extra):
        plans.append(dict(kind=kind, name=name, size=size, directions=directions,
                          frames=frames, columns=columns, mode=mode, shadow=shadow,
                          method='hybrid-3d', **extra))
    for kind, size, prefix in [('aa', 160, 'aa-turret'), ('abm', 192, 'abm-battery')]:
        add(kind, prefix + '-base', size, mode='base', shadow=prefix + '-base-shadow')
        add(kind, prefix + '-head-prepared', size, 64, 1, 8, 'head', prefix + '-head-prepared-shadow')
    add('aa', 'aa-turret-head-attacking', 160, 64, 4, 16, 'attack', 'aa-turret-head-attacking-shadow')
    add('abm', 'abm-battery-launch-sheet', 192, 64, 12, 24, 'launch')
    add('radar', 'early-warning-radar-sheet', 192, 1, 32, 8, shadow='early-warning-radar-shadow-sheet')
    add('radar', 'radar-alert-overlay-sheet', 192, 1, 12, 4, 'alert')
    for kind, size in [('recon', 72), ('strike', 80), ('heavy', 96)]:
        add(kind, kind + '-drone-sheet', size, 16, 8, 16, shadow=kind + '-drone-shadow-sheet')
    for direction in range(8):
        add('wreck', f'falling-wreck-{direction}', 96, 1, 12, 12,
            shadow=f'falling-wreck-shadow-{direction}', wreck_direction=direction)
    for kind in ('airfield', 'ballistic-site'):
        add(kind, kind + '-base', 320, mode='base', shadow=kind + '-shadow')
        add(kind, kind + '-overlay-sheet', 320, 1, 16, 4, 'overlay')
    add('ballistic-site', 'ballistic-site-launch-sheet', 320, 1, 20, 5, 'launch')
    for kind in ('aa', 'abm', 'radar', 'recon', 'strike', 'heavy', 'airfield', 'ballistic-site'):
        name = {'aa': 'aa-turret', 'abm': 'abm-battery', 'radar': 'early-warning-radar'}.get(kind, kind + ('-drone' if kind in ('recon', 'strike', 'heavy') else ''))
        add(kind, 'icon-' + name, 128)
    for kind, source, rotation in [
        ('ballistic-missile', 'graphics/source/ballistic-missile.png', 0),
        ('interceptor', 'graphics/source/interceptor.png', 45),
        ('flak-magazine', 'graphics/source/flak-magazine.png', 0),
        ('flak-round', 'graphics/hybrid/retained/flak-round.png', 0),
    ]:
        for icon in ([False, True] if kind in ('ballistic-missile', 'interceptor') else [kind != 'flak-round']):
            add(kind, ('icon-' if icon else '') + kind, 32 if kind == 'flak-round' else 128)
            plans[-1].update(method='retained-2d', retained_source=source, source_rotation=rotation)
    return plans


def source_files(kind, root=ROOT):
    plans = [p for p in render_plan() if p['kind'] == kind]
    if all(p['method'] == 'retained-2d' for p in plans):
        return [root / p for p in sorted({p['retained_source'] for p in plans})]
    files = [root / 'tools' / name for name in ('hybrid_renderer.py', 'hybrid_materials.py', 'hybrid_geometry.py', 'hybrid_scene.py')]
    files += [root / 'graphics/hybrid/materials' / name for name in ('industrial-atlas-v1.png', 'worn-olive-v1.png')]
    candidates = {'aa': ['zenitka'], 'abm': ['nasams'], 'radar': ['tps-59'], 'recon': ['shahed-129'],
                  'strike': ['shahed-136'], 'heavy': ['shahed-238'], 'wreck': ['shahed-136'],
                  'airfield': ['shahed-136'], 'ballistic-site': ['fateh-110']}
    files += [root / 'graphics/imported' / name / 'normalized.blend' for name in candidates[kind]]
    if kind in ('aa', 'abm', 'radar'):
        files.append(root / 'tools/hybrid_defenses.py')
    elif kind in ('airfield', 'ballistic-site'):
        files += [root / 'tools' / name for name in ('hybrid_infrastructure.py', 'hybrid_projection.py')]
        files.append(root / 'graphics/hybrid/materials' / ('airfield-paintover-v2.png' if kind == 'airfield' else 'silo-paintover-v1.png'))
        files.extend(sorted((root / 'graphics/hybrid/materials/photographed').rglob('*.png')))
    else:
        files.append(root / 'tools/hybrid_aircraft.py')
        files.extend(sorted((root / 'graphics/source').glob('*.png')))
    return files


def fingerprint(kind, root=ROOT):
    digest = hashlib.sha256(b'hybrid-render-pipeline-v2')
    digest.update(json.dumps([p for p in render_plan() if p['kind'] == kind], sort_keys=True).encode())
    for path in sorted(set(source_files(kind, root))):
        digest.update(path.relative_to(root).as_posix().encode())
        with path.open('rb') as stream:
            while chunk := stream.read(4 * 1024 * 1024):
                digest.update(chunk)
    return digest.hexdigest()
