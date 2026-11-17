"""Optional offline cache denoising in the actual pinned waist's moving frame.

Not a cloth solver or a runtime filter. Preserve every pinned point and the two
endpoints; collision, displacement and visual acceptance remain separate gates.
"""

import math

from mathutils import Matrix, Vector


def _frame(points, anchors):
    origin, along, across = [Vector(points[index]) for index in anchors]
    x = (along - origin).normalized()
    z = x.cross(across - origin).normalized()
    if z.length_squared < .5:
        raise ValueError('Collapsed moving waist frame')
    y = z.cross(x).normalized()
    return origin, Matrix((x, y, z)).transposed()


def filter_samples(samples, rest, pin_lower_y, radius=1):
    if type(radius) is not int or radius not in (1, 2):
        raise ValueError('Only one- or two-frame offline windows are supported')
    if len(samples) < radius * 2 + 3 or [s['frame'] for s in samples] != list(range(1, len(samples) + 1)):
        raise ValueError('Expected a complete consecutive cache')
    if any(len(s['posed']) != len(rest) for s in samples):
        raise ValueError('Cache topology changed')
    if not all(math.isfinite(c) for s in samples for p in s['posed'] for c in p):
        raise ValueError('Nonfinite cached position')
    pinned = {i for i, p in enumerate(rest) if p[1] >= pin_lower_y - 1e-6}
    top = max(p[1] for p in rest)
    ring = [i for i in pinned if rest[i][1] >= top - 1e-6]
    if len(ring) < 3:
        raise ValueError('No pinned waist ring')
    a = ring[0]
    b = max(ring, key=lambda i: (Vector(rest[i]) - Vector(rest[a])).length_squared)
    axis = Vector(rest[b]) - Vector(rest[a])
    c = max(ring, key=lambda i: axis.cross(Vector(rest[i]) - Vector(rest[a])).length_squared)
    anchors = [a, b, c]
    frames = [_frame(sample['posed'], anchors) for sample in samples]
    local = [[basis.transposed() @ (Vector(point) - origin) for point in sample['posed']]
             for sample, (origin, basis) in zip(samples, frames)]
    kernel = [1, 2, 1] if radius == 1 else [1, 4, 6, 4, 1]
    total = sum(kernel)
    result, deltas = [], []
    for frame, sample in enumerate(samples):
        points = [list(p) for p in sample['posed']]
        blend = min(1.0, frame / radius, (len(samples) - 1 - frame) / radius)
        maximum = 0.0
        if blend > 0:
            origin, basis = frames[frame]
            for index in range(len(rest)):
                if index in pinned:
                    continue
                point = sum((local[max(0, min(len(samples) - 1, frame + k - radius))][index] * weight
                             for k, weight in enumerate(kernel)), Vector()) / total
                proposed = origin + basis @ local[frame][index].lerp(point, blend)
                maximum = max(maximum, (proposed - Vector(points[index])).length)
                points[index] = list(proposed)
        result.append({**sample, 'posed': points})
        deltas.append(maximum)
    return result, {
        'method': 'Offline symmetric binomial cache filter in a three-anchor pinned waist frame',
        'radius_frames': radius, 'kernel': kernel, 'anchors': anchors,
        'pinned_vertices': len(pinned), 'endpoint_fade': True,
        'max_delta': max(deltas), 'frame_deltas': deltas,
    }
