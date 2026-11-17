"""Focused cache-state checks; run through Blender MCP without editing a scene."""

from pathlib import Path
import runpy
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class CacheGuardTests(unittest.TestCase):
    def setUp(self):
        module = runpy.run_path(str(Path(__file__).with_name('simulate_wearing_blender.py')))
        self.guard = module['_cache_state']
        self.cache = SimpleNamespace(is_outdated=False, is_frame_skip=False, is_baked=False)
        cloth = SimpleNamespace(modifiers=[SimpleNamespace(type='CLOTH', point_cache=self.cache)])
        self.fake_bpy = SimpleNamespace(data=SimpleNamespace(objects={'cloth': cloth}))
        self.scene = type('Scene', (dict,), {})()
        self.scene.update(cloth_object='cloth', last_simulated_frame=180)
        self.scene.frame_current = 180
        self.scene.frame_end = 180

    def check(self, end=False):
        with patch.dict(self.guard.__globals__, bpy=self.fake_bpy):
            return self.guard(self.scene, require_end=end)

    def test_complete(self):
        self.assertEqual(self.check(True)['last_sequential_frame'], 180)

    def test_outdated(self):
        self.cache.is_outdated = True
        with self.assertRaisesRegex(ValueError, 'outdated'):
            self.check(True)

    def test_skipped_frames(self):
        self.cache.is_frame_skip = True
        with self.assertRaisesRegex(ValueError, 'skipped'):
            self.check()

    def test_counter_without_final_timeline_is_not_complete(self):
        self.scene.frame_current = 1
        with self.assertRaisesRegex(ValueError, 'completed final'):
            self.check(True)

    def test_final_timeline_without_sequential_progress_is_not_complete(self):
        self.scene['last_simulated_frame'] = 102
        with self.assertRaisesRegex(ValueError, 'completed final'):
            self.check(True)

    def test_cached_intermediate_read(self):
        self.scene.frame_current = 102
        self.assertEqual(self.check()['frame'], 102)

    def test_restarted_counter_is_incomplete(self):
        self.scene['last_simulated_frame'] = 0
        with self.assertRaisesRegex(ValueError, 'completed final'):
            self.check(True)


def run():
    result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromTestCase(CacheGuardTests))
    if not result.wasSuccessful():
        raise AssertionError('Cache guard regression failed')
    return {'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors)}
