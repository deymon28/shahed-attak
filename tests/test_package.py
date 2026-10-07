import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZipFile

from tools.asset_manifest import RUNTIME_ASSETS


ROOT = Path(__file__).resolve().parents[1]

TOP_LEVEL_FILES = {
    "info.json", "settings.lua", "data.lua", "data-final-fixes.lua", "control.lua",
    "README.md", "changelog.txt", "LICENSE", "ASSET_LICENSES.md", "thumbnail.png",
}
PROTOTYPES = {
    "categories.lua", "ground_defense.lua", "defense.lua", "effects.lua", "enemies.lua", "signals.lua",
    "sounds.lua", "technology.lua", "visuals.lua",
}
SCRIPTS = {
    "alerts.lua", "audio.lua", "balance.lua", "ballistics.lua", "commands.lua",
    "battery_gui.lua", "defense.lua", "ordnance.lua", "director.lua", "forces.lua", "infrastructure.lua",
    "radar_signals.lua", "raids.lua", "state.lua", "targeting.lua", "visual_effects.lua",
    "profiler.lua", "range_overlay.lua", "stats_gui.lua",
}
SCRIPT_LIBS = {
    "abm_launch.lua", "abm_launch_geometry.lua", "config.lua",
    "air_rules.lua", "alert_policy.lua", "audio_policy.lua", "defense_math.lua", "flight_math.lua", "random.lua",
}
SOUNDS = {
    "drone-recon-loop.ogg", "drone-strike-loop.ogg", "drone-heavy-loop.ogg", "drone-flyby.ogg",
    "flak-shot.ogg", "flak-burst.ogg", "drone-impact.ogg", "heavy-impact.ogg",
    "wreck-impact.ogg", "fuel-explosion.ogg", "warhead-explosion.ogg",
    "ballistic-launch.ogg", "ballistic-flight-loop.ogg", "ballistic-impact.ogg",
    "intercept-launch.ogg", "intercept-burst.ogg", "radar-hum-loop.ogg", "radar-ping.ogg",
    "airfield-machinery-loop.ogg", "ballistic-site-machinery-loop.ogg",
    "air-raid-siren.ogg", "ballistic-warning.ogg",
}


def expected_runtime_files() -> set[str]:
    return (
        TOP_LEVEL_FILES
        | {f"prototypes/{name}" for name in PROTOTYPES}
        | {f"scripts/{name}" for name in SCRIPTS}
        | {f"scripts/lib/{name}" for name in SCRIPT_LIBS}
        | {"migrations/0.5.0.lua", "migrations/0.4.0.lua", "locale/en/locale.cfg", "locale/ru/locale.cfg"}
        | {f"sound/{name}" for name in SOUNDS}
        | {record.path for record in RUNTIME_ASSETS}
    )


def test_release_archive_matches_exact_runtime_allowlist():
    metadata = json.loads((ROOT / "info.json.in").read_text(encoding="utf-8"))
    folder = f"{metadata['name']}_{metadata['version']}"
    shell = shutil.which("pwsh") or shutil.which("powershell")
    assert shell, "PowerShell is required to test the release builder"

    with tempfile.TemporaryDirectory(prefix="shahed-attack-package-") as temporary:
        output = Path(temporary) / "dist"
        subprocess.run(
            [shell, "-NoProfile", "-File", str(ROOT / "tools/build.ps1"), "-OutputDirectory", str(output)],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        archive = output / f"{folder}.zip"
        assert archive.is_file()
        with ZipFile(archive) as package:
            names = {name.replace("\\", "/") for name in package.namelist() if not name.endswith("/")}

    prefix = f"{folder}/"
    assert names and all(name.startswith(prefix) for name in names)
    actual = {name[len(prefix):] for name in names}
    assert actual == expected_runtime_files()
    banned = (
        "graphics/source", "graphics/models", "graphics/hybrid", "graphics/imported", "graphics/3d", "graphics/renders", "assets/", "tests/", "tools/", "docs/superpowers",
        "build/contact-sheets", "__pycache__", ".pytest_cache",
    )
    assert not any(fragment in name for name in names for fragment in banned)
