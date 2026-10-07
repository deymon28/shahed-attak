# Structure ground shadows

The 0.6.4 correction uses the existing building meshes, original orthographic camera position and existing body sprites. The old steep sun projection kept almost all shadow coverage beneath the foundations; reducing shadow alpha to 95/255 before native engine shading also made exposed areas too faint.

`tools/render_structure_shadows.py` renders an independent ground pass with a fixed world sun vector `(-1.4, -0.3, 1)`. Ground projection preserves contact at height zero. The horizontal canvas and camera width double together, retaining the same pixel scale and image origin. Runtime shadow layers have twice the body frame width and the same height, scale and position.

`tools/structure_shadow_assets.py` validates geometry and renderer fingerprints before packing all 420 frames into the eight existing shadow files. PNG alpha retains full surface coverage; Factorio applies `draw_as_shadow` shading. Infrastructure includes the idle hatch and fan footprint. Turret heads and radar arrays project separately for each heading and animation phase. During some firing headings, the fixed head silhouette occludes barrel recoil, so identical shadow phases are physically valid.

Run the complete production pipeline with `tools/render_assets.ps1`, or render only the corrected shadow cache with Blender `--background --disable-autoexec --python tools/render_structure_shadows.py`, then pack with `python tools/process_assets.py --root .`. Existing body render fingerprints remain valid.

`tests/test_structure_shadows.py` checks exposed ground coverage, opacity, source freshness, heading uniqueness and visible recoil. The existing visual suite checks cell boundaries and animation content. `tests/graphics.ps1 -Scenario integration-structure-shadows` captures the actual engine output for all five building families beside vanilla turret/radar references.
