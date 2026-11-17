"""Crop actual model captures for wiki motif cards; sources stay unchanged."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT.parent / "W&W Wiki/public/assets/motifs"
OUT.mkdir(parents=True, exist_ok=True)
for source, box, name in [
    ("back.png", (330, 620, 870, 1160), "stripe-overskirt.png"),
    ("waist.png", (350, 900, 790, 1340), "tassel-sash.png"),
]:
    with Image.open(ROOT / "captures/ukrainian_preview" / source) as image:
        preview = image.crop(box).convert("RGB")
        preview.save(OUT / name, optimize=True)
        print(name, preview.size)
