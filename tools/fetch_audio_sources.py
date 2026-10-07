"""Restore curated CC0 recordings from checksum-pinned public URLs."""
import argparse
import hashlib
import json
from pathlib import Path
import requests


def fetch(root: Path) -> None:
    source_root = root / 'assets' / 'audio-source'
    manifest = json.loads((source_root / 'manifest.json').read_text(encoding='utf-8'))
    for key, source in manifest['sources'].items():
        destination = source_root / source['filename']
        if destination.parent.resolve() != source_root.resolve():
            raise RuntimeError(f'Invalid source destination: {key}')
        if not destination.exists():
            response = requests.get(source['download_url'], timeout=90)
            response.raise_for_status()
            if hashlib.sha256(response.content).hexdigest() != source['sha256']:
                raise RuntimeError(f'Downloaded source changed: {key}')
            destination.write_bytes(response.content)
        if hashlib.sha256(destination.read_bytes()).hexdigest() != source['sha256']:
            raise RuntimeError(f'Source checksum mismatch: {key}')
        print(f'Verified source: {key}', flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    fetch(args.root.resolve())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
