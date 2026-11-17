"""Separate a regular skirt simulation cage from its unchanged render topology."""
import bisect
import math


def _blend(values, binding):
    ids, weights = binding
    return [sum(values[i][axis] * weight for i, weight in zip(ids, weights)) for axis in range(3)]


def _binding(heights, columns, y, column):
    upper = min(len(heights) - 1, max(1, bisect.bisect_right(heights, y)))
    lower = upper - 1
    along = max(0, min(1, (y - heights[lower]) / (heights[upper] - heights[lower])))
    left = math.floor(column) % columns
    right = (left + 1) % columns
    around = column - math.floor(column)
    return ([lower * columns + left, lower * columns + right,
             upper * columns + left, upper * columns + right],
            [(1-along)*(1-around), (1-along)*around, along*(1-around), along*around])


def build(data, rings=12, columns=20):
    original = data['base_skirt']
    rows = {}
    for i, p in enumerate(original['vertices']):
        rows.setdefault(round(p[1], 5), []).append(i)
    heights = sorted(rows)
    source_columns = len(rows[heights[0]]) - 1
    source_ids = []
    for y in heights:
        ids = rows[y]
        first, last = original['vertices'][ids[0]], original['vertices'][ids[-1]]
        if len(ids) != source_columns + 1 or sum((a-b)**2 for a, b in zip(first, last)) > 1e-10:
            raise ValueError('Cage requires an ordered periodic lathe grid')
        source_ids.extend(ids[:-1])
    cage_heights = [heights[0] + (heights[-1] - heights[0]) * r / (rings - 1) for r in range(rings)]
    source_bindings = []
    for y in cage_heights:
        for column in range(columns):
            ids, weights = _binding(heights, source_columns, y, column * source_columns / columns)
            source_bindings.append(([source_ids[i] for i in ids], weights))
    vertices = [_blend(original['vertices'], b) for b in source_bindings]
    normals = [_blend(original['normals'], b) for b in source_bindings]
    indices = []
    for row in range(rings - 1):
        for column in range(columns):
            a, b = row * columns + column, (row + 1) * columns + column
            c, d = row * columns + (column + 1) % columns, (row + 1) * columns + (column + 1) % columns
            indices.extend([a, b, c, c, b, d])
    render_bindings = [None] * len(original['vertices'])
    for y in heights:
        for column, original_id in enumerate(rows[y]):
            render_bindings[original_id] = _binding(cage_heights, columns, y, column * columns / source_columns)
    samples = [(f['frame'], [_blend(f['cloth_pin_targets'], b) for b in source_bindings]) for f in data['frames']]
    return {'vertices': vertices, 'normals': normals, 'indices': indices}, samples, source_bindings, render_bindings


def transfer(data, cage_posed, cage_base, source_bindings, render_bindings):
    from mathutils import Matrix, Vector
    inverses = data['frames'][-1]['cloth_inverse_skin_transforms']
    deltas = []
    for p, rest, (ids, weights) in zip(cage_posed, cage_base, source_bindings):
        local = sum(((Matrix(inverses[i]['basis_rows']) @ Vector(p) + Vector(inverses[i]['origin'])) * w
                     for i, w in zip(ids, weights)), Vector())
        deltas.append(list(local - Vector(rest)))
    vertices = []
    posed = []
    for rest, binding, transform in zip(data['base_skirt']['vertices'], render_bindings, inverses):
        local = Vector(rest) + Vector(_blend(deltas, binding))
        vertices.append(list(local))
        posed.append(list(Matrix(transform['basis_rows']).inverted() @ (local - Vector(transform['origin']))))
    return posed, vertices
