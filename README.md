# cachyos-gnome-bazzite-dx

Bazzite (GNOME) with CachyOS kernel and settings.

Two variants are built from the same recipe, in parallel:

| Variant | Image | Base | Use |
|---|---|---|---|
| `dx` | `ghcr.io/darkphilosophy/cachyos-gnome-bazzite-dx` | [bazzite-dx-gnome](https://github.com/ublue-os/bazzite) | desktop |
| `deck` | `ghcr.io/darkphilosophy/cachyos-gnome-bazzite-deck` | [bazzite-deck-gnome](https://github.com/ublue-os/bazzite) | handhelds / Game Mode, with the DX toolchain |

Modifications:
- Replaced kernel with [CachyOS Kernel](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/)
- [CachyOS settings + ksmd](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/)
- Removed steam in favour of flatpak steam (`dx` only: the `deck` image keeps the base's
  Steam client because Game Mode launches it)
- Removed tailscale (replaced by NetBird) and lutris; `dx` also drops fw-fanctrl, which the
  `deck` image keeps for its fan curves
- Added the [bazzite-dx](https://github.com/ublue-os/bazzite-dx) developer toolchain to the
  `deck` image too (dev tools, ROCm, virtualization, VS Code and Docker), without the
  upstream changes that disable the deck session and Game Mode

Derived from [sihawken/cachyos-kernel-bazzite-dx](https://github.com/sihawken/cachyos-kernel-bazzite-dx) (Apache-2.0).

# Install

Pick the variant that matches the machine: `dx` for a desktop, `deck` for a handheld or
anything that boots into Game Mode. From any atomic Fedora (Silverblue, Kinoite, Bazzite, ...):

```
VARIANT=dx # or: deck
IMAGE=ghcr.io/darkphilosophy/cachyos-gnome-bazzite-${VARIANT}
rpm-ostree rebase ostree-unverified-registry:${IMAGE}:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://${IMAGE}:latest
systemctl reboot
```

Customize by editing `build_files/build.sh`; per-variant steps there read `TARGET_FLAVOR`.
Every push to `main` rebuilds both variants in parallel. The weekly scheduled run (Monday
04:17 UTC) skips a variant whose base image and CachyOS packages are unchanged, but always
rebuilds it once its published image is 14 days old.

## Build installer ISO and QCOW2 images

The repository builds two `x86_64` images. Choose **Actions → Build disk images → Run workflow**
on `main` **after** the container packages have been published. Select `dx`, `deck`, or
`all`, and `qcow2`, `anaconda-iso`, or `all`. The workflow checks the container tag
exists before building, produces SHA256 checksums, and uploads separately named artifacts
for seven days. S3 upload is optional and requires the repository's S3 secrets.

A pull request only validates the disk build matrix and configuration: it does **not**
build an ISO from an unpublished `latest` image. To test new changes without merging,
publish a test image to GHCR separately and dispatch the workflow with its tag once it
is available; remember the workflow uses the official image names.

These are **Anaconda installer ISOs**, not Bazzite's custom Live desktop ISOs. The ISO
build must still be checked in a VM: boot into Anaconda, verify installation targets
the selected DX or Deck container, complete the install, and verify first boot.
For Deck, test Steam Game Mode, hhd controls and fan/handheld modules on actual hardware.
Passing the container build does not prove those runtime features work.

The source of truth for both image names and upstream bases is
`config/variants.json`. `python3 scripts/validate_builds.py` validates the two
image variants, their disk/ISO configurations and the GitHub Actions build inputs.
`python3 scripts/validate_builds.py --matrix --variant all --artifact all`
prints the disk build matrix.

For local builds, `just build` defaults to DX. For Deck set both
`IMAGE_NAME=cachyos-gnome-bazzite-deck`,
`TARGET_FLAVOR=deck` and
`BASE_IMAGE=ghcr.io/ublue-os/bazzite-deck-gnome:stable`.
`just build-iso` uses `disk_config/iso.toml` and the `anaconda-iso` type.
