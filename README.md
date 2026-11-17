# cachyos-gnome-bazzite-dx

Bazzite (GNOME) with CachyOS kernel and settings.

Two final variants derive from **one Bazzite Deck GNOME base** and **one shared CachyOS + DX build**, produced on one runner. The small desktop/handheld differences are applied only after the shared image is complete:

| Variant | Image | Base | Use |
|---|---|---|---|
| `dx` | `ghcr.io/darkphilosophy/cachyos-gnome-bazzite-dx` | Shared CachyOS Deck+DX base | GNOME desktop, without Deck autologin/Game Mode |
| `deck` | `ghcr.io/darkphilosophy/cachyos-gnome-bazzite-deck` | Shared CachyOS Deck+DX base | Steam Game Mode, handheld components, and DX toolchain |

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

Customize expensive shared operations in `build_files/build.sh`, and small product differences
in `build_files/flavor.sh`. `Containerfile.common` builds CachyOS, initramfs and DX packages
**once** from `ghcr.io/ublue-os/bazzite-deck-gnome:stable`; `Containerfile` then produces
the two product images from that identical local intermediate image. No shared stage is
published. Changes to `flavor.sh` do not invalidate the common stage's cache.

A push to `main` rebuilds both variants as one atomic CI unit; scheduled runs (Monday
04:17 UTC) rebuild both if either is missing, its fingerprint differs, or either is
14 days old. Failed builds do not advance `latest`. Signed images are promoted only after
both final images have been built and signed.

Locally use `just build-all` to build both products from the same common stage.
`just build` builds one selected flavor (default DX) and reuses cached common layers.
The output images use the existing GHCR package names. Bazzite upstream DX uses a Deck
base and selectively turns off Deck-specific sessions for the DX desktop. Our common
base keeps Deck intact; DX-only changes are applied in `flavor.sh`.

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

The source of truth for both output image names and their single upstream base is
`config/variants.json`. `python3 scripts/validate_builds.py` validates the two
image variants, their disk/ISO configurations and the GitHub Actions build inputs.
`python3 scripts/validate_builds.py --matrix --variant all --artifact all`
prints the disk build matrix.

For a local Deck-only build, set `IMAGE_NAME=cachyos-gnome-bazzite-deck`
and `TARGET_FLAVOR=deck` before calling `just build`. The common base
is always `ghcr.io/ublue-os/bazzite-deck-gnome:stable` for both flavors.
`just build-iso` uses `disk_config/iso.toml` and the `anaconda-iso` type.

**Validation:** the pull request checks both container flavors and disk configuration
in CI; installer boot, end-to-end disk builds and handheld hardware still require
separate runtime tests. CI build duration is measured from Actions logs, not assumed.
