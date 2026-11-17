"""Run via Blender MCP; compare exported rest/contact surfaces without scene edits."""
import hashlib
import json
from pathlib import Path

from mathutils import Vector
from mathutils.bvhtree import BVHTree


def analyze(folder, suffix=""):
    source = Path(folder) / "rest_contact_geometry.json"
    report = []
    for entry in json.loads(source.read_text(encoding="utf-8")):
        skirt = entry["skirt"]
        points = [Vector(p) for p in skirt["vertices"]]
        raw = [Vector(p) for p in skirt["raw"]]
        indices = skirt["indices"]
        faces = [indices[i:i + 3] for i in range(0, len(indices), 3)]
        tree = BVHTree.FromPolygons(points, faces, all_triangles=True)
        unique = {}
        welded = []
        for p in raw:
            key = tuple(round(v, 5) for v in p)
            welded.append(unique.setdefault(key, len(unique)))
        face_sets = [set(welded[i] for i in face) for face in faces]
        pairs = {(min(a, b), max(a, b)) for a, b in tree.overlap(tree)
                 if a != b and not face_sets[a].intersection(face_sets[b])}
        reversed_faces = 0
        edge_ratios = []
        for a, b, c in faces:
            old = (raw[b] - raw[a]).cross(raw[c] - raw[a])
            new = (points[b] - points[a]).cross(points[c] - points[a])
            if old.length_squared > 1e-14 and new.length_squared > 1e-14:
                reversed_faces += old.normalized().dot(new.normalized()) < -0.5
            for u, v in [(a, b), (b, c), (c, a)]:
                length = (raw[u] - raw[v]).length
                if length > 1e-6:
                    edge_ratios.append((points[u] - points[v]).length / length)
        body_intersections = []
        for body in entry["body"]:
            body_faces = [body["indices"][i:i + 3] for i in range(0, len(body["indices"]), 3)]
            body_tree = BVHTree.FromPolygons([Vector(p) for p in body["vertices"]], body_faces, all_triangles=True)
            body_intersections.append({"name": body["name"], "triangle_pairs": len(tree.overlap(body_tree))})
        edge_ratios.sort()
        report.append({"pose": entry["pose"], "mode": entry["mode"],
                       "nonadjacent_self_pairs": len(pairs), "normal_reversals_over_120deg": reversed_faces,
                       "max_edge_ratio": max(edge_ratios), "p95_edge_ratio": edge_ratios[int(len(edge_ratios) * .95)],
                       "body_intersections": body_intersections})
    target = source.with_name("rest_contact_blender" + suffix + ".json")
    target.write_text(json.dumps({"input_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                                 "method": "Blender BVH triangle overlaps, excluding welded adjacent self faces; geometric diagnostics, not CCD",
                                 "results": report}, indent=2), encoding="utf-8")
    print(json.dumps({"report": str(target), "results": report}))
