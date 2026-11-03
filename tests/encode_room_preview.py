from pathlib import Path

from PIL import Image, ImageChops, ImageStat

captures = Path(__file__).resolve().parents[1] / "captures"
paths = sorted((captures / "room_motion").glob("frame_*.png"))
assert len(paths) == 90, f"Expected 90 recorded frames, got {len(paths)}"
frames = []
for path in paths:
    with Image.open(path) as source:
        frames.append(source.convert("RGB").resize((1120, 630), Image.Resampling.LANCZOS))
change = sum(ImageStat.Stat(ImageChops.difference(frames[0], frames[45])).mean)
assert change > 0.6, f"Room recording is static: {change}"
for name in ["single_room.png", "single_room_tablet.png", "single_room_wide_tablet.png"]:
    with Image.open(captures / name) as image:
        room = image.convert("RGB").crop((image.width // 6, image.height // 4, image.width - 40, image.height * 3 // 4))
        assert sum(ImageStat.Stat(room).stddev) > 35, f"Blank room: {name}"
palette = frames[45].quantize(colors=192)
indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
output = captures / "single_room_running.gif"
# Timelapse of real GPU frames: 30 simulated seconds in 15 playback seconds.
indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=167,
                loop=0, disposal=2, optimize=False)
print(f"ROOM_RENDER_CHECK frames={len(frames)} change={change:.3f} output={output}")
