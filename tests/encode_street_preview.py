from pathlib import Path

from PIL import Image, ImageChops, ImageStat

captures = Path(__file__).resolve().parents[1] / "captures"
paths = sorted((captures / "street_motion").glob("frame_*.png"))
assert len(paths) == 132, f"Expected 132 actual GPU frames, got {len(paths)}"
frames = []
for path in paths:
    with Image.open(path) as source:
        frames.append(source.convert("RGB").resize((1120, 630), Image.Resampling.LANCZOS))

for a, b in [(0, 35), (35, 67), (67, 115)]:
    difference = ImageChops.difference(frames[a], frames[b])
    change = sum(ImageStat.Stat(difference).mean)
    assert change > 1, f"Street recording does not change: {a} -> {b}: {change}"

for size in ["1600x900", "1280x960", "1280x800"]:
    width, height = map(int, size.split("x"))
    for state in ["exterior", "interior_delivery", "postman_close"]:
        with Image.open(captures / f"street_{state}_{size}.png") as source:
            assert source.size == (width, height)
            view = source.convert("RGB").crop((width // 4, height // 3, width * 3 // 4, height * 4 // 5))
            assert sum(ImageStat.Stat(view).stddev) > 25, f"Blank view: {state} {size}"

# Shared palette avoids flashing between the exterior and cutaway view.
palette_source = Image.new("RGB", (1120, 1260))
palette_source.paste(frames[30], (0, 0))
palette_source.paste(frames[67], (0, 630))
palette = palette_source.quantize(colors=224)
indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
output = captures / "street_post_demo.gif"
indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=90,
                loop=0, disposal=2, optimize=False)
print(f"STREET_RENDER_CHECK frames={len(frames)} views=9 output={output}")

close_paths = sorted((captures / "postal_motion").glob("frame_*.png"))
assert len(close_paths) == 48, "Missing postal skinning recording"
close_frames = []
for path in close_paths:
    with Image.open(path) as source:
        close_frames.append(source.convert("RGB").resize((1120, 630), Image.Resampling.LANCZOS))
assert sum(ImageStat.Stat(ImageChops.difference(close_frames[0], close_frames[24])).mean) > 0.1
close_palette = close_frames[0].quantize(colors=224)
close_indexed = [frame.quantize(palette=close_palette, dither=Image.Dither.NONE) for frame in close_frames]
close_output = captures / "postal_clothing_cycle.gif"
close_indexed[0].save(close_output, save_all=True, append_images=close_indexed[1:], duration=45,
                      loop=0, disposal=2, optimize=False)
print(f"POSTAL_RENDER_CHECK frames={len(close_frames)} output={close_output}")
