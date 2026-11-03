from pathlib import Path

from PIL import Image, ImageChops, ImageStat

captures = Path(__file__).resolve().parents[1] / "captures"
paths = sorted((captures / "roof_motion").glob("frame_*.png"))
assert len(paths) == 84, f"Expected 84 recorded frames, got {len(paths)}"
frames = []
for path in paths:
    with Image.open(path) as source:
        frames.append(source.convert("RGB").resize((1120, 630), Image.Resampling.LANCZOS))

roof_region = (200, 0, 920, 370)
for a, b in [(0, 20), (20, 50), (50, 83)]:
    difference = ImageChops.difference(frames[a].crop(roof_region), frames[b].crop(roof_region))
    change = sum(ImageStat.Stat(difference).mean)
    assert change > 5, f"Roof state {a} -> {b} did not visibly change: {change}"

for size in ["1600x900", "1280x960", "1280x800"]:
    width, height = map(int, size.split("x"))
    for state in ["closed", "left_open", "right_open"]:
        with Image.open(captures / f"hinged_roof_{state}_{size}.png") as source:
            assert source.size == (width, height), f"Incorrect capture size: {source.size}"
            room = source.convert("RGB").crop((width // 4, height // 2, width * 3 // 4, height * 4 // 5))
            assert sum(ImageStat.Stat(room).stddev) > 35, f"Blank room: {state} {size}"

palette = frames[20].quantize(colors=192)
indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
output = captures / "hinged_roof_demo.gif"
# Four 60 Hz simulation steps per GPU frame; only the roof is animated in this preview.
indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=67,
                loop=0, disposal=2, optimize=False)
print(f"ROOF_RENDER_CHECK frames={len(frames)} captures=9 motion_checks=3 output={output}")
