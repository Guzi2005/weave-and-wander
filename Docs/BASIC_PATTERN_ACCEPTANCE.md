# Basic pattern revision acceptance

Active work: styles 10 Cuban shirt, 11 babydoll blouse, 12 adjustable skirt, 13 academic V-neck vest; continuous crossed apron straps.

Body proportions and shoulder silhouette must follow the original game reference supplied on 2026-10-29. ImageGen turnarounds v1-v3 are garment construction references only; their altered body proportions are not authoritative.

Verified 2026-10-29: basic_garment_sales_test.gd runs four styles through reserve, cut, sew, output, storage, rack, carry, wear, checkout and collection. Checks pigment/pattern retention, recorded transaction, price, duplicate-checkout rejection. Output BASIC_GARMENT_SALES_TEST styles=4 failures=0 after refreshing Godot imports. This does not yet validate autonomous customer selection or the full animated production sequence.

Visual acceptance remains open: rebuild Cuban collar/shoulder/sleeve joins and babydoll gathered silhouette; inspect vest and apron front/side/back in the actual game; confirm length changes leave neckline and sleeves fixed; inspect layered moving poses. No completion claim until these pass.
