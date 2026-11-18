#!/usr/bin/env bash
set -euo pipefail

# Deliberately small final delta. The expensive kernel, dracut and developer
# toolchain were already installed ONCE in Containerfile.common.
case "${TARGET_FLAVOR:-}" in
    deck)
        echo "Deck + DX: preserve Steam, SDDM autologin, Game Mode and handheld services"
        # All packages and services are inherited from Bazzite Deck GNOME.
        test -d /usr/share/gamescope-session-plus || {
            echo "Deck base lost gamescope-session-plus" >&2; exit 1;
        }
        ;;
    dx)
        echo "Desktop DX: disable Deck autologin/session and enable GNOME GDM"
        # These changes mirror the Deck->desktop logic in upstream Bazzite DX.
        # Never put them in build.sh: Deck must inherit these features intact.
        for file in /etc/sddm.conf.d/steamos.conf \
                    /etc/sddm.conf.d/virtualkbd.conf \
                    /etc/sddm.conf.d/zz-steamos-autologin.conf; do
            rm -f "$file"
        done
        rm -f /usr/share/gamescope-session-plus/bootstrap_steam.tar.gz
        # Remove only packages present; same semantics as previous DX build.
        for package in steam steamos-manager-powerstation sddm; do
            if rpm -q "$package" >/dev/null 2>&1; then dnf5 -y remove "$package"; fi
        done
        # Restore the desktop display manager and tuned, as upstream DX does.
        systemctl enable gdm.service
        systemctl mask powerstation.service || true
        if systemctl list-unit-files tuned.service --no-legend | grep -q tuned.service; then
            systemctl enable tuned.service
        fi
        if systemctl list-unit-files tuned-ppd.service --no-legend | grep -q tuned-ppd.service; then
            systemctl enable tuned-ppd.service
        fi
        ;;
    *)
        echo "Unknown TARGET_FLAVOR='${TARGET_FLAVOR:-}' (expected dx or deck)" >&2
        exit 1
        ;;
esac

dnf5 -y clean all
