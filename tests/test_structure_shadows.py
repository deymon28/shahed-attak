"""Ground shadows must remain visible beyond the complete building body."""
from pathlib import Path
import hashlib

import numpy as np
import pytest
from PIL import Image

from tools.asset_manifest import asset
from tools.process_assets import cell

ROOT = Path(__file__).resolve().parents[1]


def test_structure_shadow_cache_matches_current_geometry():
    from tools.structure_shadow_assets import validate_sources
    validate_sources(ROOT)


def frame(name, index=0):
    record = asset(f'graphics/entity/{name}.png')
    with Image.open(ROOT / record.path) as opened:
        return cell(opened.convert('RGBA'), record, index)


def test_firing_shadows_keep_every_heading_and_visible_barrel_recoil():
    name = 'aa-turret-head-attacking-shadow'
    headings = [hashlib.sha256(frame(name, direction * 4).tobytes()).hexdigest()
                for direction in range(64)]
    assert len(set(headings)) == 64
    # At these headings the barrels extend beyond the fixed head silhouette.
    for direction in (0, 16, 32):
        phases = [frame(name, direction * 4 + phase).tobytes() for phase in range(4)]
        assert len(set(phases)) == 4


@pytest.mark.parametrize('name', ['aa-turret', 'abm-battery', 'early-warning-radar', 'airfield', 'ballistic-site'])
def test_building_casts_visible_ground_shadow(name):
    if name in ('aa-turret', 'abm-battery'):
        body = frame(name + '-base')
        body.alpha_composite(frame(name + '-head-prepared'))
        shadow = frame(name + '-base-shadow')
        shadow.alpha_composite(frame(name + '-head-prepared-shadow'))
    elif name == 'early-warning-radar':
        body = frame(name + '-sheet')
        shadow = frame(name + '-shadow-sheet')
    else:
        body = frame(name + '-base')
        body.alpha_composite(frame(name + '-overlay-sheet'))
        shadow = frame(name + '-shadow')
    canvas = Image.new('RGBA', shadow.size)
    canvas.alpha_composite(body, ((shadow.width - body.width) // 2, 0))
    body_alpha = np.asarray(canvas.getchannel('A'))
    shadow_alpha = np.asarray(shadow.getchannel('A'))
    # Factorio applies its own shadow opacity. Premultiplying alpha by 95/255
    # made the ground pass almost invisible, even before body occlusion.
    assert shadow_alpha.max() >= 230, name
    exposed = shadow_alpha[body_alpha < 16].sum() / shadow_alpha.sum()
    assert exposed >= .06, f'{name}: only {exposed:.1%} of shadow is visible'
