# Reference Hand and Cloth Contact Experiment

## Status

FINAL USER DECISION: roll back today's model work to the pre-session state.
This is applied. ExperimentalFullBodyDoll now contains the original 297-line
pre-19:39 source, including its original shared palm and hosiery visibility.
The enable_full_body_study switch described below no longer exists. Today's
extra rig proportion/authored-weight interfaces and prototype files are removed
from the active project and backed up outside it under
`prototypes/snapshots/body-work-20261109-before-rollback/`.
The reference_dressed_restore test below was also archived; its result is
historical, not the current rollback test. See root HANDOFF for current checks.

Latest correction: the user's complete manually tuned mannequin is distinct from
both VolumeDoll's incomplete underbody and the rejected experiments below.
An early source snapshot has been recovered, but its silhouette is NOT an exact
match to the user's image. See `Docs/reference-body/RECOVERY.md` and root HANDOFF.
Do not claim the user's complete body never existed or restore these rejected
experiments as a substitute. The game runtime has not been switched again.

**Superseded by explicit user rejection, later on 2026-11-09.** The user requested
the original dressed doll at the left of the comparison, not any newly modeled body.
The current baseline is the existing `VolumeDoll`, restored exactly. The experimental
subclass now defaults to that build, with `enable_full_body_study=false`; no mannequin,
proportion mapping, body hiding or experimental collision is applied. Experimental
controls are no longer exported to the Inspector. Do not automatically re-enable them.

`tests/reference_dressed_restore_test.gd` is the current acceptance regression:
2245 checks / 0 failures on GPU, comparing exact original mesh arrays, visibility,
bone rests and five activities across three base outfits. Screenshot:
`captures/reference_dressed_restored.png`. Historical tests/captures below now require
the explicit `--archived-body-study` argument and are not visual acceptance evidence.
Unresolved physics remains unresolved; SKIP of a retired fixture is not a fix.

Later on 2026-11-09 the user rejected the low/protruding shoulders and oversized,
uneven arms. Current runtime uses `reference_hand_small.json`, fitted via live Blender
MCP by `tools/blender_reference_hand_fit.py`, with source
`Docs/ukrainian-model/reference-hand-fit.blend`. The previous hand below remains the
source asset, not the current size. X/Y scale is .72, Z scale .78, wrist-centered.

Shoulder roots now taper inside the torso and blend to Spine. Upper arm thickness is
more even, its curve is locally densified, and `shoulder_raise=.055` maps mesh, sleeve
and joint rest positions together. Head, hips and legs were not remodeled. Neck depth
was reduced locally to stop its front from poking through the standing collar.

Latest verification: silhouette 26222 checks / 0 failures, including 1080 shoulder-cap
points across 18 poses; hand 35927 / 0; isolated hand/hip slider regression 295212 / 0;
shared skinning 96 poses / 0. The hand/hip test fixes the shoulder slider at zero;
`reference_silhouette_test.gd` independently checks shoulder height and embedded caps.
New actual captures are `captures/shoulder_refined_front.png`, `_quarter.png`,
`_side.png`, `_neck.png`, `_action.png`; left is original dressed reference, center
updated mannequin, right updated clothed. Previous `shoulder_before_*` remain.
Visual approval remains with the user. All cloth physics limitations below remain.

2026-11-09. The continuous thumb is integrated into `ExperimentalFullBodyDoll`.
General garment collision is **not complete** and is not enabled in the live game.
Do not describe coverage masks or vertex-only tests as proof of no penetration.

## Hand

- Live Blender MCP ran `tools/blender_reference_hand.py`.
- `Docs/ukrainian-model/reference-hand.blend` is the editable source;
  `assets/reference_hand.json` is the generated 894-vertex closed, connected mesh.
- The thumb root is boolean-unioned and locally smoothed inside the reference palm.
  No separate thumb sphere renders on the experimental doll.
- The original wrist ring, body outline and previous Y-only proportion controls remain.
  Wrist normals match the forearm. Skin weights blend from forearm at the rim to hand
  farther down the palm, so rotating the hand does not open the wrist seam.
- Other `VolumeDoll` hand assets and the rejected whole-body remesh are untouched.

Verified in Godot 4.7.1:

| Test | Result |
| --- | --- |
| `tests/reference_hand_test.gd` | 35927 checks, 0 failures; 18 poses including explicit wrist rotations |
| `tests/mannequin_arm_proportion_test.gd` | 283554 checks, 0 failures; zero-reset and unchanged X/Z/head/feet |
| `tests/skinning_test.gd` | 96 poses, 0 failures; clearance_vertices=0, not a cloth collision test |

Actual GPU captures: `captures/reference_hand_detail.png` (front/oblique hand),
`captures/garment_contact_stand.png`, `captures/garment_contact_sit.png`.
The two garment images compare contact disabled/enabled with the body deliberately
visible. They are experimental evidence, not accepted clothing renders.

## Collision Experiment: Known Failure

`scripts/garment_body_contact.gd` projects posed garment vertices out of actual body
triangles, then propagates the displacement to bound garment overlays.
`cloth_contact_surface.gd` uses native TriangleMesh BVHs for projection and a refit
nearest-triangle tree for the independent distance audit. This is not a cloth solver.

`body_contact_enabled` defaults to **false**. It is an expensive fitting diagnostic,
not a production per-NPC system. Enabling it replaces rendered garment geometry with
posed copies, without changing source visibility; clearing restores render layers.

Latest six-pose audit (walk samples, working, seated, nap):

- 84450 vertex/body samples; 1763 corrections; zero vertex failures.
- **418 triangle-centroid/body penetration samples** beyond 0.0005 tolerance,
  deepest about 0.061 game units. These are not necessarily unique faces.
- 29-79 ms per update on this machine, excluding the exact verification pass.
- `tests/garment_body_contact_test.gd` correctly exits **1** for this known blocker.
  Earlier reports of zero failures referred only to vertices and are insufficient.
- No CCD, cloth self-collision or arbitrary layer collision is implemented here.
  Avoid running this GDScript diagnostic on the roughly 140k-vertex imported outfit.

## Native Physics Adapter

`scripts/garment_soft_body.gd` wraps Godot SoftBody3D, with a reusable Inspector
Resource in `components/garment_physics_profile.gd`: mass, stiffness, damping,
solver iterations and caller-owned collision proxy padding. It copies source meshes,
strips skin arrays, supports moving pins, explicit filters and solver-only cleanup.
Padding is not render thickness or a guaranteed self-collision distance.

The adapter is not wired into production dolls. It does not yet transfer a low-poly
simulated surface to a high-detail rendered garment or synchronize a moving body rig.
Custom vertex channels, material splits and blend-shape garment layers need validation.

Reviewed results from `tests/garment_soft_body_test.gd`:

- Current game DEFAULT/GodotPhysics3D: near-contact fixture 220 checks / 0 failures.
- Same backend with `--separated-colliders`: 220 checks / **2 failures**, exit 1.
  A hanging sheet misses the initially distant box/sphere in this fixture.
- Isolated **Jolt Physics**: near and separated fixtures pass, 220 checks / 0 failures.
  Main agent independently reran the separated fixture. Both triangle windings and
  welded pin aliases were also checked by the delegate; those were not the cause.
- This does not establish moving-character or multilayer garment reliability.

Isolated fixture retained at `captures/softbody-jolt-fixture/project.godot`; it contains
minimal settings plus copies of the profile, adapter and test. Refresh those copies
when changing the source. The shared game `project.godot` was **not** switched to Jolt.

From `D:/GodotProjects/weave-and-wander`, with the installed console executable:

```powershell
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --path prototypes/dollhouse-3d --headless --script tests/reference_hand_test.gd
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --path prototypes/dollhouse-3d --headless --script tests/garment_body_contact_test.gd
& 'D:/Godot/Godot_v4.7.1-stable_win64/Godot_v4.7.1-stable_win64_console.exe' --path prototypes/dollhouse-3d/captures/softbody-jolt-fixture --headless --fixed-fps 60 --script tests/garment_soft_body_test.gd -- --separated-colliders
```

## Next Implementation Gate

1. Preserve the hand/body proportions; await visual approval, not more body remodeling.
2. Use one skirt as the first physical garment. Define its seam/pin metadata and
   low-poly simulation cage, with render-mesh barycentric transfer and body proxies.
3. Validate moving hips/thighs, walking, sitting, nap, transition and teleport reset
   against Jolt in isolation. Test face interiors/edges, not only sampled vertices.
4. Add garment-layer and self-contact validation; choose close-up-only simulation,
   reduced solver frequency/LOD and baked pose correctives for other NPCs.
5. Only then evaluate a shared backend change with the existing game physics tests.
   Do not enable the slow fitting diagnostic globally or claim CLO-equivalent physics.

## Sources

- [CLO collision thickness](https://support.clo3d.com/hc/en-us/articles/115002798068-Adjust-Collision-Thickness)
- [CLO rendering thickness](https://support.clo3d.com/hc/en-us/articles/44177925839897-Rendering-Thickness)
- [Godot SoftBody3D](https://docs.godotengine.org/en/stable/classes/class_softbody3d.html)
- [Godot soft-body tutorial](https://docs.godotengine.org/en/4.6/tutorials/physics/soft_body.html)

The separation of collision and visual thickness comes from CLO's documented model;
the proposed cage/LOD pipeline is this project's engineering plan, not a claim about
CLO's proprietary solver implementation.
