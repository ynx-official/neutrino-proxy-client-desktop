"""Standalone desktop packaging must not depend on the Java repository."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import tomllib
import unittest
import zipfile
import release

REPO = Path(__file__).resolve().parents[2]


def build_records(output, version="0.1.1", commit="a" * 40):
    for platform in ("windows-x64", "macos-x64", "macos-arm64"):
        release.write_json(output / "build-info" / f"desktop-{platform}.json", {
            "version": version, "commit": commit, "platform": platform, "tools": {},
        })


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / "output"

    def test_versions_are_injected_at_repository_root_without_java(self):
        for name in ("package.json", "package-lock.json", "Cargo.lock", "src-tauri/Cargo.toml",
                     "src-tauri/tauri.conf.json", "crates/client-core/Cargo.toml"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO / name, target)
        release.prepare_versions(self.root, "0.1.1")
        for name in ("package.json", "package-lock.json", "src-tauri/tauri.conf.json"):
            self.assertEqual(json.loads((self.root / name).read_text())["version"], "0.1.1")
        self.assertEqual(json.loads((self.root / "package-lock.json").read_text())["packages"][""]["version"], "0.1.1")
        for package in tomllib.loads((self.root / "Cargo.lock").read_text())["package"]:
            if package["name"] in ("neutrino-client-core", "neutrino-proxy-client-desktop"):
                self.assertEqual(package["version"], "0.1.1")
        self.assertFalse((self.root / "pom.xml").exists())

    def test_tag_parser_rejects_paths_commands_and_invalid_versions(self):
        for tag in ("v0.1.1", "v0.2.0-rc.1"):
            self.assertEqual(release.parse_version(tag), tag[1:])
        for tag in ("0.1.1", "v1.02.3", "v1.2.3-01", "v65536.0.0", "v1.2.3/evil", "v1.2.3;bad"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.parse_version(tag)

    def test_windows_installer_and_portable_are_distinct_self_contained_assets(self):
        build = self.root / "target/x86_64-pc-windows-msvc/release"
        (build / "bundle/nsis").mkdir(parents=True)
        (build / "bundle/nsis/setup.exe").write_bytes(b"installer")
        (build / "neutrino-proxy-client-desktop.exe").write_bytes(b"application")
        (self.root / "LICENSE").write_text("MIT")
        release.package_desktop(self.root, self.output, "windows-x64", "x86_64-pc-windows-msvc", "0.1.1")
        prefix = "neutrino-proxy-client-desktop-0.1.1-windows-x64"
        self.assertEqual((self.output / f"{prefix}-setup.exe").read_bytes(), b"installer")
        with zipfile.ZipFile(self.output / f"{prefix}-portable.zip") as archive:
            self.assertEqual(set(archive.namelist()), {f"{prefix}/LICENSE", f"{prefix}/neutrino-proxy-client-desktop.exe"})
            self.assertEqual(archive.read(f"{prefix}/neutrino-proxy-client-desktop.exe"), b"application")

    def test_macos_architectures_are_packaged_separately(self):
        for platform, target in (("macos-x64", "x86_64-apple-darwin"), ("macos-arm64", "aarch64-apple-darwin")):
            directory = self.root / "target" / target / "release/bundle/dmg"
            directory.mkdir(parents=True)
            (directory / "Neutrino.dmg").write_bytes(platform.encode())
            release.package_desktop(self.root, self.output, platform, target, "0.1.1")
            self.assertEqual((self.output / f"neutrino-proxy-client-desktop-0.1.1-{platform}.dmg").read_bytes(), platform.encode())

    def test_missing_binary_and_duplicate_installers_stop_packaging(self):
        with self.assertRaises((FileNotFoundError, ValueError)):
            release.package_desktop(self.root, self.output, "windows-x64", "x86_64-pc-windows-msvc", "0.1.1")
        directory = self.root / "target/x86_64-pc-windows-msvc/release/bundle/nsis"
        directory.mkdir(parents=True)
        for name in ("one.exe", "two.exe"):
            (directory / name).write_bytes(b"installer")
        with self.assertRaises(ValueError):
            release.package_desktop(self.root, self.output, "windows-x64", "x86_64-pc-windows-msvc", "0.1.1")

    def test_manifest_requires_four_desktop_assets_and_matching_build_commits(self):
        self.output.mkdir()
        names = release.expected_assets("0.1.1")
        self.assertEqual(len(names), 4)
        self.assertTrue(all(name.startswith("neutrino-proxy-client-desktop-") for name in names))
        for name in names[:-1]:
            (self.output / name).write_bytes(b"package")
        with self.assertRaises(ValueError):
            release.assemble(self.output, "0.1.1", "a" * 40, "https://example.invalid/run")
        (self.output / names[-1]).write_bytes(b"package")
        with self.assertRaises((ValueError, FileNotFoundError)):
            release.assemble(self.output, "0.1.1", "a" * 40, "https://example.invalid/run")
        build_records(self.output, commit="b" * 40)
        with self.assertRaises(ValueError):
            release.assemble(self.output, "0.1.1", "a" * 40, "https://example.invalid/run")
        build_records(self.output)
        release.assemble(self.output, "0.1.1", "a" * 40, "https://example.invalid/run")
        manifest = json.loads((self.output / "release-manifest.json").read_text())
        self.assertEqual(len(manifest["assets"]), 4)
        self.assertNotIn("linux_compatibility", manifest)
        self.assertEqual(manifest["desktop_signing"], "unsigned-no-notarization")
        self.assertEqual(manifest["assets"][0]["sha256"], hashlib.sha256(b"package").hexdigest())
        (self.output / "unexpected.zip").write_bytes(b"unexpected")
        with self.assertRaises(ValueError):
            release.assemble(self.output, "0.1.1", "a" * 40, "https://example.invalid/run")


if __name__ == "__main__":
    unittest.main()
