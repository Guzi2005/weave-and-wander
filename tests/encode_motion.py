from pathlib import Path
from PIL import Image, ImageChops, ImageStat

capture_dir = Path(__file__).resolve().parents[1] / "captures"
paths = sorted((capture_dir / "motion").glob("frame_*.png"))
assert len(paths) == 96, f"Expected 96 frames, got {len(paths)}"
frames = [Image.open(path).convert("RGB") for path in paths]
change = sum(ImageStat.Stat(ImageChops.difference(frames[0], frames[32])).mean)
assert change > 1, f"Turntable is static: {change}"
for name in ["dolls_3d.png", "dollhouse_3d.png", "tablet_4_3.png", "tablet_wardrobe.png"]:
    image = Image.open(capture_dir / name).convert("RGB")
    assert sum(ImageStat.Stat(image).stddev) > 20, f"Blank render: {name}"
palette = frames[0].quantize(colors=128)
indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
output = capture_dir / "dolls_3d_simple_baseline.gif"
indexed[0].save(output, save_all=True, append_images=indexed[1:],
                duration=[40, 40, 45] * 32, loop=0, optimize=False, disposal=2)
print(f"RENDER_CHECK frames={len(frames)} change={change:.3f} output={output}")
