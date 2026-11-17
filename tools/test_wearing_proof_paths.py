import hashlib
from pathlib import Path
import tempfile
import unittest

from wearing_proof_paths import (
    checked_input, checked_output, portable_reference, project_file,
    rebind_inputs, scene_inputs,
)


class WearingProofPathsTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name) / 'active'
        (self.root / 'captures').mkdir(parents=True)
        self.source = self.root / 'captures/source.json'
        self.source.write_text('{"sample": 1}', encoding='utf-8')
        self.support = self.root / 'captures/support.json'
        self.support.write_text('{"cushion": 1}', encoding='utf-8')
        self.digest = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.support_digest = hashlib.sha256(self.support.read_bytes()).hexdigest()

    def test_project_paths(self):
        for ref in ['res://captures/source.json', 'captures/source.json', self.source]:
            with self.subTest(ref=ref):
                self.assertEqual(checked_input(self.root, ref, self.digest), self.source)
                self.assertEqual(portable_reference(self.root, ref), 'res://captures/source.json')

    def test_reject_external_and_uri(self):
        for ref in ['', 'https://example.com/source.json', 'user://source.json',
                    '../retired/source.json', 'res://../retired/source.json',
                    Path(self.folder.name) / 'retired/source.json']:
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                project_file(self.root, ref)

    def test_missing_or_changed_input(self):
        for ref, sha in [('captures/missing.json', self.digest),
                         (self.source, '0' * 64), (self.source, ''),
                         (self.source, 'x' * 64)]:
            with self.subTest(ref=ref, sha=sha), self.assertRaises(ValueError):
                checked_input(self.root, ref, sha)

    def test_output_confined(self):
        self.assertEqual(checked_output(self.root, self.source, 'native_2'),
                         self.root / 'captures/source_blender_native_2.json')
        for source, tag in [(self.source, '../escape'), (self.source, ''),
                            (self.root / 'scripts/body.json', 'native')]:
            with self.subTest(source=source, tag=tag), self.assertRaises(ValueError):
                checked_output(self.root, source, tag)

    def test_rebind_preserves_cached_geometry(self):
        scene = {'source': str(Path(self.folder.name) / 'retired/source.json'),
                 'source_sha256': self.digest, 'support_source': 'old/support.json',
                 'support_sha256': self.support_digest, 'last_simulated_frame': 180}
        with self.assertRaises(ValueError):
            scene_inputs(self.root, scene)
        rebind_inputs(self.root, scene, self.source, self.support)
        self.assertEqual(scene_inputs(self.root, scene), (self.source, self.support))
        self.assertEqual(scene['last_simulated_frame'], 180)
        self.assertTrue(scene['source'].startswith('res://'))

    def test_rebind_is_atomic(self):
        scene = {'source': 'old/source.json', 'source_sha256': self.digest,
                 'support_source': 'old/support.json', 'support_sha256': '0' * 64}
        before = scene.copy()
        with self.assertRaises(ValueError):
            rebind_inputs(self.root, scene, self.source, self.support)
        self.assertEqual(scene, before)
        with self.assertRaises(ValueError):
            rebind_inputs(self.root, scene, self.source)
        self.assertEqual(scene, before)

    def test_support_hash_checked_each_time(self):
        scene = {'source': 'res://captures/source.json', 'source_sha256': self.digest,
                 'support_source': 'res://captures/support.json', 'support_sha256': self.support_digest}
        self.support.write_text('changed', encoding='utf-8')
        with self.assertRaises(ValueError):
            scene_inputs(self.root, scene)

    def test_cannot_invent_support(self):
        scene = {'source': 'res://captures/source.json', 'source_sha256': self.digest}
        before = scene.copy()
        with self.assertRaises(ValueError):
            rebind_inputs(self.root, scene, self.source, self.support)
        self.assertEqual(scene, before)


if __name__ == '__main__':
    unittest.main()
