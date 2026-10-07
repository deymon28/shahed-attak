"""Source contract for the reconnaissance airframe's falling animation."""
import hashlib
import json
from pathlib import Path

try:
    from tools.hybrid_manifest import fingerprint
except ModuleNotFoundError:
    from hybrid_manifest import fingerprint

ROOT = Path(__file__).resolve().parents[1]


def source_digest(root=ROOT):
    digest = hashlib.sha256(fingerprint('recon', root).encode())
    for name in ('recon_wreck_assets.py', 'render_recon_wreck.py'):
        digest.update((root / 'tools' / name).read_bytes())
    return digest.hexdigest()


def validate_sources(root=ROOT):
    expected = source_digest(root)
    metadata = json.loads((root / 'graphics/renders/recon-wreck-geometry.json').read_text())
    if metadata['source_digest'] != expected:
        raise ValueError('Recon wreck geometry is stale; run tools/render_recon_wreck.py in Blender')
    for direction in range(8):
        folder = root / 'graphics/renders' / f'falling-recon-wreck-{direction}'
        for phase in range(12):
            path = folder / f'{phase:04d}.png'
            if not path.exists() or not path.with_suffix('.shadow.png').exists() or path.with_suffix('.source.sha256').read_text() != expected:
                raise ValueError(f'Missing or stale recon wreck frame: {path}')
