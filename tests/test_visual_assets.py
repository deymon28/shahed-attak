"""Contracts for generated Factorio runtime artwork."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import pytest
from PIL import Image, ImageChops, ImageStat

from tools.asset_manifest import ALPHA_THRESHOLD, RUNTIME_ASSETS
from tools.hybrid_manifest import render_plan, fingerprint, source_files
from tools.check_render_quality import failures
from tools.process_assets import alpha_crop, assert_clear_edges, retained_image


ROOT = Path(__file__).resolve().parents[1]


def test_abm_launch_anchors_match_current_sprite_geometry():
    metadata = json.loads((ROOT / 'graphics/renders/abm-launch-anchors.json').read_text())
    assert metadata['source_digest'] == fingerprint('abm')
    assert metadata['exporter_sha256'] == hashlib.sha256((ROOT / 'tools/export_abm_launch.py').read_bytes()).hexdigest()
    assert metadata['runtime_sha256'] == hashlib.sha256((ROOT / 'scripts/lib/abm_launch_geometry.lua').read_bytes()).hexdigest()
    assert len(metadata['directions']) == 64
    assert all(len(pose['positions']) == 9 for pose in metadata['directions'])


def test_painted_defense_frames_do_not_lose_their_materials():
    assert not failures(ROOT)


def test_recon_wreck_has_current_source_and_its_own_airframe():
    from tools.recon_wreck_assets import validate_sources
    validate_sources(ROOT)
    recon = Image.open(ROOT/'graphics/entity/falling-recon-wreck-0.png').convert('RGBA')
    strike = Image.open(ROOT/'graphics/entity/falling-wreck-0.png').convert('RGBA')
    assert ImageStat.Stat(ImageChops.difference(recon.getchannel('A'),strike.getchannel('A'))).mean[0] > 5


def test_alpha_crop_ignores_nearly_transparent_noise():
    image = Image.new("RGBA", (20, 20), (0, 0, 0, 0))
    image.putpixel((0, 0), (255, 0, 0, 1))
    for x in range(6, 14):
        for y in range(7, 13):
            image.putpixel((x, y), (20, 30, 40, 255))
    cropped = alpha_crop(image, threshold=ALPHA_THRESHOLD)
    assert cropped.size == (8, 6)


def test_clear_edge_check_rejects_touching_cell():
    sheet = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    sheet.putpixel((15, 8), (255, 255, 255, 255))
    with pytest.raises(ValueError, match="cell 0 touches its edge"):
        assert_clear_edges(sheet, cell_size=(16, 16), columns=2)


def test_manifest_paths_and_sizes_are_self_consistent():
    paths = [record.path for record in RUNTIME_ASSETS]
    assert len(paths) == len(set(paths))
    for record in RUNTIME_ASSETS:
        cells = record.directions * record.frames
        expected = (
            record.cell_size[0] * record.columns,
            record.cell_size[1] * math.ceil(cells / record.columns),
        )
        assert record.sheet_size == expected


def test_all_runtime_assets_match_manifest_and_have_clear_cell_edges():
    for record in RUNTIME_ASSETS:
        path = ROOT / record.path
        assert path.is_file(), f"missing generated asset: {record.path}"
        with Image.open(path) as opened:
            image = opened.convert("RGBA")
        assert image.size == record.sheet_size, record.path
        assert_clear_edges(image, record.cell_size, record.columns)


def test_animated_cells_are_nonblank_and_unique():
    for record in RUNTIME_ASSETS:
        if record.directions * record.frames <= 1 or record.allow_static_duplicates:
            continue
        with Image.open(ROOT / record.path) as opened:
            sheet = opened.convert("RGBA")
        hashes: set[str] = set()
        for index in range(record.directions * record.frames):
            x = index % record.columns * record.cell_size[0]
            y = index // record.columns * record.cell_size[1]
            cell = sheet.crop((x, y, x + record.cell_size[0], y + record.cell_size[1]))
            assert cell.getchannel("A").getbbox() is not None, f"blank cell {index}: {record.path}"
            digest = hashlib.sha256(cell.tobytes()).hexdigest()
            assert digest not in hashes, f"duplicate cell {index}: {record.path}"
            hashes.add(digest)


def test_editable_geometry_exists_for_every_model():
    metadata = json.loads((ROOT / 'graphics/renders/geometry.json').read_text())
    expected = {'aa','abm','radar','recon','strike','heavy','wreck','airfield',
                'ballistic-site','ballistic-missile','interceptor','flak-round','flak-magazine'}
    assert set(metadata['models']) == expected
    for name, model in metadata['models'].items():
        if model['render_method'] == 'retained-2d':
            assert name in {'ballistic-missile', 'interceptor', 'flak-round', 'flak-magazine'}
            assert all((ROOT / path).is_file() for path in model['sources'])
            continue
        assert (ROOT / model['scene_path']).stat().st_size > 50000
        assert model['vertices'] >= 24, name
        if name in ('aa','abm','radar','airfield','ballistic-site'):
            assert model['meshes'] >= 15, name
            assert model['assemblies'], name


def test_head_azimuth_is_not_a_flat_sprite_rotation():
    """Opposite views expose different projected geometry, not a rotated PNG."""
    for name, size in [('aa-turret',160), ('abm-battery',192)]:
        with Image.open(ROOT/f'graphics/entity/{name}-head-prepared.png') as sheet:
            north=sheet.crop((0,0,size,size)).convert('RGBA')
            south=sheet.crop((0,4*size,size,5*size)).convert('RGBA')
        rotated=north.rotate(180)
        diff=ImageChops.difference(rotated.getchannel('A'),south.getchannel('A'))
        assert ImageStat.Stat(diff).mean[0] > 8, name


def test_radar_physical_antenna_changes_width_while_base_stays_fixed():
    folder=ROOT/'graphics/renders/early-warning-radar-sheet'
    front=Image.open(folder/'0000.png').convert('RGBA')
    side=Image.open(folder/'0008.png').convert('RGBA')
    # The rotating array is above the fixed cabinets in the oblique projection.
    # Exclude the stationary beacon at the right when measuring the array.
    upper=(round(front.width*.28),0,round(front.width*.65),round(front.height*.33))
    a=front.crop(upper).getchannel('A').point(lambda p: 255 if p >= ALPHA_THRESHOLD else 0).getbbox()
    b=side.crop(upper).getchannel('A').point(lambda p: 255 if p >= ALPHA_THRESHOLD else 0).getbbox()
    assert a and b
    assert a[2]-a[0] > (b[2]-b[0])*2
    bottom=(0,round(front.height*.72),front.width,front.height)
    diff=ImageChops.difference(front.crop(bottom),side.crop(bottom))
    assert max(ImageStat.Stat(diff).mean) < 2


def test_light_and_shadow_projection_are_fixed_in_world_space():
    metadata=json.loads((ROOT/'graphics/renders/geometry.json').read_text())
    x,y,z=metadata['sun']
    assert x < 0 and y < 0 and z > 0
    assert metadata['camera_location']==[0,-10,12]
    # At four directions, the elevated head shadow falls right of the same pivot.
    record=next(r for r in RUNTIME_ASSETS if r.path.endswith('aa-turret-head-prepared-shadow.png'))
    sheet=Image.open(ROOT/record.path).convert('RGBA')
    centroids=[]
    for index in (0,16,32,48):
        w,h=record.cell_size;cx=index%record.columns*w;cy=index//record.columns*h
        alpha=sheet.crop((cx,cy,cx+w,cy+h)).getchannel('A')
        values=list(alpha.getdata());weight=sum(values)
        centroids.append(sum((i%w)*v for i,v in enumerate(values))/weight)
    assert min(centroids) > record.cell_size[0] / 2


def test_retained_art_cannot_replace_animated_or_building_geometry():
    for kind, directions, frames in [('aa',1,1), ('radar',1,32), ('interceptor',2,1), ('flak-round',1,8)]:
        with pytest.raises(ValueError, match='restricted to approved static ordnance'):
            retained_image(ROOT, dict(kind=kind, directions=directions, frames=frames))
    for plan in render_plan():
        if plan['method'] == 'retained-2d':
            assert retained_image(ROOT, plan).getchannel('A').getbbox()


def test_silo_hatch_stays_closed_until_a_launch_then_returns_closed():
    record=next(r for r in RUNTIME_ASSETS if r.path.endswith('ballistic-site-overlay-sheet.png'))
    sheet=Image.open(ROOT/record.path).convert('RGBA')
    hashes=[]
    for index in range(16):
        x,y=index%4*320,index//4*320
        frame=sheet.crop((x,y,x+320,y+320))
        assert frame.getchannel('A').getbbox() is not None
        hashes.append(hashlib.sha256(frame.tobytes()).hexdigest())
    reference = sheet.crop((0,0,320,320))
    for index in range(16):
        frame = sheet.crop((index%4*320,index//4*320,index%4*320+320,index//4*320+320))
        # Cycles can differ by a one-level color rounding error without motion.
        assert max(ImageStat.Stat(ImageChops.difference(reference,frame)).mean) < .01
    launch = Image.open(ROOT/'graphics/entity/ballistic-site-launch-sheet.png').convert('RGBA')
    phases = [launch.crop((i%5*320,i//5*320,i%5*320+320,i//5*320+320)) for i in range(20)]
    assert all(p.getchannel('A').getbbox() for p in phases)
    assert len({hashlib.sha256(p.tobytes()).hexdigest() for p in phases}) >= 16
    for rest in (phases[0], phases[-1]):
        # Launch holdout/lighting can change antialiased boundary coverage.
        assert max(ImageStat.Stat(ImageChops.difference(reference,rest)).mean) < .25


def test_every_render_frame_matches_current_model_source():
    folder=ROOT/'graphics/renders'
    plans=json.loads((folder/'plan.json').read_text())
    assert plans == render_plan()
    hashes = {kind: fingerprint(kind) for kind in {p['kind'] for p in plans}}
    metadata = json.loads((folder/'geometry.json').read_text())
    for plan in plans:
        source_hash = hashes[plan['kind']]
        assert metadata['models'][plan['kind']]['source_digest'] == source_hash
        if plan['method'] == 'retained-2d':
            continue
        for index in range(plan['directions']*plan['frames']):
            stamp=folder/plan['name']/f'{index:04d}.source.sha256'
            assert stamp.read_text()==source_hash,str(stamp)


def test_source_fingerprint_covers_materials_and_imported_geometry():
    dependencies = {p.relative_to(ROOT).as_posix() for p in source_files('aa')}
    assert 'tools/hybrid_materials.py' in dependencies
    assert 'graphics/imported/zenitka/normalized.blend' in dependencies
    assert 'graphics/hybrid/materials/worn-olive-v1.png' in dependencies
    dependencies = {p.relative_to(ROOT).as_posix() for p in source_files('airfield')}
    assert 'tools/hybrid_projection.py' in dependencies
    assert 'graphics/hybrid/materials/airfield-paintover-v2.png' in dependencies
