import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from generate_restore_source import generate


class ReStoreReleaseTests(unittest.TestCase):
    def test_metadata_uses_requested_repository_tag_and_actual_ipa_name(self):
        path = Path(__file__).with_name("generate_source_metadata.py")
        spec = importlib.util.spec_from_file_location("metadata", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ipa = root / "ReStore custom.ipa"
            ipa.write_bytes(b"test build")
            arguments = [str(path), "--repo-root", str(root), "--ipa", str(ipa),
                         "--output-dir", str(root), "--release-notes-dir", str(root),
                         "--release-tag", "test/tag", "--marketing-version", "0.7.0",
                         "--short-commit", "1234567", "--release-channel", "nightly",
                         "--bundle-id", "com.ReStore.ReStore", "--repository", "owner/fork"]
            def command(command, cwd):
                (root / "release-notes.md").write_text("Changes", encoding="utf-8")
                return ""
            with patch.object(sys, "argv", arguments), patch.object(module, "sh", command):
                module.main()
            metadata_path = root / "source_metadata.json"
            metadata = json.loads(metadata_path.read_text())
            self.assertEqual(metadata["download_url"], "https://github.com/owner/fork/releases/download/test%2Ftag/ReStore%20custom.ipa")
            self.assertEqual(metadata["size"], 10)
            self.assertEqual(metadata["sha256"], hashlib.sha256(b"test build").hexdigest())
            output = root / "release/source.json"
            generate(metadata_path, output)
            source = json.loads(output.read_text())
            app = source["apps"][0]
            self.assertEqual(app["name"], "ReStore")
            self.assertEqual(app["bundleIdentifier"], "com.ReStore.ReStore")
            self.assertEqual(app["downloadURL"], metadata["download_url"])
            self.assertEqual(app["releaseChannels"][0]["releases"][0]["sha256"], metadata["sha256"])
            # Required fallback fields let clients decode nightly-only feeds without beta preferences.
            for key in ("version", "versionDate", "downloadURL", "size", "developerName", "iconURL"):
                self.assertIn(key, app)


if __name__ == "__main__":
    unittest.main()
