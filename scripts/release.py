"""Validate release versions and assemble complete, checksummed desktop bundles."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile


PREFIX = "neutrino-proxy-client-desktop"
WINDOWS_REQUIRED = (
    "neutrino_proxy_client_desktop.exe",
    "neutrino_proxy_host.exe",
    "neutrino_worker.exe",
    "THIRD-PARTY-NOTICES.txt",
    "flutter_windows.dll",
    "msvcp140.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "window_manager_plugin.dll",
    "data/icudtl.dat",
    "data/app.so",
    "data/flutter_assets/AssetManifest.bin",
    "data/flutter_assets/assets/logo.png",
    "data/flutter_assets/assets/tray.ico",
    "data/flutter_assets/assets/test.jks",
)


def parse_tag(tag):
    number = r"(?:0|[1-9][0-9]*)"
    match = re.fullmatch(
        rf"v({number}\.{number}\.{number})(?:-(alpha|beta|rc)\.({number}))?", tag
    )
    if not match or any(int(n) > 65535 for n in match[1].split(".")):
        raise ValueError("Tag must be vX.Y.Z or vX.Y.Z-{alpha,beta,rc}.N; components <= 65535")
    return match[1], match[2] is not None


def metadata(tag, build_number):
    version, prerelease = parse_tag(tag)
    if not str(build_number).isdigit() or not 1 <= int(build_number) <= 65535:
        raise ValueError("Build number must be 1..65535")
    return {"tag": tag, "version": version, "build_number": str(build_number),
            "prerelease": str(prerelease).lower()}


def expected_assets(tag, platform=None):
    parse_tag(tag)
    assets = {
        "windows-x64": [f"{PREFIX}-{tag}-windows-x64.zip",
                        f"{PREFIX}-{tag}-windows-x64-setup.exe"],
        "macos-universal": [f"{PREFIX}-{tag}-macos-universal.zip",
                            f"{PREFIX}-{tag}-macos-universal.dmg"],
    }
    return assets[platform] if platform else [name for group in assets.values() for name in group]


def validate_windows_bundle(source):
    for name in WINDOWS_REQUIRED:
        if not (source / name).is_file() or (source / name).stat().st_size == 0:
            raise ValueError(f"Missing or empty Windows runtime file: {name}")


def package_windows(source, output, tag):
    validate_windows_bundle(source)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / expected_assets(tag, "windows-x64")[0]
    if archive.resolve().is_relative_to(source.resolve()):
        raise ValueError("Archive output must be outside the runtime directory")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(source.rglob("*")):
            if path.is_file() and path.suffix.lower() not in (".pdb", ".ilk", ".exp", ".lib"):
                bundle.write(path, f"Neutrino/{path.relative_to(source).as_posix()}")
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise ValueError("Windows ZIP integrity check failed")
    return archive


def package_windows_installer(source, output, tag, build_number, compiler):
    details = metadata(tag, build_number)
    source, output = source.resolve(), output.resolve()
    validate_windows_bundle(source)
    if output.is_relative_to(source):
        raise ValueError("Installer output must be outside the runtime directory")
    if compiler is None or not compiler.is_file():
        raise ValueError("Inno Setup compiler is required; use scripts/package-windows.ps1")
    output.mkdir(parents=True, exist_ok=True)
    script = Path(__file__).resolve().parents[1] / 'packaging/windows/setup.iss'
    subprocess.run([
        str(compiler.resolve()), '/Qp', f'/DBundleDir={source}', f'/DOutputDir={output}',
        f'/DReleaseTag={tag}', f'/DAppVersion={details["version"]}',
        f'/DBuildNumber={details["build_number"]}', str(script),
    ], check=True)
    installer = output / expected_assets(tag, 'windows-x64')[1]
    with installer.open('rb') as binary:
        if binary.read(2) != b'MZ':
            raise ValueError('Installer is not a Windows executable')
    return installer


def asset_info(path):
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing or empty release asset: {path.name}")
    with path.open("rb") as source:
        checksum = hashlib.file_digest(source, "sha256").hexdigest()
    return {"name": path.name, "size": path.stat().st_size, "sha256": checksum}


def record(output, tag, commit, build_number, platform):
    details = metadata(tag, build_number)
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("A full Git commit SHA is required")
    details.update(commit=commit, platform=platform,
                   assets=[asset_info(output / name) for name in expected_assets(tag, platform)])
    (output / f"{platform}.json").write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")


def assemble(output, tag, commit, build_number):
    expected = metadata(tag, build_number) | {"commit": commit}
    actual_names = {p.name for p in output.iterdir() if p.suffix in (".zip", ".dmg", ".exe")}
    if actual_names != set(expected_assets(tag)):
        raise ValueError("Release requires exactly the Windows installer/ZIP and macOS ZIP/DMG for this tag")
    assets = []
    for platform in ("windows-x64", "macos-universal"):
        path = output / f"{platform}.json"
        if not path.is_file():
            raise ValueError(f"Missing build record: {platform}")
        record_data = json.loads(path.read_text(encoding="utf-8"))
        if any(record_data.get(key) != value for key, value in expected.items()):
            raise ValueError(f"Version, build number or commit mismatch: {platform}")
        current = [asset_info(output / name) for name in expected_assets(tag, platform)]
        if record_data.get("platform") != platform or current != record_data.get("assets"):
            raise ValueError(f"Artifact integrity mismatch: {platform}")
        assets.extend(current)
    manifest = expected | {"assets": assets}
    (output / "release-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS").write_text(
        "".join(f"{item['sha256']}  {item['name']}\n" for item in assets), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("metadata", "windows", "installer", "record", "assemble"))
    parser.add_argument("--tag", default="")
    parser.add_argument("--build-number", default="1")
    parser.add_argument("--commit")
    parser.add_argument("--platform", choices=("windows-x64", "macos-universal"))
    parser.add_argument("--source", type=Path, default=Path("build/windows/x64/runner/Release"))
    parser.add_argument("--output", type=Path, default=Path("release-assets"))
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--iscc", type=Path)
    args = parser.parse_args()
    tag = args.tag
    if not tag:
        # CI uses the checked-in base version; tag releases always pass an explicit tag.
        match = re.search(r"^version:\s*(\S+)", Path("pubspec.yaml").read_text(), re.MULTILINE)
        if not match:
            parser.error("pubspec.yaml has no version")
        tag = "v" + match[1].split("+")[0]
    try:
        details = metadata(tag, args.build_number)
        if args.command == "metadata":
            if args.github_output:
                with args.github_output.open("a", encoding="utf-8") as output:
                    output.write("".join(f"{key}={value}\n" for key, value in details.items()))
            print(json.dumps(details))
        elif args.command == "windows":
            print(package_windows(args.source, args.output, tag))
        elif args.command == "installer":
            print(package_windows_installer(args.source, args.output, tag, args.build_number, args.iscc))
        else:
            if not args.commit:
                parser.error("--commit is required")
            if args.command == "record":
                if not args.platform:
                    parser.error("--platform is required")
                record(args.output, tag, args.commit, args.build_number, args.platform)
            else:
                assemble(args.output, tag, args.commit, args.build_number)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
