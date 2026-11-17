"""Focused strain and actual Blender rest-metric regressions."""
from pathlib import Path
import json
import runpy
import sys
import unittest

import bpy
from mathutils import Matrix, Vector

M = runpy.run_path(str(Path(__file__).with_name('current_hem_study_blender.py')))


class StrainTests(unittest.TestCase):
    def setUp(self):
        self.points = [[0, .2, 0], [1, .2, 0], [0, .3, 0]]

    def test_rigid_motion_has_no_strain(self):
        rotation = Matrix.Rotation(.8, 3, 'Y')
        posed = [list(rotation @ Vector(p) + Vector((2, 4, -1))) for p in self.points]
        report = M['strain'](self.points, posed, [0, 1, 2])
        self.assertAlmostEqual(report['all']['maximum_ratio'], 1, places=5)
        self.assertEqual(report['all']['over_screening_limit'], 0)

    def test_extension_is_measured_not_hidden(self):
        report = M['strain'](self.points, [[2 * v for v in p] for p in self.points], [0, 1, 2])
        self.assertAlmostEqual(report['all']['maximum_ratio'], 2)
        self.assertEqual(report['all']['over_screening_limit'], 3)

    def test_invalid_input_rejected(self):
        for indices in [[0, 1], [0, 1, 99]]:
            with self.assertRaises(ValueError):
                M['strain'](self.points, self.points, indices)


class RestMetricTests(unittest.TestCase):
    def test_nonzero_metric_changes_actual_cloth_rest_length(self):
        original = bpy.context.window.scene
        scenes = []
        widths = []
        try:
            for explicit in [False, True]:
                scene = bpy.data.scenes.new('WW_RestMetric_Regression')
                scenes.append(scene)
                bpy.context.window.scene = scene
                scene.gravity = (0, 0, 0)
                mesh = bpy.data.meshes.new('MetricPatch')
                mesh.from_pydata([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [], [(0, 1, 2), (0, 2, 3)])
                obj = bpy.data.objects.new('MetricPatch', mesh)
                scene.collection.objects.link(obj)
                basis = obj.shape_key_add(name='Basis')
                pose = obj.shape_key_add(name='StretchedStart')
                for v in pose.data:
                    v.co.x *= 2
                pose.value = 1.
                obj['welded_representatives'] = [0, 1, 2, 3]
                modifier = obj.modifiers.new('Cloth', 'CLOTH')
                modifier.settings.quality = 20
                modifier.settings.mass = .01
                modifier.settings.air_damping = 2
                modifier.settings.tension_stiffness = 40
                modifier.settings.compression_stiffness = 40
                modifier.point_cache.frame_end = 60
                modifier.settings.rest_shape_key = basis
                if explicit:
                    key = M['_set_rest_metric'](obj, [[0, 0, 0], [1, 0, 0], [1, 0, -1], [0, 0, -1]])
                    self.assertGreater(obj.data.shape_keys.key_blocks.find(key.name), 0)
                    self.assertEqual(key.value, 0.)
                mesh.update()
                obj.update_tag()
                scene.frame_set(0)
                bpy.context.view_layer.update()
                for frame in range(1, 61):
                    scene.frame_set(frame)
                    points = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices
                widths.append((points[1].co - points[0].co).length)
                print('METRIC_CACHE', explicit, modifier.point_cache.info, modifier.point_cache.is_outdated,
                      obj.data.shape_keys.key_blocks.find(modifier.settings.rest_shape_key.name))
            print('ACTUAL_REST_METRIC basis_vs_explicit=', widths)
            self.assertGreater(widths[0], 1.9)
            self.assertLess(widths[1], 1.2)
        finally:
            bpy.context.window.scene = original
            for scene in scenes:
                for obj in list(scene.objects):
                    data = obj.data
                    bpy.data.objects.remove(obj, do_unlink=True)
                    bpy.data.meshes.remove(data)
                bpy.data.scenes.remove(scene)


def run():
    result = unittest.TextTestRunner(stream=sys.stdout, verbosity=1).run(unittest.TestSuite(
        unittest.defaultTestLoader.loadTestsFromTestCase(c) for c in [StrainTests, RestMetricTests]))
    report = {'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors),
              'passed': result.wasSuccessful(), 'blender': bpy.app.version_string,
              'failure_details': [{'test': str(test), 'traceback': trace} for test, trace in result.failures],
              'error_details': [{'test': str(test), 'traceback': trace} for test, trace in result.errors]}
    (M['ROOT'] / 'captures/current_hem_regression.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    if not result.wasSuccessful():
        raise AssertionError('Current hem regression failed')
    return report
