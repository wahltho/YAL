#!/usr/bin/env python3
"""Regression tests for YAL GitHub release package metadata."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("package_yal_release.py")
SPEC = importlib.util.spec_from_file_location("package_yal_release", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load release packager from {SCRIPT_PATH}")
PACKAGER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGER)


class ReleasePackageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.root = Path(self.tempdir.name) / "repo"
        self.output = Path(self.tempdir.name) / "dist"
        self.root.mkdir()

        for relative in PACKAGER.PACKAGE_FILES:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f"fixture:{relative}\n".encode("ascii"))

        payloads = {
            "64/mac.xpl": b"mac plugin\n",
            "data/modules/configuration/configuration.ini": b"user config default\n",
            "data/modules/configuration/version.ini": b"4.8b1\n",
            "data/modules/configuration/wprefs.ini": b"window preferences default\n",
            "data/output/example.log": b"packaged output fixture\n",
            "liblinux/64/lin.xpl": b"linux plugin\n",
        }
        for relative, content in payloads.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)

        skipped = {
            "data/.DS_Store": b"ignored",
            "data/__pycache__/cache.pyc": b"ignored",
            "data/temporary~": b"ignored",
            "Documentation/internal.md": b"not part of release package",
            "tools/internal.py": b"not part of release package",
            ".git/config": b"not part of release package",
        }
        for relative, content in skipped.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)

    def build(self, channel: str = "beta", version: str = "4.8b1"):
        return PACKAGER.build_zip(self.root, self.output, channel, version)

    def test_json_manifest_exactly_describes_release_zip(self) -> None:
        zip_path, text_manifest_path, json_manifest_path = self.build()
        manifest = json.loads(json_manifest_path.read_text(encoding="utf-8"))

        self.assertEqual("wahltho.yal", manifest["packageId"])
        self.assertEqual("4.8b1", manifest["packageVersion"])
        self.assertEqual("v4.8b1", manifest["releaseTag"])
        self.assertEqual("beta", manifest["channel"])
        self.assertEqual("xPlaneInstallation", manifest["installScope"])
        self.assertEqual("Resources/plugins/YAL", manifest["targetPath"])
        self.assertEqual(["zibo-737ng", "levelup-737ng"], manifest["supportedProducts"])
        self.assertTrue(manifest["restartRequired"])
        self.assertEqual(list(PACKAGER.PROTECTED_PATHS), manifest["protectedPaths"])

        archive_metadata = manifest["archive"]
        self.assertEqual(zip_path.name, archive_metadata["fileName"])
        self.assertEqual("YAL", archive_metadata["rootPath"])
        self.assertEqual(zip_path.stat().st_size, archive_metadata["size"])
        self.assertEqual(hashlib.sha256(zip_path.read_bytes()).hexdigest(), archive_metadata["sha256"])

        expected_paths = [
            path.relative_to(self.root).as_posix()
            for path in PACKAGER.collect_files(self.root)
        ]
        actual_paths = [entry["path"] for entry in manifest["files"]]
        self.assertEqual(expected_paths, actual_paths)
        self.assertNotIn("data/.DS_Store", actual_paths)
        self.assertNotIn("data/__pycache__/cache.pyc", actual_paths)
        self.assertNotIn("data/temporary~", actual_paths)
        self.assertNotIn("Documentation/internal.md", actual_paths)
        self.assertNotIn("tools/internal.py", actual_paths)
        self.assertNotIn(".git/config", actual_paths)

        with zipfile.ZipFile(zip_path, "r") as archive:
            self.assertEqual(
                {f"YAL/{path}" for path in expected_paths},
                {info.filename for info in archive.infolist() if not info.is_dir()},
            )
            for entry in manifest["files"]:
                payload = archive.read(f"YAL/{entry['path']}")
                self.assertEqual(len(payload), entry["size"])
                self.assertEqual(hashlib.sha256(payload).hexdigest(), entry["sha256"])

        text_manifest = text_manifest_path.read_text(encoding="utf-8")
        self.assertIn(f"file_count={len(expected_paths)}\n", text_manifest)
        self.assertTrue(text_manifest.endswith(expected_paths[-1] + "\n"))

    def test_verifier_rejects_changed_file_hash(self) -> None:
        zip_path, _, json_manifest_path = self.build()
        manifest = json.loads(json_manifest_path.read_text(encoding="utf-8"))
        manifest["files"][0]["sha256"] = "0" * 64
        json_manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                PACKAGER.verify_release_package(zip_path, json_manifest_path, "beta", "4.8b1")

    def test_stable_channel_metadata(self) -> None:
        _, _, json_manifest_path = PACKAGER.build_zip(
            self.root,
            self.output / "stable",
            "stable",
            "4.7",
        )
        manifest = json.loads(json_manifest_path.read_text(encoding="utf-8"))

        self.assertEqual("4.7", manifest["packageVersion"])
        self.assertEqual("v4.7", manifest["releaseTag"])
        self.assertEqual("stable", manifest["channel"])


if __name__ == "__main__":
    unittest.main()
