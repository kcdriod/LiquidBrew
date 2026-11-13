import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[2] / "scripts/release_version.py"
spec = importlib.util.spec_from_file_location("release_version", MODULE)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseVersionTests(unittest.TestCase):
    def test_initial_and_next_patch(self):
        self.assertEqual(release.choose_version([]), "v1.0.0")
        self.assertEqual(release.choose_version(["v1.0.0"]), "v1.0.1")

    def test_numeric_order_and_prereleases(self):
        self.assertEqual(release.choose_version(["v1.9.9", "v1.10.2", "v2.0.0-beta.1", "other"]), "v1.10.3")

    def test_explicit_major_or_minor(self):
        self.assertEqual(release.choose_version(["v1.0.0"], "1.1.0"), "v1.1.0")
        self.assertEqual(release.choose_version(["v1.0.0"], "2.0.0"), "v2.0.0")

    def test_invalid_or_already_used_version(self):
        for value in ["v2.0.0", "01.0.0", "1.0", "1.0.0-beta", "1.0.0", "0.9.0", "anything; echo bad"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.choose_version(["v1.0.0"], value)

    def test_rerun_reuses_its_tag_even_after_newer_releases(self):
        self.assertEqual(release.choose_version(["v1.0.0", "v1.0.1", "v1.0.2"], commit_tags=["v1.0.1"]), "v1.0.1")
        self.assertEqual(release.choose_version(["v1.1.0"], "1.1.0", ["v1.1.0"]), "v1.1.0")
        with self.assertRaises(ValueError):
            release.choose_version(["v1.1.0"], "2.0.0", ["v1.1.0"])


if __name__ == "__main__":
    unittest.main()
