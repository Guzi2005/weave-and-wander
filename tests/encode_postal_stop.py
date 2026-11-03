from pathlib import Path

from PIL import Image, ImageChops, ImageStat

captures = Path(__file__).resolve().parents[1] / "captures"
paths = sorted((captures / "postal_stop_motion").glob("frame_*.png"))
assert len(paths) == 132, f"Expected 132 GPU frames, got {len(paths)}"
frames = []
for path in paths:
    with Image.open(path) as source:
        frames.append(source.convert("RGB").resize((960, 600), Image.Resampling.LANCZOS))
for a, b in [(0, 40), (66, 100)]:
    assert sum(ImageStat.Stat(ImageChops.difference(frames[a], frames[b])).mean) > 1
palette = frames[30].quantize(colors=192)
indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
durations = [50] * len(indexed)
# Separate the two close-up excerpts without pretending they are a continuous visit.
durations[65] = 700
durations[-1] = 700
output = captures / "postal_stop_and_start.gif"
indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=durations,
                loop=0, disposal=2, optimize=False)
print(f"POSTAL_STOP_RENDER_CHECK frames={len(frames)} output={output}")
