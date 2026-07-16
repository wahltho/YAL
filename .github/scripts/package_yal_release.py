#!/usr/bin/env python3
"""Build a GitHub full-install ZIP for YAL releases."""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path


PACKAGE_ROOT = "YAL"

PACKAGE_DIRS = (
    "64",
    "data",
    "liblinux",
)

PACKAGE_FILES = (
    "Checklists.md",
    "LICENSE",
    "README.md",
    "SASL-LICENSE.txt",
    "YAL Manual.pdf",
    "skunkcrafts_updater.cfg",
    "skunkcrafts_updater_beta.cfg",
    "version.txt",
)

SKIP_NAMES = {
    ".DS_Store",
    "__MACOSX",
    "__pycache__",
}

SKIP_SUFFIXES = (
    ".pyc",
    ".pyo",
    "~",
)


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="latin-1")


def extract_regex(path: Path, pattern: str, label: str) -> str:
    text = read_text(path)
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        fail(f"could not read {label} from {path}")
    return match.group(1).strip()


def read_cfg_value(path: Path, key: str) -> str:
    for line in read_text(path).splitlines():
        if "|" not in line:
            continue
        name, value = line.split("|", 1)
        if name == key:
            return value.strip()
    fail(f"could not read {key} from {path}")


def is_prerelease(version: str) -> bool:
    return bool(re.search(r"[A-Za-z]", version or ""))


def validate_versions(root: Path, channel: str, version: str) -> None:
    if channel == "stable" and is_prerelease(version):
        fail(f"stable release version must not be a prerelease: {version}")
    if channel == "beta" and not is_prerelease(version):
        fail(f"beta release version must be a prerelease: {version}")

    definitions_version = extract_regex(
        root / "data/modules/Custom Module/definitions.lua",
        r'P\.VERSION\s*=\s*"([^"]+)"',
        "definitions version",
    )
    version_ini = read_text(root / "data/modules/configuration/version.ini").strip()
    readme_version = extract_regex(
        root / "README.md",
        r"\*\*Version\s+([^*]+)\*\*",
        "README version",
    )

    expected = {
        "definitions.lua": definitions_version,
        "version.ini": version_ini,
        "README.md": readme_version,
    }
    for name, actual in expected.items():
        if actual != version:
            fail(f"{name} has version {actual}, expected {version}")

    stable_cfg_version = read_cfg_value(root / "skunkcrafts_updater.cfg", "version")
    beta_cfg_version = read_cfg_value(root / "skunkcrafts_updater_beta.cfg", "version")
    stable_cfg_name = read_cfg_value(root / "skunkcrafts_updater.cfg", "name")
    beta_cfg_name = read_cfg_value(root / "skunkcrafts_updater_beta.cfg", "name")

    if stable_cfg_name != "YAL":
        fail(f"skunkcrafts_updater.cfg name is {stable_cfg_name}, expected YAL")
    if beta_cfg_name != "YAL Beta":
        fail(f"skunkcrafts_updater_beta.cfg name is {beta_cfg_name}, expected YAL Beta")

    active_cfg_version = beta_cfg_version if channel == "beta" else stable_cfg_version
    active_cfg_name = "skunkcrafts_updater_beta.cfg" if channel == "beta" else "skunkcrafts_updater.cfg"
    if active_cfg_version != version:
        fail(f"{active_cfg_name} has version {active_cfg_version}, expected {version}")


def should_skip(path: Path) -> bool:
    if any(part in SKIP_NAMES for part in path.parts):
        return True
    return path.name.endswith(SKIP_SUFFIXES)


def collect_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for item in PACKAGE_FILES:
        path = root / item
        if not path.is_file():
            fail(f"required package file missing: {item}")
        files.append(path)

    for dirname in PACKAGE_DIRS:
        directory = root / dirname
        if not directory.is_dir():
            fail(f"required package directory missing: {dirname}")
        for path in directory.rglob("*"):
            if path.is_file() and not should_skip(path.relative_to(root)):
                files.append(path)

    return sorted(set(files), key=lambda p: p.relative_to(root).as_posix().lower())


def build_zip(root: Path, output_dir: Path, version: str) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    zip_path = output_dir / f"YAL-{version}.zip"
    manifest_path = output_dir / f"YAL-{version}-manifest.txt"
    package_files = collect_files(root)

    if zip_path.exists():
        zip_path.unlink()
    if manifest_path.exists():
        manifest_path.unlink()

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
        for path in package_files:
            rel = path.relative_to(root).as_posix()
            archive.write(path, f"{PACKAGE_ROOT}/{rel}")

    with manifest_path.open("w", encoding="utf-8", newline="\n") as manifest:
        manifest.write(f"YAL release package {version}\n")
        manifest.write(f"root={PACKAGE_ROOT}\n")
        manifest.write(f"file_count={len(package_files)}\n\n")
        for path in package_files:
            manifest.write(path.relative_to(root).as_posix() + "\n")

    return zip_path, manifest_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--channel", choices=("stable", "beta"), required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--root", default=".")
    parser.add_argument("--output-dir", default="dist")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    output_dir = Path(args.output_dir).resolve()
    validate_versions(root, args.channel, args.version)
    zip_path, manifest_path = build_zip(root, output_dir, args.version)

    print(f"zip={zip_path}")
    print(f"manifest={manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
