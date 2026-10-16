import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile


spec = importlib.util.spec_from_file_location(
    "release", Path(__file__).parents[1] / "release.py"
)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_tag_version_and_prerelease(self):
        self.assertEqual(release.parse_tag("v1.2.3"), ("1.2.3", False))
        self.assertEqual(release.parse_tag("v1.2.3-rc.1"), ("1.2.3", True))
        for tag in ("1.2.3", "vnext", "v01.2.3", "v1.2", "v1.2.3/evil",
                    "v1.2.3-rc.01", "v65536.0.0", "v1.2.3\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.parse_tag(tag)

    def test_build_number_must_fit_windows_version(self):
        for value in ("0", "-1", "65536", "not-a-number"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.metadata("v0.1.0", value)
        self.assertEqual(release.metadata("v0.1.0", "12")["build_number"], "12")

    def test_windows_bundle_keeps_runtime_plugins_and_assets(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, output = root / "bundle", root / "out"
            for name in release.WINDOWS_REQUIRED:
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fixture")
            (source / "extra_plugin.dll").write_bytes(b"plugin")
            (source / "debug.pdb").write_bytes(b"symbols")
            archive = release.package_windows(source, output, "v0.1.0")
            with zipfile.ZipFile(archive) as bundle:
                names = bundle.namelist()
                for name in release.WINDOWS_REQUIRED:
                    self.assertIn(f"Neutrino/{name}", names)
                self.assertIn("Neutrino/extra_plugin.dll", names)
                self.assertNotIn("Neutrino/debug.pdb", names)

    def test_missing_windows_runtime_prevents_packaging(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            root.joinpath("neutrino_proxy_client_desktop.exe").write_bytes(b"exe")
            with self.assertRaises(ValueError):
                release.package_windows(root, root / "out", "v0.1.0")

    def seed_artifacts(self, root):
        for name in release.expected_assets("v0.1.0"):
            (root / name).write_bytes(b"build-output")
        for platform in ("windows-x64", "macos-universal"):
            release.record(root, "v0.1.0", "a" * 40, "1", platform)

    def test_assembly_requires_complete_matching_verified_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.seed_artifacts(root)
            release.assemble(root, "v0.1.0", "a" * 40, "1")
            manifest = json.loads((root / "release-manifest.json").read_text())
            self.assertEqual(manifest["commit"], "a" * 40)
            self.assertEqual(len(manifest["assets"]), 3)
            checksum = hashlib.sha256(b"build-output").hexdigest()
            self.assertEqual((root / "SHA256SUMS").read_text().count(checksum), 3)

    def test_missing_tampered_or_mixed_commit_outputs_are_rejected(self):
        for failure in ("missing", "tampered", "wrong-commit", "extra"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                self.seed_artifacts(root)
                path = root / release.expected_assets("v0.1.0")[0]
                if failure == "missing":
                    path.unlink()
                elif failure == "tampered":
                    path.write_bytes(b"tampered")
                elif failure == "extra":
                    (root / "old-release.zip").write_bytes(b"old")
                else:
                    release.record(root, "v0.1.0", "b" * 40, "1", "windows-x64")
                with self.assertRaises(ValueError):
                    release.assemble(root, "v0.1.0", "a" * 40, "1")


if __name__ == "__main__":
    unittest.main()
