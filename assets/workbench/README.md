# Outer Workbench Assets

The real-scale workbench uses a textured three-band lighting shader, separate
from the miniature's `room_paper` and character shaders. It retains real mesh
depth, bevels, subdued normal maps, metal highlights and cast shadows. Runtime
geometry uses render layer 2; the miniature stays on layer 1. The two scales
share sky colors and the task lamp, but have independently balanced sunlight.

## Sources

Downloaded from Poly Haven, CC0 1.0:

- Wood Table: https://polyhaven.com/a/wood_table
- Oak Veneer 02 (cabinet wood): https://polyhaven.com/a/oak_veneer_02
- Rough Linen: https://polyhaven.com/a/rough_linen
- White Plaster 02: https://polyhaven.com/a/white_plaster_02
- Potted Plant 02: https://polyhaven.com/a/potted_plant_02
- Desk Lamp Arm 01: https://polyhaven.com/a/desk_lamp_arm_01
- Wicker Basket 02: https://polyhaven.com/a/wicker_basket_02
- Book Encyclopedia Set 01: https://polyhaven.com/a/book_encyclopedia_set_01
- Jacaranda Tree: https://polyhaven.com/a/jacaranda_tree
- Fern 02: https://polyhaven.com/a/fern_02

License: https://polyhaven.com/license
Exact authors, download URLs and MD5 checksums are in `sources.json`.
Texture downloads are 1K, except the 2K wood. No paid assets or API keys.

## Rebuild

1. Run `tools/fetch_workbench_assets.ps1` to verify or restore source downloads.
2. Run Blender 4.2 with `--background --python tools/build_workbench.py`.
3. Import `artisan_workbench.glb` in Godot.

## Rebuilt Studio (2026-10-16)

The previous outer workbench geometry has been replaced, not layered over.
Only the large-window/worktable arrangement was retained. One game unit is
2 cm in this outer room: desk 184 x 88 cm, cutting mat 90 x 60 cm. The game
miniature retains its own scale. Wood shelves use black metal brackets.

The window is an opening with two transparent Fresnel/specular glass surfaces
in Godot. Actual tree trunks, foliage and ferns are placed at multiple depths
outside. No opaque window scenery card remains. Trees use planar simplification
and deterministic whole-leaf thinning; retained leaves are slightly enlarged
to make the canopy less noisy. The studio totals 1,078,572 triangles (including
three trees), compared with 2,875,591 before thinning. Repeated assets share
mesh data. Source downloads are excluded from Godot
auto-import; only the assembled GLB is used in the game.

The generated editable Blender source lives in
`art_source/workbench/artisan_workbench.blend`, excluded from Godot auto-import.
It retains separate objects; the game export batches geometry by material.
Desk, shelves, blind, ceramic cup, brushes, shears, bobbins and fabric stacks
are locally generated. Books, baskets, plants, trees, ferns and the articulated
lamp use the external models credited above. Powered by Poly Haven.

Blender MCP 2.1.9 is installed in the user's tools, with Blender's addon enabled.
It listens on localhost:9876; telemetry is disabled in the MCP client config.
The reproducible builder remains usable independently of MCP. The installed
bridge was verified with `get_addon_status` and live scene inspection. The addon
reports telemetry off. `tools/start_blender_mcp.py` starts the localhost bridge.

## Lighting and Style

`scripts/studio_day_cycle.gd` has editable art-directed keyframes for dawn,
daylight, sunset, blue hour and night. This is not an astronomical/physical
sky simulation. Both scales receive the changing ambient color and sun angle.
Room pendant lights turn on gradually; exterior shop windows glow at night.
The lamp uses a shadow-casting SpotLight3D anchored to its imported bulb marker,
illuminating both scales. Its scanned closed casing does not cast shadows so
it cannot accidentally occlude its own light. There is no volumetric fog cone.

`shaders/studio_color_blocks.gdshader` controls tonal grouping, normal strength,
texture softening and metal highlights. Character material/proportions are
unchanged. Street paving has shallow beveled geometry instead of flat plates;
it receives shadows but does not cast noisy sub-pixel self-shadows.

`tests/workbench_preview.gd` records actual GPU captures at multiple hours and
checks day/night color separation and the visible contribution of the task
lamp. `tests/workbench_test.gd` checks materials, geometry budget, foliage not
crossing the wall, light placement and continuity at midnight. Desktop-sized
tablet previews are not measurements on real tablet hardware.
