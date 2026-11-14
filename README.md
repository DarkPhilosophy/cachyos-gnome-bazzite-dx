# cachyos-gnome-bazzite-dx

Bazzite-DX (GNOME) with CachyOS kernel and settings.

Base image: [bazzite-dx-gnome](https://github.com/ublue-os/bazzite)

Modifications:
- Replaced kernel with [CachyOS Kernel](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/)
- [CachyOS settings + ksmd](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/)
- Removed steam in favour of flatpak steam

Derived from [sihawken/cachyos-kernel-bazzite-dx](https://github.com/sihawken/cachyos-kernel-bazzite-dx) (Apache-2.0).

# Install

From any atomic Fedora (Silverblue, Kinoite, Bazzite, ...):

```
rpm-ostree rebase ostree-unverified-registry:ghcr.io/darkphilosophy/cachyos-gnome-bazzite-dx:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/darkphilosophy/cachyos-gnome-bazzite-dx:latest
systemctl reboot
```

Customize by editing `build_files/build.sh`; every push to `main` rebuilds the image (also daily at 10:05 UTC).
