#!/bin/bash

set -euo pipefail

## Which image variant is being built. The Containerfile passes it as the TARGET_FLAVOR ARG:
##   dx   -> desktop image (Steam from Flatpak, no handheld fan control)
##   deck -> handheld / Game Mode image (keeps the base Steam client and fw-fanctrl)
FLAVOR="${TARGET_FLAVOR:-dx}"
case "${FLAVOR}" in
    dx | deck) ;;
    *)
        echo "Unknown TARGET_FLAVOR='${FLAVOR}', expected one of: dx deck" >&2
        exit 1
        ;;
esac
echo "Building image variant: ${FLAVOR}"

# Remove the given packages, skipping the ones this base image does not ship
remove_if_installed() {
    local p
    for p in "$@"; do
        if rpm -q "$p" > /dev/null 2>&1; then dnf5 -y remove "$p"; fi
    done
}

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

## DNF5 Speedup
sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf

# create a shims to bypass kernel install triggering dracut/rpm-ostree
# seems to be minimal impact, but allows progress on build
cd /usr/lib/kernel/install.d \
&& mv 05-rpmostree.install 05-rpmostree.install.bak \
&& mv 50-dracut.install 50-dracut.install.bak \
&& printf '%s\n' '#!/bin/sh' 'exit 0' > 05-rpmostree.install \
&& printf '%s\n' '#!/bin/sh' 'exit 0' > 50-dracut.install \
&& chmod +x  05-rpmostree.install 50-dracut.install

## Install CachyOS kernel
dnf5 -y copr enable bieszczaders/kernel-cachyos
dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra 
rm -rf /lib/modules/* # Remove kernel files that remain
dnf5 -y install kernel-cachyos kernel-cachyos-devel-matched --allowerasing

dnf5 -y copr enable bieszczaders/kernel-cachyos-addons

## Required to install CachyOS settings
rm -rf /usr/lib/systemd/coredump.conf

## Install KSMD and CachyOS-Settings
dnf5 -y install libcap-ng libcap-ng-devel procps-ng procps-ng-devel
# F45: systemd-oomd-defaults owns the same files as cachyos-settings
rpm -q systemd-oomd-defaults > /dev/null 2>&1 && rpm -e --nodeps systemd-oomd-defaults
dnf5 -y install cachyos-settings cachyos-ksm-settings --allowerasing

## Trust this image's own cosign signature (client verifies with ostree-image-signed)
install -Dm0644 /ctx/keys/cosign.pub /etc/pki/containers/darkphilosophy.pub
tee /etc/containers/registries.d/darkphilosophy.yaml > /dev/null <<EOF
docker:
  ghcr.io/darkphilosophy:
    use-sigstore-attachments: true
EOF
jq '.transports.docker["ghcr.io/darkphilosophy"] = [{"type":"sigstoreSigned","keyPaths":["/etc/pki/containers/darkphilosophy.pub"],"signedIdentity":{"type":"matchRepository"}}]' \
    /etc/containers/policy.json > /tmp/policy.json
install -m0644 /tmp/policy.json /etc/containers/policy.json

## Enable KSMD
tee "/usr/lib/systemd/system/ksmd.service" > /dev/null <<EOF
[Unit]
Description=Activates Kernel Samepage Merging
ConditionPathExists=/sys/kernel/mm/ksm

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ksmctl -e
ExecStop=/usr/bin/ksmctl -d

[Install]
WantedBy=multi-user.target
EOF

ln -s /usr/lib/systemd/system/ksmd.service /etc/systemd/system/multi-user.target.wants/ksmd.service

# restore kernel install
mv -f 05-rpmostree.install.bak 05-rpmostree.install \
&& mv -f 50-dracut.install.bak 50-dracut.install
cd -

# Regen initramfs
releasever=$(/usr/bin/rpm -E %fedora)
basearch=$(/usr/bin/arch)
# The kernel modules dir name is the installed kernel version; it must be the only one
KERNEL_VERSION=$(ls /usr/lib/modules)
[ "$(echo "$KERNEL_VERSION" | wc -l)" -eq 1 ] || { echo "Expected exactly one kernel in /usr/lib/modules, got: $KERNEL_VERSION" >&2; exit 1; }
# Ensure Initramfs is generated
depmod -a ${KERNEL_VERSION}
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "${KERNEL_VERSION}" --reproducible -v --add ostree -f "/lib/modules/${KERNEL_VERSION}/initramfs.img"
chmod 0600 "/lib/modules/${KERNEL_VERSION}/initramfs.img"

# tailscale is replaced by NetBird on every variant. Steam comes from Flatpak on the
# desktop image, but Bazzite-Deck launches the base's Steam client for Game Mode, so the
# deck variant keeps it.
remove_if_installed tailscale
[ "${FLAVOR}" = "deck" ] || remove_if_installed steam

## Packages that were layered with rpm-ostree on the host
# Repos (exact copies of the ones configured on the host)
cp /ctx/repos/*.repo /etc/yum.repos.d/
cp /ctx/gpg/* /etc/pki/rpm-gpg/

dnf5 -y install \
    caddy certbot crowdsec crowdsec-firewall-bouncer-nftables fail2ban nodejs \
    dovecot postfix opendkim opendkim-tools mailx \
    earlyoom irqbalance preload powertop kdump-utils kexec-tools seatd \
    udisks2-btrfs udisks2-iscsi udisks2-lvm2 \
    direnv gh google-cloud-cli himalaya meson mock neovim rpm-build \
    trash-cli xclip fuse-sshfs sshfs Sunshine \
    libgamemode.so.0 libgamemodeauto.so.0

# NetBird's %post runs `netbird service install/start`, which cannot work inside a build.
# Skip its scriptlets and ship the same unit the installer generates.
dnf5 -y install --setopt=tsflags=noscripts netbird netbird-ui
chmod 0600 /etc/sysconfig/netbird
install -Dm0644 /ctx/units/netbird.service /usr/lib/systemd/system/netbird.service
ln -sf /usr/lib/systemd/system/netbird.service /etc/systemd/system/multi-user.target.wants/netbird.service

## Dev toolchain and headers (previously only in distrobox containers)
dnf5 -y install \
    autoconf automake libtool cmake cargo clang clang-tools-extra lld llvm vala \
    glibc-static libstdc++-static libxcrypt-static check check-devel check-static \
    alsa-lib-devel appstream-devel at-spi2-atk-devel at-spi2-core-devel atk-devel \
    brotli-devel bzip2-devel cairo-devel cairo-gobject-devel clang-devel dbus-devel \
    fontconfig-devel freetype-devel fribidi-devel fuse3-devel gdk-pixbuf2-devel \
    gettext-devel glib2-devel glycin-devel gnome-desktop4-devel \
    gobject-introspection-devel graphene-devel graphite2-devel \
    gsettings-desktop-schemas-devel gstreamer1-devel \
    gtk3-devel gtk4-devel harfbuzz-devel iso-codes-devel javascriptcoregtk4.1-devel \
    javascriptcoregtk6.0-devel keyutils-libs-devel krb5-devel lcms2-devel \
    libX11-devel libXau-devel libXcomposite-devel libXcursor-devel libXdamage-devel \
    libXext-devel libXfixes-devel libXft-devel libXi-devel libXinerama-devel \
    libXrandr-devel libXrender-devel libXtst-devel libadwaita-devel libblkid-devel \
    libcloudproviders-devel libcom_err-devel libdatrie-devel libdrm-devel \
    libedit-devel libei-devel libepoxy-devel libffi-devel libglvnd-core-devel \
    libglvnd-devel libgudev-devel libicu-devel libinput-devel libmount-devel \
    libnghttp2-devel libogg-devel libomp-devel libpciaccess-devel libpsl-devel \
    libseccomp-devel libselinux-devel libsepol-devel libsoup3-devel libthai-devel \
    libverto-devel libxcb-devel libxdo-devel libxkbcommon-devel libxml2-devel \
    llvm-devel lzo-devel \
    ncurses-devel openssl-devel opus-devel orc-devel pango-devel pcre2-devel \
    pipewire-devel pixman-devel pulseaudio-libs-devel sqlite-devel subunit-devel \
    sysprof-capture-devel systemd-devel vulkan-headers vulkan-loader-devel \
    wayland-devel wayland-protocols-devel webkit2gtk4.1-devel webkitgtk6.0-devel \
    xdg-desktop-portal-devel xkeyboard-config-devel xorg-x11-proto-devel xz-devel

# GL/EGL/GBM headers: the base ships Terra's mesa and excludes Fedora's, so Fedora's
# -devel packages can be unsatisfiable. Best effort, visible in the log if skipped.
dnf5 -y install mesa-libGL-devel mesa-libEGL-devel mesa-libgbm-devel gstreamer1-plugins-base-devel \
    || echo "WARNING: GL/EGL/GBM/gstreamer-plugins-base headers not installed (mesa provider conflict)"

# Packages removed from the base on the host. fw-fanctrl drives handheld/laptop fan
# curves, so the deck variant keeps it.
remove_if_installed lutris
[ "${FLAVOR}" = "deck" ] || remove_if_installed fw-fanctrl

## The deck base is a gaming image: it does not carry the DX (developer experience) layer
## that bazzite-dx-gnome ships. Install that layer on deck so this is a deck+DX image.
## Only the package and repo blocks of bazzite-dx's 20-install-apps.sh are copied here:
## its SDDM/Game Mode, autologin, tuned/powerstation and dx-groups changes are meant to
## *undo* the deck session and would break the handheld experience we keep above.
if [ "${FLAVOR}" = "deck" ]; then
    dnf5 -y install \
        android-tools \
        bcc \
        bpftop \
        bpftrace \
        ccache \
        flatpak-builder \
        git-subtree \
        google-noto-sans-fonts \
        nicstat \
        numactl \
        podman-machine \
        podman-tui \
        python3-ramalama \
        restic \
        rclone \
        sysprof \
        tiptop \
        usbmuxd \
        waypipe \
        zsh

    dnf5 --setopt=install_weak_deps=False -y install \
        rocm-hip \
        rocm-opencl \
        rocm-clinfo \
        rocm-smi \
        qemu \
        libvirt \
        qemu-kvm \
        virt-manager \
        edk2-ovmf \
        guestfs-tools

    # Prefer the ROCm OpenCL ICD over Mesa's
    remove_if_installed mesa-libOpenCL

    # config-manager comes from dnf5-plugins; the deck base may not carry it
    dnf5 -y install dnf5-plugins

    # Both repos are added disabled upstream and enabled only for these installs
    dnf5 config-manager addrepo --from-repofile="https://packages.microsoft.com/yumrepos/vscode/config.repo"
    dnf5 config-manager setopt vscode-yum.enabled=0
    dnf5 -y install --enable-repo=vscode-yum code

    dnf5 config-manager addrepo --from-repofile="https://download.docker.com/linux/fedora/docker-ce.repo"
    dnf5 config-manager setopt docker-ce-stable.enabled=0
    dnf5 -y install --enable-repo=docker-ce-stable \
        containerd.io \
        docker-buildx-plugin \
        docker-ce \
        docker-ce-cli \
        docker-compose-plugin

    systemctl enable docker.socket
    systemctl enable podman.socket

    # Docker-in-Docker, as in bazzite-dx
    mkdir -p /etc/modules-load.d
    printf 'iptable_nat\n' >> /etc/modules-load.d/ip_tables.conf
fi

## CLEAN UP
# Clean up dnf cache to reduce image size
dnf5 -y clean all