# Loom integration review in progress

The implementation is not accepted yet. Root review findings against current code:

- `_plan_yarn` consumes multiple pigment lots but renders only the first colour. Must either restrict one lot with sufficient yarn or model and render actual yarn variation. Do not silently consume differently coloured yarn as uniform cloth.
- Batch parameters must be snapshotted on start: required picks, length, width, material and pattern cannot change midway and alter completed yield or debit.
- Current `woven_length` metadata is proportional but the visible cloth uses `.20 + fraction*.61` regardless of actual length, and fixed 1.88 width vs descriptor1.4. Need a supported visible web and rolled cloth geometry tracking the real amount, plus explicit warp setup distinct from completed fabric.
- Reach targets at shuttle extremes/roll crank may exceed arm length. Capture + actual hand/contact distances must prove seated actions work.
- Foot IK raises front hem only; seated skirts and calf contact require visual validation.
- Output mounts grow infinitely upward and are shared with seated operator access. Ensure stock physically fits reachable staging, or stop when full; depleted mounts can be reused.
- register_source_package API exists in production_flow; source-specific _fabric_candidates now honors mount material_access metadata. Verify retrieval AND remaining-bolt return at loom location.
- Single-hand spool regression passed after held_at=(.30,1.32,.25), max grip gap .04879.
- Current user goal includes all earlier unfinished geometry and runtime acceptance requests. Do not mark complete based only on loom ledger test.
