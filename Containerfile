# dux-atomic image definition.
#
# Layout follows the Universal Blue image-template
# (https://github.com/ublue-os/image-template): a ctx stage exposes the build
# scripts to one RUN, and a build script performs the installs.
#
# BASE_IMAGE is a global build arg. It must precede the first FROM so the final
# stage can use it, and a caller can override the base:
#   podman build --build-arg BASE_IMAGE=<ref> .

ARG BASE_IMAGE=ghcr.io/ublue-os/base-main:45

# Allow build scripts to be referenced without being copied into the final image.
FROM scratch AS ctx
COPY build /build
COPY manifests /manifests
COPY overlay /overlay

# BASE_IMAGE is a build arg with an explicit tag; hadolint cannot resolve it.
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/build/common.sh

# Verify the final image and contents are correct.
RUN bootc container lint
