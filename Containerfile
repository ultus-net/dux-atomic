# dux-atomic image definition.
#
# Layout follows the Universal Blue image-template
# (https://github.com/ublue-os/image-template): a ctx stage exposes the build
# scripts to one RUN, and a build script performs the installs.

# Allow build scripts to be referenced without being copied into the final image.
FROM scratch AS ctx
COPY build /build
COPY manifests /manifests
COPY overlay /overlay

# The base is pinned to a digest, and the tag stays for readers. The pin is a
# literal rather than an ARG: Dependabot reads a file whose name matches
# containerfile|dockerfile, and never expands an ARG into FROM.
# tests/test-static.sh asserts the tag+digest form.
FROM ghcr.io/ublue-os/base-main:45@sha256:444e9e37ea581e76829772ae2a42edfdbacdd0cbc7a27085a4ed0f3d6e1336c7

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/build/common.sh

# Verify the final image and contents are correct.
RUN bootc container lint
