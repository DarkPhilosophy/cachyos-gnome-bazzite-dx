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
