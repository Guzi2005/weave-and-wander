"""Assemble actual Godot capture frames without changing their content."""
from pathlib import Path
from PIL import Image

captures = Path(__file__).resolve().parents[1] / "captures"
sources = sorted((captures / "garment_motion_frames").glob("frame_*.png"))
assert len(sources) == 64, f"Expected 64 GPU frames, found {len(sources)}"
frames = []
for source in sources:
    with Image.open(source) as raw:
        image = raw.convert("RGB")
        image.thumbnail((720, 720), Image.Resampling.LANCZOS)
        frames.append(image)
target = captures / "garment_turn_stop.gif"
frames[0].save(target, save_all=True, append_images=frames[1:], duration=50,
               loop=0, disposal=2, optimize=False)
print(f"Encoded {len(frames)} actual GPU frames: {target}")
