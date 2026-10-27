"""Upload the complete verified build, then automatically make the release public."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request

from release import ROOT, expected_assets, parse_version


class GitHubAPI:
    """Use the job-scoped token only against GitHub's API/upload hosts."""

    def __init__(self, token):
        self.token = token

    def request(self, method, path, data=None, content_type="application/json"):
        url = path if path.startswith("https://") else "https://api.github.com" + path
        if urllib.parse.urlsplit(url).hostname not in ("api.github.com", "uploads.github.com"):
            raise ValueError("Unexpected GitHub API host")
        if data is not None and not isinstance(data, bytes):
            data = json.dumps(data).encode("utf-8")
        request = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": "Bearer " + self.token, "Accept": "application/vnd.github+json",
            "Content-Type": content_type, "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "neutrino-proxy-release",
        })
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                body = response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as error:
            if error.code == 404 and method == "GET" and "/releases/tags/" in path:
                return None
            raise RuntimeError(f"GitHub {method} failed with HTTP {error.code}: {error.read().decode()}") from error


def verify_files(output, version, commit):
    """Recheck file hashes immediately before any publication-side mutation."""
    names = set(expected_assets(version)) | {"release-manifest.json", "SHA256SUMS"}
    actual = {path.name for path in output.iterdir() if path.is_file()}
    if actual != names:
        raise ValueError("Unexpected or missing publication files")
    checksums = {}
    for line in (output / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        digest, name = line.split("  ", 1)
        if name in checksums or not re.fullmatch("[0-9a-f]{64}", digest):
            raise ValueError("Invalid checksum manifest")
        checksums[name] = digest
    if set(checksums) != names - {"SHA256SUMS"}:
        raise ValueError("Checksum manifest file list mismatch")
    for name, digest in checksums.items():
        if hashlib.sha256((output / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Checksum mismatch: {name}")
    manifest = json.loads((output / "release-manifest.json").read_text(encoding="utf-8"))
    if manifest["version"] != version or manifest["commit"] != commit:
        raise ValueError("Build version or commit does not match publication request")
    return sorted(names)


def find_release(api, base, tag):
    """The by-tag endpoint only guarantees published releases; list drafts separately."""
    release = api.request("GET", base + "/releases/tags/" + urllib.parse.quote(tag, safe=""))
    if release is not None:
        return release
    for page in range(1, 101):
        releases = api.request("GET", base + f"/releases?per_page=100&page={page}")
        matches = [item for item in releases if item["tag_name"] == tag]
        if len(matches) > 1:
            raise ValueError("Multiple drafts found for the same tag")
        if matches:
            return matches[0]
        if len(releases) < 100:
            return None
    raise ValueError("Release listing exceeded pagination limit")


def publish(repository, tag, commit, output, api):
    """Keep uploads private until every expected asset is present and verified."""
    version = parse_version(tag)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    names = verify_files(output, version, commit)
    base = f"/repos/{repository}"
    reference = api.request("GET", base + "/git/ref/tags/" + urllib.parse.quote(tag, safe=""))["object"]
    for _ in range(10):
        if reference["type"] == "commit":
            break
        if reference["type"] != "tag":
            raise ValueError("Release tag does not refer to a commit")
        reference = api.request("GET", base + "/git/tags/" + reference["sha"])["object"]
    if reference["type"] != "commit" or reference["sha"] != commit:
        raise ValueError("Remote tag commit changed after build preparation")
    prerelease = "-" in version
    marker = f"<!-- neutrino-release:{commit} -->"
    body = (f"{marker}\nRelease {tag} · commit `{commit}`\n\n"
            "Windows x64 installer and portable app, Intel and Apple Silicon macOS DMGs.\n\n"
            "Windows apps are unsigned; macOS uses ad-hoc signing without notarization. "
            "The Windows portable app requires WebView2.\n\n"
            "Verify downloads using `SHA256SUMS`; build provenance and tool versions are in `release-manifest.json`.\n")
    manifest = json.loads((output / "release-manifest.json").read_text(encoding="utf-8"))
    if manifest.get("tests_skipped") is True:
        body += "\nRegression and browser tests were skipped for this release at the user's request. "
        body += "Builds, formatting, Clippy, asset completeness and SHA-256 verification remain mandatory.\n"
    release = find_release(api, base, tag)
    if release is not None:
        if not release["draft"]:
            raise ValueError(f"Release {tag} is already published; use a new tag")
        if marker not in release.get("body", "") or release.get("target_commitish") != commit:
            raise ValueError("Existing draft was not created by this build; refusing to modify it")
    else:
        release = api.request("POST", base + "/releases", {
            "tag_name": tag, "target_commitish": commit, "name": tag,
            "body": body, "draft": True, "prerelease": prerelease,
        })
    release_path = base + f'/releases/{release["id"]}'
    remote = api.request("GET", release_path + "/assets?per_page=100")
    if len(remote) >= 100 or {asset["name"] for asset in remote} - set(names):
        raise ValueError("Existing draft contains unexpected assets")
    existing = {asset["name"]: asset for asset in remote}
    upload_url = release["upload_url"].split("{")[0]
    for name in names:
        content = (output / name).read_bytes()
        digest = "sha256:" + hashlib.sha256(content).hexdigest()
        old = existing.get(name)
        if old and old.get("digest") == digest and old["size"] == len(content):
            continue
        if old:
            # Only this workflow's still-private draft may replace an interrupted build asset.
            api.request("DELETE", base + f'/releases/assets/{old["id"]}')
        asset = api.request("POST", upload_url + "?" + urllib.parse.urlencode({"name": name}),
                            content, "application/octet-stream")
        if asset.get("digest") != digest or asset["size"] != len(content):
            raise ValueError(f"Uploaded asset checksum mismatch: {name}")
        print(f"Uploaded and verified {name}")
    result = api.request("PATCH", release_path, {
        "draft": False, "prerelease": prerelease, "make_latest": "false" if prerelease else "true", "body": body,
    })
    print("Published " + result["html_url"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "release-assets")
    args = parser.parse_args()
    publish(os.environ["GITHUB_REPOSITORY"], args.tag, args.commit, args.output, GitHubAPI(os.environ["GH_TOKEN"]))


if __name__ == "__main__":
    main()
