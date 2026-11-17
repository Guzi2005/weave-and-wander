"""Small math/diagnostic guards for isolated silhouette experiments in Blender."""

from pathlib import Path
import runpy
import unittest

from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parent
SHAPE = runpy.run_path(str(ROOT / 'shape_sleep_silhouette_blender.py'))
FILTER = runpy.run_path(str(ROOT / 'cloth_cache_filter.py'))
AUDIT = runpy.run_path(str(ROOT / 'audit_native_layers_blender.py'))


class SilhouetteTests(unittest.TestCase):
    def test_envelope_uses_boundary_not_interior(self):
        hull = SHAPE['_hull']([[-1, -2, 0], [1, -2, 0], [1, 2, 0], [-1, 2, 0], [0, 0, 0]], 1)
        for x in [-2, -1, -.5, 0, .5, 1, 2]:
            low, high = SHAPE['_envelope'](hull, x)
            self.assertAlmostEqual(low, -2)
            self.assertAlmostEqual(high, 2)

    def test_strength_guards_precede_io(self):
        for strength in [-.1, 1.1, float('nan')]:
            with self.assertRaises(ValueError):
                SHAPE['build']('missing', 'missing', back_strength=strength)
        for strength in [0, .51, float('nan')]:
            with self.assertRaises(ValueError):
                SHAPE['relax']('missing', guide_weight=strength)

    def test_smooth_mask_bounded(self):
        values = [SHAPE['_smooth'](i / 10) for i in range(-5, 16)]
        self.assertEqual(values, sorted(values))
        self.assertEqual(values[0], 0)
        self.assertEqual(values[-1], 1)


class CacheFilterTests(unittest.TestCase):
    def setUp(self):
        self.rest = [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1], [0, 0, 0]]
        self.samples = []
        for i in range(9):
            rotation = Matrix.Rotation(i * .1, 3, 'Z')
            translation = Vector((i * .2, i * .01, -.3))
            self.samples.append({'frame': i + 1, 'posed': [list(rotation @ Vector(p) + translation) for p in self.rest]})

    def test_rigid_motion_preserved(self):
        for radius in [1, 2]:
            result, report = FILTER['filter_samples'](self.samples, self.rest, .9, radius)
            self.assertLess(report['max_delta'], 1e-6)
            self.assertEqual(result[0]['posed'], self.samples[0]['posed'])
            self.assertEqual(result[-1]['posed'], self.samples[-1]['posed'])

    def test_pins_preserved_and_spike_reduced(self):
        self.samples[4]['posed'][4][2] += .1
        result, report = FILTER['filter_samples'](self.samples, self.rest, .9)
        for actual, original in zip(result, self.samples):
            self.assertEqual(actual['posed'][:4], original['posed'][:4])
        self.assertAlmostEqual(result[4]['posed'][4][2], -.25, places=5)
        self.assertGreater(report['max_delta'], .04)

    def test_invalid_cache_rejected(self):
        for radius in [0, 3, 1.5]:
            with self.assertRaises(ValueError):
                FILTER['filter_samples'](self.samples, self.rest, .9, radius)
        self.samples[4]['frame'] = 99
        with self.assertRaises(ValueError):
            FILTER['filter_samples'](self.samples, self.rest, .9)


class LayerAuditTests(unittest.TestCase):
    def test_intersection_roles_and_totals(self):
        horizontal = [[-1, -1, 0], [1, -1, 0], [0, 1, 0]]
        vertical = [[0, -.5, -1], [0, -.5, 1], [0, .5, 0]]
        parts = [{'name': 'cloth', 'role': 'cloth', 'vertices': horizontal, 'indices': [0, 1, 2]},
                 {'name': 'body', 'role': 'body', 'vertices': vertical, 'indices': [0, 1, 2]},
                 {'name': 'support', 'role': 'support', 'vertices': horizontal, 'indices': [0, 1, 2]}]
        records, body_support = AUDIT['_part_records'](parts)
        self.assertEqual(body_support, 1)
        self.assertEqual(records[0]['nonadjacent_self_pairs'], 0)
        self.assertEqual(records[0]['contacts'][0]['triangle_pairs'], 1)
        self.assertEqual(records[0]['contacts'][0]['role'], 'body')

    def test_shared_seam_is_not_self_intersection(self):
        part = {'name': 'cloth', 'role': 'cloth', 'vertices': [[0, 0, 0], [1, 0, 0], [0, 1, 0],
                [1, 0, 0], [1, 1, 0], [0, 1, 0]], 'indices': list(range(6))}
        records, _ = AUDIT['_part_records']([part])
        self.assertEqual(records[0]['nonadjacent_self_pairs'], 0)
        self.assertEqual(records[0]['degenerate_triangles'], 0)


def run():
    suite = unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromTestCase(cls)
                               for cls in [SilhouetteTests, CacheFilterTests, LayerAuditTests])
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    if not result.wasSuccessful():
        raise AssertionError('Silhouette/filter/audit regression failed')
    return {'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors)}
