"""Run inside Blender via MCP after game_body_fit_capture.gd --export-contact."""
import hashlib
import json
from pathlib import Path

from mathutils import Vector
from mathutils.bvhtree import BVHTree


def check(capture_directory, input_name="game_body_contact_input.json", output_name="game_body_contact_report.json", poses=None):
    folder = Path(capture_directory)
    source = folder / input_name
    data = json.loads(source.read_text(encoding="utf-8"))
    direction = Vector((0.843, 0.223, 0.489)).normalized()
    results = []
    for entry in data:
        if poses is not None and entry["pose"] not in poses:
            continue
        volumes = []
        for part in entry["body"]:
            points = [Vector(p) for p in part["vertices"]]
            indices = part["indices"]
            tree = BVHTree.FromPolygons(points, [indices[i:i + 3] for i in range(0, len(indices), 3)], all_triangles=True)
            low = Vector(tuple(min(p[k] for p in points) for k in range(3)))
            high = Vector(tuple(max(p[k] for p in points) for k in range(3)))
            volumes.append((part["name"], tree, low, high))
        for cloth in entry["cloth"]:
            points = [Vector(p) for p in cloth["vertices"]]
            indices = cloth["indices"]
            samples = points + [sum((points[j] for j in indices[i:i + 3]), Vector()) / 3 for i in range(0, len(indices), 3)]
            contacts = {}
            for point in samples:
                for name, tree, low, high in volumes:
                    if any(point[k] < low[k] or point[k] > high[k] for k in range(3)):
                        continue
                    origin = point.copy()
                    hits = 0
                    for _ in range(24):
                        hit, _, _, _ = tree.ray_cast(origin, direction, 10)
                        if hit is None:
                            break
                        hits += 1
                        origin = hit + direction * 0.00001
                    if hits % 2:
                        nearest = tree.find_nearest(point)
                        depth = nearest[3] if nearest else 0
                        if depth > 0.001:
                            contact = contacts.setdefault(name, {"samples": 0, "max_depth": 0})
                            contact["samples"] += 1
                            contact["max_depth"] = round(max(contact["max_depth"], depth), 6)
            results.append({"style": entry["style"], "pose": entry["pose"], "cloth": cloth["name"], "sample_count": len(samples), "contacts": contacts})
    report = {
        "input_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "method": "Blender BVH ray parity, body volumes, post-skin contact vertices and triangle centers",
        "limits": "Diagnostic, not acceptance. Input may be CPU-evaluated or uncorrected (see capture metadata); hidden nested panels can intersect limbs. No temporal CCD or cloth self-collision. Inspect actual GPU captures too.",
        "results": results,
    }
    (folder / output_name).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"mesh_pose_checks": len(results), "with_candidate_contacts": sum(bool(r["contacts"]) for r in results), "report": str(folder / output_name)}))


if __name__ == "__main__":
    check("D:/workspace/weave-and-wander/captures")
