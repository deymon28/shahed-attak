"""Single source of truth for generated runtime artwork."""

from __future__ import annotations

from dataclasses import dataclass


ALPHA_THRESHOLD = 12


@dataclass(frozen=True)
class RuntimeAsset:
    path: str
    cell_size: tuple[int, int]
    directions: int = 1
    frames: int = 1
    columns: int = 1
    edge_clearance: int = 1
    allow_static_duplicates: bool = False

    @property
    def sheet_size(self) -> tuple[int, int]:
        cells = self.directions * self.frames
        rows = (cells + self.columns - 1) // self.columns
        return self.cell_size[0] * self.columns, self.cell_size[1] * rows


def _static(path: str, size: int) -> RuntimeAsset:
    return RuntimeAsset(path, (size, size))


RUNTIME_ASSETS: tuple[RuntimeAsset, ...] = (
    RuntimeAsset("graphics/entity/recon-drone-sheet.png", (72, 72), 16, 8, 16),
    RuntimeAsset("graphics/entity/strike-drone-sheet.png", (80, 80), 16, 8, 16),
    RuntimeAsset("graphics/entity/heavy-drone-sheet.png", (96, 96), 16, 8, 16),
    RuntimeAsset("graphics/entity/recon-drone-shadow-sheet.png", (72, 72), 16, 8, 16),
    RuntimeAsset("graphics/entity/strike-drone-shadow-sheet.png", (80, 80), 16, 8, 16),
    RuntimeAsset("graphics/entity/heavy-drone-shadow-sheet.png", (96, 96), 16, 8, 16),
    *tuple(
        RuntimeAsset(f"graphics/entity/falling-wreck-{direction}.png", (96, 96), 1, 12, 12)
        for direction in range(8)
    ),
    *tuple(
        RuntimeAsset(f"graphics/entity/falling-wreck-shadow-{direction}.png", (96, 96), 1, 12, 12)
        for direction in range(8)
    ),
    *tuple(
        RuntimeAsset(f"graphics/entity/falling-recon-wreck{suffix}-{direction}.png", (96, 96), 1, 12, 12)
        for direction in range(8) for suffix in ('', '-shadow')
    ),
    _static("graphics/entity/airfield-base.png", 320),
    RuntimeAsset("graphics/entity/airfield-shadow.png", (640, 320)),
    RuntimeAsset("graphics/entity/airfield-overlay-sheet.png", (320, 320), 1, 16, 4),
    _static("graphics/entity/ballistic-site-base.png", 320),
    RuntimeAsset("graphics/entity/ballistic-site-shadow.png", (640, 320)),
    # The idle hatch stays closed; the launch sequence opens and closes it.
    RuntimeAsset("graphics/entity/ballistic-site-overlay-sheet.png", (320, 320), 1, 16, 4,
                 allow_static_duplicates=True),
    RuntimeAsset("graphics/entity/ballistic-site-launch-sheet.png", (320, 320), 1, 20, 5,
                 allow_static_duplicates=True),
    RuntimeAsset("graphics/entity/early-warning-radar-sheet.png", (192, 192), 1, 32, 8),
    RuntimeAsset("graphics/entity/early-warning-radar-shadow-sheet.png", (384, 192), 1, 32, 8),
    RuntimeAsset("graphics/entity/radar-alert-overlay-sheet.png", (192, 192), 1, 12, 4),
    _static("graphics/entity/aa-turret-base.png", 160),
    RuntimeAsset("graphics/entity/aa-turret-base-shadow.png", (320, 160)),
    RuntimeAsset("graphics/entity/aa-turret-head-prepared.png", (160, 160), 64, 1, 8),
    RuntimeAsset("graphics/entity/aa-turret-head-attacking.png", (160, 160), 64, 4, 16),
    RuntimeAsset("graphics/entity/aa-turret-head-prepared-shadow.png", (320, 160), 64, 1, 8),
    # The recoiling barrels are occluded by the fixed head silhouette at some
    # headings. A real projected shadow can remain still during those frames.
    RuntimeAsset("graphics/entity/aa-turret-head-attacking-shadow.png", (320, 160), 64, 4, 16,
                 allow_static_duplicates=True),
    _static("graphics/entity/abm-battery-base.png", 192),
    RuntimeAsset("graphics/entity/abm-battery-base-shadow.png", (384, 192)),
    RuntimeAsset("graphics/entity/abm-battery-head-prepared.png", (192, 192), 64, 1, 8),
    RuntimeAsset("graphics/entity/abm-battery-head-prepared-shadow.png", (384, 192), 64, 1, 8),
    RuntimeAsset("graphics/entity/abm-battery-launch-sheet.png", (192, 192), 64, 12, 24),
    _static("graphics/entity/ballistic-missile.png", 128),
    _static("graphics/entity/interceptor.png", 128),
    _static("graphics/entity/flak-round.png", 32),
    *tuple(
        _static(f"graphics/icons/{name}.png", 64)
        for name in (
            "recon-drone",
            "strike-drone",
            "heavy-drone",
            "airfield",
            "ballistic-site",
            "early-warning-radar",
            "aa-turret",
            "abm-battery",
            "ballistic-missile",
            "flak-magazine",
            "interceptor",
        )
    ),
)


_BY_PATH = {record.path: record for record in RUNTIME_ASSETS}


def asset(path: str) -> RuntimeAsset:
    """Return the declared runtime asset or fail for an unknown path."""
    return _BY_PATH[path]
