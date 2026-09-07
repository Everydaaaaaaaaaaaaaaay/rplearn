import tempfile
import unittest
from pathlib import Path

from scene_preview_guard import require_preview


class ScenePreviewGuardTests(unittest.TestCase):
    def test_requires_explicit_diagnostic_intent(self):
        with self.assertRaises(ValueError):
            require_preview("/tmp/scene-preview", False)

    def test_allows_separate_preview(self):
        with tempfile.TemporaryDirectory() as root:
            destination = Path(root) / "preview"
            self.assertEqual(require_preview(str(destination), True), destination.resolve())

    def test_rejects_resources_and_descendants(self):
        for suffix in ["App/Resources", "App/Resources/ActivityScene", "App/Resources/ActivityScene/video.mp4"]:
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                require_preview(str(Path.cwd() / suffix), True)

    def test_resolves_symlink_destination(self):
        with tempfile.TemporaryDirectory() as root:
            resources = Path(root) / "App" / "Resources"
            resources.mkdir(parents=True)
            alias = Path(root) / "preview"
            alias.symlink_to(resources, target_is_directory=True)
            with self.assertRaises(ValueError):
                require_preview(str(alias / "ActivityScene"), True)

    def test_normalizes_parent_segments(self):
        with self.assertRaises(ValueError):
            require_preview("App/Other/../Resources/ActivityScene", True)


if __name__ == "__main__":
    unittest.main()
