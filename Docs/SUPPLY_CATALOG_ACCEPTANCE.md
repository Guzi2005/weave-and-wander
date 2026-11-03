# Supply catalog and production queue acceptance

Requested 2026-10-29 for Weave&Wander.

- A saved shop assortment consists of named immutable recipe specifications: garment style, material, pattern, pigment, fabric width/thickness, thread, and garment/skirt lengths.
- Each entry has independent auto-restock enabled, target quantity, and allow-dye policy; one-click manual ordering works even with auto disabled and while another job runs.
- Auto restocking counts matching unsold finished stock plus pending/in-progress orders. Sold stock and different colors/patterns/lengths do not satisfy the target.
- Queue shows identity, recipe swatch, origin, stage, progress and actionable blocked reason. Pending orders can be cancelled/reordered; edited or deleted catalog entries cannot mutate already arranged recipes.
- Real workers execute dye and sewing; reservations lock the actual batch, inventory debits once, completion records once. A blocked entry must not prevent later feasible work.
- Dye substitution requires compatible material/pattern/width/thickness and sufficient quantity, dye stock and vat capacity. Respect manual dye jobs and existing reservations. Actual resulting pigment must match the recipe; manual overdye semantics must remain intact.
- Catalog persists across restart; invalid schema cannot corrupt current entries. Queue reload must not fabricate/resume production resources without matching persisted world state.
- Verify at 1280x720: scrollable readable catalogue/queue, no clipped action buttons, no focus lost during periodic refresh. Provide real game screenshot.

Status: implementation underway; no acceptance claims yet.
