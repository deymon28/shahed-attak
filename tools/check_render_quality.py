"""Reject intermittent Cycles black-material failures in painted defense frames.

The threshold is specific to these painted models, not arbitrary artwork.
Repair reruns the unchanged scene renderer in a fresh Blender process and keeps
the rejected image for review. Successful source fingerprints remain intact.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

import numpy as np
from PIL import Image

try:
    from tools.hybrid_manifest import render_plan
except ModuleNotFoundError:
    from hybrid_manifest import render_plan


ROOT = Path(__file__).resolve().parents[1]


def black_fraction(image):
    pixels = np.asarray(image.convert('RGBA'))
    opaque = pixels[:, :, 3] > 220
    black = (pixels[:, :, :3].max(axis=2) < 8) & opaque
    return float(black.sum() / max(1, opaque.sum()))


def failures(root=ROOT):
    failed = []
    for plan in render_plan():
        if plan['kind'] not in ('aa', 'abm') or plan['mode'] == 'launch':
            continue
        for index in range(plan['directions'] * plan['frames']):
            path = root / 'graphics/renders' / plan['name'] / f'{index:04d}.png'
            if not path.exists():
                raise FileNotFoundError(path)
            with Image.open(path) as image:
                fraction = black_fraction(image)
            if fraction > .15:
                failed.append((plan['kind'], path, fraction))
    return failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repair', action='store_true')
    parser.add_argument('--blender', default=os.environ.get('BLENDER_EXE', 'blender'))
    args = parser.parse_args()
    for attempt in range(4):
        failed = failures()
        if not failed:
            print('PASS: painted defense renders have no black-material failures')
            return
        for kind, path, fraction in failed:
            print(f'Black material {fraction:.1%}: {path.relative_to(ROOT)}', flush=True)
        if not args.repair or attempt == 3:
            raise ValueError('Black-material render failures remain')
        for kind, path, fraction in failed:
            backup = ROOT / 'build/hybrid-overhaul/rejected-renders' / str(attempt) / path.parent.name / path.name
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
            # Invalidate only this generated cache entry; original sources stay intact.
            path.with_suffix('.source.sha256').unlink(missing_ok=True)
        kinds = ','.join(sorted({kind for kind, _, _ in failed}))
        log = ROOT / 'build/hybrid-overhaul' / f'quality-repair-{attempt}.log'
        environment = os.environ.copy()
        environment['OPTIX_CACHE_PATH'] = str(ROOT / 'build/hybrid-overhaul/optix-cache')
        creationflags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        with log.open('w') as output:
            subprocess.run([args.blender, '--background', '--disable-autoexec', '--python',
                            'tools/hybrid_scene.py', '--', '--kind', kinds], cwd=ROOT,
                           env=environment, stdout=output, stderr=subprocess.STDOUT,
                           creationflags=creationflags, check=True)


if __name__ == '__main__':
    main()
