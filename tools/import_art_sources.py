"""Safely preserve and extract the supplied local model archives."""
from __future__ import annotations

import hashlib
import json
import shutil
import stat
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "graphics/3d"
DEST = ROOT / "graphics/imported"
NAMES = {
    "balistic": "fateh-110",
    "iranian-shahed-136-military-drone": "shahed-136",
    "military-radar-system": "radar-system",
    "pro": "nasams",
    "roket1": "kh-38",
    "shahed-238-drone": "shahed-238",
    "us-antps-59-radar-war-thunder-af": "tps-59",
    "watcher_shahed-129-gen2": "shahed-129",
}


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def extract(archive, destination):
    destination.mkdir(parents=True, exist_ok=True)
    base = destination.resolve()
    with zipfile.ZipFile(archive) as handle:
        for entry in handle.infolist():
            name = PurePosixPath(entry.filename.replace("\\", "/"))
            if name.is_absolute() or ".." in name.parts or any(":" in p for p in name.parts):
                raise ValueError(f"Unsafe archive entry: {entry.filename!r}")
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f"Symbolic link is not allowed: {entry.filename!r}")
            target = destination.joinpath(*name.parts).resolve()
            if not target.is_relative_to(base):
                raise ValueError(f"Archive path escaped destination: {entry.filename!r}")
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with handle.open(entry) as source, target.open("wb") as out:
                    shutil.copyfileobj(source, out)


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    records = []
    for archive in sorted(SOURCE.glob("*.zip")):
        name = NAMES.get(archive.stem, archive.stem)
        target = DEST / name
        extract(archive, target / "original")
        pending = list((target / "original").rglob("*.zip"))
        expanded = []
        while pending:
            child = pending.pop(0)
            output = child.with_name(child.stem + "_unpacked")
            extract(child, output)
            expanded.append({"path": str(child.relative_to(ROOT)), "sha256": digest(child)})
            pending.extend(output.rglob("*.zip"))
        files = list(target.rglob("*"))
        models = [p for p in files if p.suffix.lower() in (".obj", ".fbx", ".glb", ".gltf", ".blend", ".stl")]
        textures = [p for p in files if p.suffix.lower() in (".png", ".jpg", ".jpeg", ".tga", ".exr")]
        records.append({"name": name, "source": str(archive.relative_to(ROOT)), "source_sha256": digest(archive),
                        "nested_archives": expanded, "models": [str(p.relative_to(ROOT)) for p in models],
                        "textures": [str(p.relative_to(ROOT)) for p in textures],
                        "license_status": "Supplied for private local use; authorship and redistribution rights unverified."})
    original = SOURCE / "zenitka.blend"
    target = DEST / "zenitka/original/zenitka.blend"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original, target)
    records.append({"name": "zenitka", "source": str(original.relative_to(ROOT)), "source_sha256": digest(original),
                    "models": [str(target.relative_to(ROOT))], "textures": [], "nested_archives": [],
                    "license_status": "Supplied for private local use; authorship and redistribution rights unverified."})
    output = DEST / "manifest.json"
    output.write_text(json.dumps(records, indent=2), encoding="utf-8")
    for record in records:
        print(record["name"], record["models"], f"textures={len(record['textures'])}")
    print(f"Manifest: {output}")


if __name__ == "__main__":
    main()
