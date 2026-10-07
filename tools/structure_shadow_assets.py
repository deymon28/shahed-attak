"""Independent ground-shadow cache, preserving the existing painted body renders."""
import hashlib
import json
from pathlib import Path

try:
    from tools.hybrid_manifest import fingerprint, render_plan
except ModuleNotFoundError:
    from hybrid_manifest import fingerprint, render_plan

ROOT = Path(__file__).resolve().parents[1]
KINDS = ('aa', 'abm', 'radar', 'airfield', 'ballistic-site')
SUN = (-1.4, -.3, 1.0)


def shadow_plans():
    return [p for p in render_plan() if p['kind'] in KINDS and p['shadow']]


def source_digest(kind, root=ROOT):
    digest = hashlib.sha256(fingerprint(kind, root).encode())
    for name in ('structure_shadow_assets.py', 'render_structure_shadows.py'):
        digest.update((root / 'tools' / name).read_bytes())
    return digest.hexdigest()


def frame_path(plan, index, root=ROOT):
    return root / 'graphics/renders/structure-shadows' / plan['shadow'] / f'{index:04d}.png'


def validate_sources(root=ROOT):
    metadata = json.loads((root / 'graphics/renders/structure-shadows/geometry.json').read_text())
    for kind in KINDS:
        expected = source_digest(kind, root)
        if metadata[kind]['source_digest'] != expected:
            raise ValueError(f'Stale structure shadow geometry: {kind}')
        for plan in (p for p in shadow_plans() if p['kind'] == kind):
            for index in range(plan['directions'] * plan['frames']):
                path = frame_path(plan, index, root)
                stamp = path.with_suffix('.source.sha256')
                if not path.exists() or not stamp.exists() or stamp.read_text() != expected:
                    raise ValueError(f'Missing or stale structure shadow: {path}')


def pack(root=ROOT):
    from PIL import Image
    try:
        from tools.asset_manifest import asset
        from tools.process_assets import _save, place, resize_premultiplied
    except ModuleNotFoundError:
        from asset_manifest import asset
        from process_assets import _save, place, resize_premultiplied
    validate_sources(root)
    for plan in shadow_plans():
        record = asset(f"graphics/entity/{plan['shadow']}.png")
        sheet = Image.new('RGBA', record.sheet_size)
        for index in range(plan['directions'] * plan['frames']):
            with Image.open(frame_path(plan, index, root)) as opened:
                # Keep full coverage: draw_as_shadow applies engine opacity.
                frame = resize_premultiplied(opened.convert('RGBA'), record.cell_size)
            place(sheet, frame, record, index)
        _save(sheet, root / record.path, record)
        print(f'Packed ground shadow {record.path}', flush=True)
