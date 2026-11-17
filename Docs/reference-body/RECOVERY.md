# Full Body Recovery - 2026-11-09

## Superseded: User Requested Pre-Session Rollback

The user confirmed that an actual model was edited, then explicitly requested
restoring the project to before today's model discussion. That rollback is now
applied; do not continue the recovery plan below automatically.

The active experimental class is restored to the 297-line source preceding the
first patch at 2026-11-09 19:39:27 Asia/Shanghai. The matching early source reads
and inverse patches are documented in the snapshot directory. Later source and
asset experiments have been moved out of the active game project into
`D:/GodotProjects/weave-and-wander/prototypes/snapshots/body-work-20261109-before-rollback/` (relative to the game root).
The original hand asset, hosiery, and unrelated work are preserved.

Further read-only investigation found Antigravity's V20 full-source write in
conversation `5f98a330-d5ca-4e58-9a01-26631b9dde29`, step 2360. It is saved only as
`recovered_v20_not_applied.gd.txt` in the snapshot directory. It was NOT made the
runtime model after the user's rollback instruction. Earlier candidate script
and test paths below now refer to archived files, not active project files.

## Status: User-Tuned Version Not Yet Recovered Exactly

The user's target is `user-tuned-body-2026-11-09.png`, copied without alteration
from the latest attachment. It is byte-identical to the earlier `65ec0fcf` image.
SHA256: `F55A12EE9E9E0DB71A4B009AE1F04259E1D5E3BA6C4B9D547B17B0E2821626BA`.

Do not conflate these three models:

- The user's complete, smooth, manually tuned mannequin in that image.
- The original dressed `VolumeDoll`, which does not contain a complete underbody.
- Later rejected shoulder, hand, height-map and fused-mesh experiments.

The previous claim that there was no complete mannequin was incorrect. It was
based only on inspecting the dressed VolumeDoll, not the user's mannequin.

## Recovered Evidence

`experimental_full_body_2026-11-05.gd.txt` is a historical source snapshot from a
local Codex command output at 2026-11-05 06:58:00 UTC. The originating session is
`rollout-2026-11-04T08-35-42-01a1950f-40f0-7722-a240-51e201d70a28_01a1a3fb-ac50-7c73-967d-86ad76b5413f.jsonl`,
line 144, `payload.output[1].text`. Only the script was extracted; following
command output was excluded, and line endings normalized to LF.
SHA256: `FA156DAA691697327A45EE216C54F58AF112528670F4B7C54EA255221223C810`.

`scripts/recovered_early_full_body_doll.gd` differs only by global class name.
No geometry, rig parameters, or body proportions were edited during recovery.
This is an EARLY candidate, not an accepted restoration of the user's image.
The current shared parent and rig are still dependencies, not frozen snapshots.
The Nov 9 11:38 UTC source-read record has the same first 140 lines but replaces
the original procedural palm with shared_hand; it is not an exact target match.

Actual GPU previews: `captures/recovered_early_body_front.png` and `_quarter.png`.
The early candidate has shoulder protrusions and different calf contours compared
with the user's target. Do not claim an exact match or remodel it speculatively.
Initial captures named `recovered_reference_body_*` are superseded diagnostics.

The later hosiery shader hides leg pixels above the skirt hem even when the skirt
is hidden. The dedicated capture overrides only those materials to reveal the
existing body; it does not add missing geometry or alter the shape.

## Checks and Next Steps

### Accepted on 2026-11-10

The user explicitly approved the V20 render and requested slightly shorter arms.
`scripts/accepted_body_v20.gd` now preserves that source inside the project, with
only the global class name changed. Source parity against step2310 passed.
`scripts/shorter_arm_body.gd` is an isolated adjustment: 0.045 upward hand offset,
fixed shoulder, unchanged palm/thumb shape, smooth arm shortening. Its own rest
bones and Skin follow the offset; shared rig and active NPCs remain untouched.
`scenes/accepted_mannequin.tscn` exposes `arm_shortening`; zero restores V20.
GPU comparison: `captures/accepted_body_shorter_arm_front.png` and `_quarter.png`,
baseline left, adjustment right. Regression: 67247 checks, zero failures.
The user subsequently replied "ok." to this comparison, approving the 0.045
short-arm delta as the new body baseline. Preserve V20 and zero-value rollback.
Do not confuse this accepted model with earlier rejected split-body rollbacks.
This approval does not mean active clothed NPCs were replaced or all poses fitted.

### Newer recovery finding: V20 source, awaiting recognition

The user rejected the Nov9 pre-conversation rollback and requested an earlier
version. The correct V20 source is in Antigravity conversation
`5f98a330-d5ca-4e58-9a01-26631b9dde29`, step2310. Step2324 modifies only the shoe;
step2328 renders V20 and step2330 saves its screenshots. The previously extracted
step2360 is V21 (rendered in step2362), NOT V20. This chronology correction
explains the remaining shoulder and calf mismatch in the first isolated attempt.

Correct original source and a class-name-only runnable copy are saved outside
the active game in `D:/GodotProjects/weave-and-wander/prototypes/snapshots/body-work-20261109-before-rollback/` as
`recovered_v20_not_applied.gd.txt` and `historical_body_v20.gd`.
The misidentified source is retained as `historical_step2360_v21.gd.txt`.
Actual Godot GPU front/quarter images: `captures/historical_v20_front.png` and
`captures/historical_v20_quarter.png`. Source parity passed; images inspected.
No active model replacement yet. Await user recognition, not another redesign.
Shared parent/rig dependencies are current; this is not a frozen historical build.

### Earlier checks (not acceptance of the rejected candidate)

- Godot MCP validated the recovered script.
- `historical_mannequin_recovery_test.gd`: source parity and 12 anatomical parts pass.
- `reference_dressed_restore_test.gd`: 2245 checks, 0 failures; game baseline unchanged.
- Exact visual restoration is still pending. The user was asked where their manual
  adjustments were made (Godot/Blender/model versus an edited reference image).
- Follow that editing source/save history next. Preserve the screenshot, this
  archive, the dressed baseline and rejected experiments separately.
- Do not re-enable the rejected experimental class or overwrite the user's edits.
