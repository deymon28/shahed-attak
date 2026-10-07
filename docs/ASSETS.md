# Hybrid artwork sources for Air War 0.6.1

The production pipeline combines supplied detailed 3D geometry, original 2D reference art, generated surface artwork and photographed materials. Animated bodies are rendered from one consistent model, without independent image generation per direction.

## Source families

| Runtime family | Geometry and surface treatment |
| --- | --- |
| AA turret | Supplied Zenitka mesh; separated pedestal, turret and recoil assembly; additional cooling, service panels, race and generated worn olive finish |
| ABM battery | Supplied NASAMS rack; retained UV materials, repaired canisters, new industrial pedestal; 64 actual launch views |
| Radar | Supplied TPS-59 antenna; separate mechanical rotation, industrial base, service equipment and alert lamps |
| Recon / strike / heavy | Supplied Shahed-129 / Shahed-136 / Shahed-238; retained source UVs or vertex color, object-local reference surface detail, physical panels and separate propulsion motion |
| Wreck | Torn Shahed-136 with severed spars, wiring and independently tumbling wing |
| Airfield / ballistic site | Custom multi-part machinery; generated fixed-camera paint projected onto real geometry; geometric alpha and shadows; separate fan/hatch/launch assemblies |
| Missile / interceptor / magazine | Selected original static 2D art retained for readability; editable 3D alternatives remain in the development project |
| Flak tracer | Retained compact tracer, resized only through the asset packer |

Original downloads remain in `graphics/3d`, original references in `graphics/source`, normalized packed scenes and source hashes in `graphics/imported`. Final editable scenes are `graphics/hybrid/models`. Generated images and prompts are in `graphics/hybrid/materials`. The generated industrial atlas and worn olive image provide shared surface detail. Airfield paint version 2 and silo paint version 1 are the production site projections; earlier experimental paint is not shipped.

The concrete material was downloaded from Poly Haven, with authors, URLs and SHA-256 in `graphics/hybrid/materials/photographed/manifest.json`. The photographed shutter candidate was evaluated and retained as a development input; it is not used in the final scenes. Supplied model provenance is recorded honestly in `ASSET_LICENSES.md` and `graphics/imported/manifest.json`.

## Production

`tools/render_assets.ps1` runs `tools/hybrid_scene.py` using Blender 5.2.1 LTS, Cycles and the verified RTX 5070 Ti OptiX device. `tools/hybrid_manifest.py` lists render plans and hashes dependent model, texture, lighting, projection and renderer sources. `tools/process_assets.py` rejects missing/stale 3D frames and packs native rendered shadow PNGs with premultiplied alpha and a 12/255 alpha threshold. Only the four named static ordnance families may use retained images. A separate painted-defense quality gate catches the observed intermittent black-material renderer failure and rerenders rejected frames in a fresh process before packing.

There are 73 runtime graphics: 16x8 aircraft, 8x12 wrecks, 64 turret directions, 4 AA firing frames per direction, 64x12 ABM launch frames, 32 radar angles, separate base/shadow/overlay sheets, 20 silo launch phases and inventory icons. The closed silo idle is intentionally static; the cover only opens for an actual launch and returns closed.

Review renders, contact sheets, motion previews and measured audio checks are under `build/hybrid-overhaul`. Final game captures and test logs are linked from `docs/VERIFICATION.md`. Source scenes, original files, generated materials, render caches and test worlds are excluded from the runtime archive.

The 22 recorded OGG sounds are retained after headroom and loop-seam checks. New per-player playback gating prevents repeated warning clips stacking while allowing an immediate ballistic escalation. Audio source attribution remains in `ASSET_LICENSES.md`.

The reconnaissance wreck has its own 8x12 body/shadow set, rendered by `tools/render_recon_wreck.py` from the same textured recon airframe. `tools/recon_wreck_assets.py` pins its source dependencies separately, so adding this family does not invalidate unrelated completed renders. The full render wrapper runs both generators before packing.
