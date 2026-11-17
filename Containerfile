# Base image this build rebases. Every variant of the image is the same build with a
# different base, so the workflow passes this per variant:
#   dx   -> ghcr.io/ublue-os/bazzite-dx-gnome:stable    (desktop)
#   deck -> ghcr.io/ublue-os/bazzite-deck-gnome:stable  (handheld / Game Mode)
# It must stay before the first FROM: only a global ARG can be used in FROM lines.
ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite-dx-gnome:stable"

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ${BASE_IMAGE}

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

## Which variant is being built; build.sh reads it from the environment to pick the
## per-flavor steps (dx = desktop, deck = handheld/Game Mode).
ARG TARGET_FLAVOR="dx"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh
