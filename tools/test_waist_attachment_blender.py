"""Regression checks for the isolated waist proof, run through live Blender MCP."""

import copy
from pathlib import Path
import runpy
import unittest

import bpy


MODULE = runpy.run_path(str(Path(__file__).with_name('attach_waist_seam_blender.py')))


class MotionSeedTests(unittest.TestCase):
    def setUp(self):
        self.audit = {
            'cache_validation': {'is_outdated': False, 'is_frame_skip': False, 'last_sequential_frame': 180},
            'attachment_guard_frames': [], 'final_snapshot_delta': 0.0,
            'frames': [{'frame': i, 'self_triangle_pairs': []} for i in range(1, 181)],
        }

    def test_ordered_complete_seed(self):
        self.audit['frames'][60]['self_triangle_pairs'] = [[2, 1], [1, 2]]
        self.assertEqual(MODULE['_motion_seed_pairs'](self.audit, 5), {(1, 2)})

    def test_reject_invalid_cache_and_endpoint(self):
        for field, value in [('is_outdated', True), ('is_frame_skip', True), ('last_sequential_frame', 179)]:
            data = copy.deepcopy(self.audit)
            data['cache_validation'][field] = value
            with self.assertRaises(ValueError):
                MODULE['_motion_seed_pairs'](data, 5)
        for value in [0.01, float('nan')]:
            data = copy.deepcopy(self.audit)
            data['final_snapshot_delta'] = value
            with self.assertRaises(ValueError):
                MODULE['_motion_seed_pairs'](data, 5)

    def test_reject_skipped_duplicate_or_misordered_frames(self):
        for frames in [self.audit['frames'][:-1], list(reversed(self.audit['frames'])), self.audit['frames'][:179] + [self.audit['frames'][178]]]:
            with self.assertRaises(ValueError):
                MODULE['_motion_seed_pairs']({**self.audit, 'frames': frames}, 5)

    def test_reject_displacement_failures_and_bad_faces(self):
        self.audit['attachment_guard_frames'] = [1]
        with self.assertRaises(ValueError):
            MODULE['_motion_seed_pairs'](self.audit, 5)
        self.audit['attachment_guard_frames'] = []
        for pair in [[0, 5], [-1, 2], [1, 1], [1.0, 2], [True, 2]]:
            self.audit['frames'][0]['self_triangle_pairs'] = [pair]
            with self.assertRaises(ValueError):
                MODULE['_motion_seed_pairs'](self.audit, 5)


class StaticProbeTests(unittest.TestCase):
    def setUp(self):
        self.original = bpy.context.window.scene
        self.scene = bpy.data.scenes.new('WW_WaistProof_UnitTest')
        self.base = {'vertices': [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
                     'normals': [[0, 0, 1]] * 3, 'indices': [0, 1, 2]}
        self.obj = MODULE['_static_finish_object'](self.scene, 'WW_ProbeTest', self.base, self.base['vertices'], {})
        bpy.context.window.scene = self.scene

    def tearDown(self):
        bpy.context.window.scene = self.original
        mesh = self.obj.data
        bpy.data.objects.remove(self.obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
        bpy.data.scenes.remove(self.scene)

    def test_fresh_scene_and_repeated_updates_without_timeline_evaluation(self):
        keys = self.obj.data.shape_keys
        self.assertIsNone(keys.animation_data)
        self.assertEqual(len(keys.key_blocks), 2)
        key = keys.key_blocks['Pose_1']
        self.assertEqual(key.value, 1.0)
        for delta in [0.25, -0.1, 0.0]:
            points = [(x + delta, -z, y) for x, y, z in self.base['vertices']]
            key.data.foreach_set('co', [c for p in points for c in p])
            keys.update_tag()
            self.obj.data.update()
            self.obj.update_tag()
            bpy.context.view_layer.update()
            mesh = self.obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data
            for actual, expected in zip(mesh.vertices, points):
                for coordinate, value in zip(actual.co, expected):
                    self.assertAlmostEqual(coordinate, value, places=6)

    def test_finish_rejects_unbounded_settings(self):
        for factor, iterations in [(float('nan'), 3), (0.51, 3), (0.25, 7), (0.25, 2.5)]:
            with self.assertRaises(ValueError):
                MODULE['_finish_modifier'](self.obj, {}, factor, iterations)

    def test_finish_rejects_invalid_weights(self):
        for weights in [{-1: 1.0}, {3: 1.0}, {0: float('nan')}, {0: 1.1}, {'1.0': 1.0}]:
            with self.assertRaises(ValueError):
                MODULE['_finish_modifier'](self.obj, weights)


def run():
    suite = unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromTestCase(cls)
                               for cls in [MotionSeedTests, StaticProbeTests])
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    if not result.wasSuccessful():
        raise AssertionError('Waist attachment regressions failed')
    return {'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors)}
