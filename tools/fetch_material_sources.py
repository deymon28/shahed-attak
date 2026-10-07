"""Download selected photographed PBR surfaces from their public source."""
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'graphics/hybrid/materials/photographed'
ASSETS = {
    'concrete_floor_worn_001': ['Dimitrios Savva', 'Rico Cilliers'],
    'painted_metal_shutter': ['Charlotte Baglioni', 'Dario Barresi', 'Rico Cilliers'],
}


def main():
    records = []
    for asset, authors in ASSETS.items():
        folder = OUTPUT / asset
        folder.mkdir(parents=True, exist_ok=True)
        for channel in ('diff', 'nor_gl', 'rough'):
            name = f'{asset}_{channel}_2k.png'
            url = f'https://dl.polyhaven.org/file/ph-assets/Textures/png/2k/{asset}/{name}'
            path = folder / name
            if not path.exists():
                request = Request(url, headers={'User-Agent': 'ShahedAttack-Private-Art-Source-Fetcher/1.0'})
                with urlopen(request, timeout=60) as response:
                    data = response.read()
                path.write_bytes(data)
            with Image.open(path) as image:
                assert image.size == (2048, 2048), f'Unexpected texture size: {path}'
                image.verify()
            records.append({'asset': asset, 'channel': channel, 'path': str(path.relative_to(ROOT)),
                            'url': url, 'source': f'https://polyhaven.com/a/{asset}',
                            'authors': authors, 'license': 'CC0 1.0',
                            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size})
            print(f'MATERIAL_SOURCE {asset} {channel} {path.stat().st_size}', flush=True)
    (OUTPUT / 'manifest.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
