# dux-atomic image definition.
#
# Layout follows the Universal Blue image-template
# (https://github.com/ublue-os/image-template): a ctx stage exposes the build
# scripts to one RUN, and a build script performs the installs.
#
# ARG before FROM is a global build arg, so a caller can override the base:
#   podman build --build-arg BASE_IMAGE=<ref> .

ARG BASE_IMAGE=ghcr.io/ublue-os/base-main:45

FROM ${BASE_IMAGE}
