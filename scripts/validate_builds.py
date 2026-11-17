#!/usr/bin/env python3
"""Validate the two Bazzite variants and plan disk/ISO builds without extra deps."""

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = ROOT / "config/variants.json"
DISK_CONFIG = ROOT / "disk_config/disk.toml"
ISO_CONFIG = ROOT / "disk_config/iso.toml"
BUILD_WORKFLOW = ROOT / ".github/workflows/build.yml"
DISK_WORKFLOW = ROOT / ".github/workflows/build-disk.yml"


def validate():
    variants = json.loads(VARIANTS.read_text())
    assert isinstance(variants, list) and len(variants) == 2, "Exactly dx and deck variants required"
    assert {v["flavor"] for v in variants} == {"dx", "deck"}, "Unexpected variant flavors"
    assert len({v["image"] for v in variants}) == 2, "Variants must have distinct GHCR packages"
    for v in variants:
        assert set(v) == {"flavor", "image", "base", "desc"}, "Variant schema changed"
        assert re.fullmatch(r"[a-z0-9][a-z0-9-]*", v["image"]), "Invalid image package name"
        assert v["base"].startswith("ghcr.io/ublue-os/bazzite-"), "Unexpected base image"
    bases = {v["base"] for v in variants}
    assert bases == {"ghcr.io/ublue-os/bazzite-deck-gnome:stable"}, "DX and Deck must share the SAME upstream base"
    common = (ROOT / "Containerfile.common").read_text()
    final = (ROOT / "Containerfile").read_text()
    shared_build = (ROOT / "build_files/build.sh").read_text()
    flavor_build = (ROOT / "build_files/flavor.sh").read_text()
    assert "BASE_IMAGE" in common and "/ctx/build.sh" in common, "Missing shared build stage"
    assert "COMMON_IMAGE" in final and "/ctx/flavor.sh" in final, "Missing thin flavor stage"
    assert "dnf5 -y install kernel-cachyos" in shared_build, "CachyOS kernel must be built in shared stage"
    assert re.search(r"(?m)^\s*(?:/usr/bin/)?dracut\b", shared_build), "Shared stage must regenerate initramfs"
    assert not re.search(r"(?m)^\s*(?:/usr/bin/)?dracut\b", flavor_build), "Only common stage may regenerate initramfs"
    assert "COPY build_files /" not in common and "COPY build_files /" not in final, "Flavor changes must not invalidate common cache"
    assert "TARGET_FLAVOR" not in shared_build, "Shared stage must be flavor-agnostic"
    assert "TARGET_FLAVOR" in flavor_build and "deck)" in flavor_build and "dx)" in flavor_build
    assert "Containerfile.common" in BUILD_WORKFLOW.read_text(), "CI must build shared stage"
    assert "matrix.variant" not in BUILD_WORKFLOW.read_text(), "CI must not build variants in separate runners"
    for config in (DISK_CONFIG, ISO_CONFIG):
        assert config.is_file(), f"Missing builder config: {config}"
        parsed = tomllib.loads(config.read_text())
        assert "customizations" in parsed, f"Empty config: {config}"
    iso = tomllib.loads(ISO_CONFIG.read_text())
    kickstart = iso.get("customizations", {}).get("installer", {}).get("kickstart", {}).get("contents", "")
    assert "image-template" not in kickstart and "bootc switch" not in kickstart, "ISO points at wrong payload"
    build = BUILD_WORKFLOW.read_text()
    disk = DISK_WORKFLOW.read_text()
    assert "config/variants.json" in build and "config/variants.json" in disk, "Workflows must share variants.json"
    assert "matrix.target.config" in disk, "Disk workflow must use matrix-selected config"
    assert "'./disk_config/" not in disk, "Invalid GitHub path filter prefix"
    assert 'image-template' not in (ROOT / "Justfile").read_text(), "Stale Justfile image name"
    return variants


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", action="store_true", help="Print GitHub Actions build matrix JSON")
    parser.add_argument("--variant", choices=("all", "dx", "deck"), default="all")
    parser.add_argument("--artifact", choices=("all", "qcow2", "anaconda-iso"), default="all")
    parser.add_argument("--tag", default="latest")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", args.tag):
        parser.error("Invalid OCI image tag")
    variants = validate()
    result = [
        {"flavor": v["flavor"], "image": v["image"], "type": image_type,
         "config": "disk_config/iso.toml" if image_type == "anaconda-iso" else "disk_config/disk.toml"}
        for v in variants if args.variant in ("all", v["flavor"])
        for image_type in ("qcow2", "anaconda-iso") if args.artifact in ("all", image_type)
    ]
    assert result, "No build selected"
    if args.matrix:
        print(json.dumps(result, separators=(",", ":")))
    else:
        print(f"Validated {len(variants)} variants and both disk/ISO configs; {len(result)} build target(s)")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, ValueError, OSError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
