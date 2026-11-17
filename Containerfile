# Fast flavor-specific output stage. COMMON_IMAGE is the local image built by
# Containerfile.common, never an independently rebuilt upstream distribution.
ARG COMMON_IMAGE="localhost/cachyos-bazzite-common:build"
FROM scratch AS ctx
COPY build_files /

FROM ${COMMON_IMAGE}
ARG TARGET_FLAVOR="dx"
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/flavor.sh
