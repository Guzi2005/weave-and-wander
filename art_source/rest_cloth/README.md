# Rest Cloth Study

The approved silhouette is recorded in `../../captures/rest_approved_reference_20261023.png`.
The garment remains the original skinned LongSkirt, apron and trim. It is not replaced
with a separately rendered nap prop, and the skirt opening is not capped.

## Rebuild

1. Run `tests/export_rest_cloth.gd` with this Godot project. It exports the authored
   four nap poses, bone positions, actual calves/shoes and bench contact height to
   `captures/rest_cloth_input.json`. Export explicitly excludes the previous bake.
2. In Blender MCP, execute `tools/bake_rest_cloth.py`. Call `setup(variant)`, then
   `advance(65)` and `export(variant)` for each variant in a fresh study file.
   Existing study scenes are deliberately not overwritten.
3. Call `export_gravity_resource()`. The Godot resource is
   `assets/rest_cloth/nap_gravity.tres`; the Blender source and full diagnostic
   coordinates stay here, excluded from Godot import by `.gdignore`.

Blender 4.2.2 Cloth supplies gravity/collision settling below the knees. The waist
and authored hip/knee silhouette are pinned. Only vertical displacement is baked
back into the game, filtered into broad folds and limited to a 10.5 cm drop. This
is an art-directed offline corrective, **not** unrestricted real-time cloth or
a claim of collision safety for arbitrary new body sizes/furniture. The existing
pose blend weights drive the four corrections; hems and layers share that motion.
Godot retains the cushion-side support bound. Seated and standing shapes are unchanged.

## Reference Research

- [Pleated skirt, sandy2, CC0](https://blendswap.com/blend/28321): construction
  reference only. No downloaded mesh is incorporated into this project.
- [Blender cloth shape settings](https://docs.blender.org/manual/en/4.2/physics/cloth/settings/shape.html):
  pinning and rest-shape controls. A free full-skirt relaxation was tested and
  rejected because it destroyed the user's approved silhouette.

## Verification

Run `nap_gravity_test.gd`, `rest_drape_test.gd`, `rest_bench_test.gd`,
`layer_skinning_test.gd`, `garment_components_test.gd`, `skinning_test.gd` and
`expression_test.gd`. `rest_pose_capture.gd` captures four poses, the approved
upper view, a low side view and a sleeping-face detail. Inspect actual GPU images;
geometric guards do not replace visual acceptance.
