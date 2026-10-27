"""Release publication must never expose partial assets or overwrite a release."""

import hashlib
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from release import assemble, expected_assets
from publish import publish


class FakeAPI:
    def __init__(self, existing=None, fail_upload=False):
        self.existing = existing
        self.fail_upload = fail_upload
        self.calls = []
        self.tag_commit = "a" * 40

    def request(self, method, path, data=None, content_type="application/json"):
        self.calls.append((method, path, data))
        if method == "GET" and "/git/ref/" in path:
            return {"object": {"type": "commit", "sha": self.tag_commit}}
        if method == "GET" and "/releases/tags/" in path:
            return self.existing if self.existing and not self.existing["draft"] else None
        if method == "GET" and "/releases?per_page=100&page=" in path:
            return [self.existing] if self.existing else []
        if method == "POST" and path.endswith("/releases"):
            return {"id": 7, "draft": True, "upload_url": "https://uploads.github.com/repos/test/repo/releases/7/assets{?name,label}"}
        if method == "GET" and path.endswith("/assets?per_page=100"):
            return []
        if method == "POST" and path.startswith("https://uploads.github.com/"):
            if self.fail_upload:
                raise RuntimeError("fixture upload failure")
            return {"digest": "sha256:" + hashlib.sha256(data).hexdigest(), "size": len(data)}
        if method == "PATCH":
            return {"html_url": "https://github.com/test/repo/releases/tag/v2.1.0"}
        raise AssertionError((method, path))


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)
        for name in expected_assets("2.1.0"):
            (self.output / name).write_bytes(b"fixture package")
        from test_release import build_records
        build_records(self.output, version="2.1.0")
        assemble(self.output, "2.1.0", "a" * 40, "https://example.invalid/run")

    def test_success_automatically_publishes_stable_after_all_uploads(self):
        api = FakeAPI()
        publish("test/repo", "v2.1.0", "a" * 40, self.output, api)
        uploads = [call for call in api.calls if call[1].startswith("https://uploads.github.com/")]
        self.assertEqual(len(uploads), 6)
        self.assertEqual(api.calls[-1][0], "PATCH")
        self.assertFalse(api.calls[-1][2]["draft"])
        self.assertFalse(api.calls[-1][2]["prerelease"])

    def test_failed_upload_cannot_publish_partial_release(self):
        api = FakeAPI(fail_upload=True)
        with self.assertRaisesRegex(RuntimeError, "upload failure"):
            publish("test/repo", "v2.1.0", "a" * 40, self.output, api)
        self.assertFalse(any(call[0] == "PATCH" for call in api.calls))

    def test_published_release_is_never_modified(self):
        api = FakeAPI(existing={"id": 7, "draft": False})
        with self.assertRaisesRegex(ValueError, "already published"):
            publish("test/repo", "v2.1.0", "a" * 40, self.output, api)
        self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_interrupted_draft_is_found_via_release_listing_and_resumed(self):
        api = FakeAPI(existing={
            "id": 7, "draft": True, "tag_name": "v2.1.0", "target_commitish": "a" * 40,
            "body": '<!-- neutrino-release:' + 'a' * 40 + ' -->',
            "upload_url": "https://uploads.github.com/repos/test/repo/releases/7/assets{?name,label}",
        })
        publish("test/repo", "v2.1.0", "a" * 40, self.output, api)
        self.assertFalse(any(method == "POST" and path.endswith('/releases') for method, path, _ in api.calls))
        self.assertEqual(api.calls[-1][0], "PATCH")

    def test_tampered_asset_fails_before_any_remote_action(self):
        api = FakeAPI()
        (self.output / expected_assets("2.1.0")[0]).write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "Checksum"):
            publish("test/repo", "v2.1.0", "a" * 40, self.output, api)
        self.assertEqual(api.calls, [])

    def test_moved_tag_cannot_publish_artifacts_from_another_commit(self):
        api = FakeAPI()
        api.tag_commit = "b" * 40
        with self.assertRaisesRegex(ValueError, "commit"):
            publish("test/repo", "v2.1.0", "a" * 40, self.output, api)
        self.assertTrue(api.calls)
        self.assertFalse(any(call[0] != "GET" for call in api.calls))

    def test_prerelease_is_published_without_replacing_latest(self):
        from test_release import build_records
        output = self.output / "prerelease"
        output.mkdir()
        version = "2.1.0-rc.1"
        for name in expected_assets(version):
            (output / name).write_bytes(b"fixture package")
        build_records(output, version=version)
        assemble(output, version, "a" * 40, "https://example.invalid/run")
        api = FakeAPI()
        publish("test/repo", "v" + version, "a" * 40, output, api)
        self.assertTrue(api.calls[-1][2]["prerelease"])
        self.assertEqual(api.calls[-1][2]["make_latest"], "false")



if __name__ == "__main__":
    unittest.main()
