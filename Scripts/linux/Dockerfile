# syntax=docker/dockerfile:1.7
#
# SwiftTUI Linux dev/test image.
#
# Bakes everything Scripts/linux.sh used to install lazily on first use:
#   * Swiftly + the pinned Swift toolchain
#   * Bun (system-wide install at /usr/local/bun)
#   * Wasm Swift SDK (preinstalled at /root/.swiftpm/swift-sdks)
#   * binaryen (wasm-opt), brotli, ripgrep, python3, curl, unzip, git, ca-certificates
#
# Build args mirror the variables Scripts/linux.sh exports so a bump to the
# Swift toolchain or Wasm SDK is a one-line change in both places. CI passes
# these explicitly; local `docker build` falls back to the defaults below.
#
# IMPORTANT: keep these defaults in sync with .swift-version and the
# SWIFTLY_* / WASM_SDK_* vars at the top of Scripts/linux.sh.

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG SWIFT_VERSION=6.4.0
ARG SWIFTLY_VERSION=1.1.4
ARG BUN_VERSION=1.3.14
ARG WASM_SDK_URL=https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz
ARG WASM_SDK_CHECKSUM=f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d
ARG BUN_INSTALL=/usr/local/bun

LABEL org.opencontainers.image.title="swift-tui-linux" \
      org.opencontainers.image.description="Swift toolchain + Bun + Wasm SDK for SwiftTUI Linux and Wasm checks" \
      org.opencontainers.image.source="https://github.com/SwiftTUI/swift-tui" \
      org.opencontainers.image.licenses="MIT"

ENV BUN_INSTALL=${BUN_INSTALL} \
    SWIFTLY_HOME_DIR=/root/.local/share/swiftly \
    SWIFTLY_BIN_DIR=/root/.local/bin \
    DEBIAN_FRONTEND=noninteractive
ENV PATH="${BUN_INSTALL}/bin:${SWIFTLY_BIN_DIR}:${PATH}"

# Swiftly's generated env.sh uses bash conditionals, so image provisioning must
# not source it through Docker's default /bin/sh.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System dependencies for the Swiftly-managed toolchain on Ubuntu 24.04,
# plus the tools the SwiftTUI Linux workflow and local checks use:
#   - curl/unzip:    bun installer + general fetch
#   - libcurl dev:   Swiftly's downloaded Swift toolchains require it
#   - ca-certificates+git: SwiftPM dependency resolution over HTTPS
#   - ripgrep:       used by repo tests + matches the GH Actions runner setup
#   - binaryen:      provides wasm-opt for local primary-repo Wasm diagnostics
#   - brotli:        available for local primary-repo web artifact checks
#   - python3:       parses Swift loaded-module traces in policy checks
#   - jq:            convenient for inspecting JSON in the container
#   - gdb:           the repo gate's step watchdog dumps thread backtraces of
#                    a wedged test process before killing it
#                    (SWIFTTUI_HANG_DIAGNOSTICS=1; Scripts/lib/step_watchdog.sh)
#
# `--no-install-recommends` keeps the image close to the minimum, and we wipe
# /var/lib/apt/lists in the same RUN so it never lands in a layer.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      binutils \
      ca-certificates \
      curl \
      git \
      gnupg2 \
      libc6-dev \
      libcurl4-openssl-dev \
      libedit2 \
      libgcc-13-dev \
      libncurses-dev \
      libncurses6 \
      libpython3-dev \
      libsqlite3-0 \
      libstdc++-13-dev \
      libxml2-dev \
      libz3-dev \
      pkg-config \
      rsync \
      tzdata \
      zlib1g-dev \
      unzip \
      ripgrep \
      binaryen \
      brotli \
      python3 \
      jq \
      gdb \
 && rm -rf /var/lib/apt/lists/*

# Bun, installed system-wide. The official installer wants $BUN_INSTALL set,
# defaults to ~/.bun. We pin it to /usr/local/bun so it isn't shadowed when a
# user mounts a volume at /root/.bun, and symlink the binaries into a
# directory that's already on $PATH for any new shell.
RUN curl -fsSL https://bun.sh/install | bash -s -- "bun-v${BUN_VERSION}" \
 && ln -sf "${BUN_INSTALL}/bin/bun"  /usr/local/bin/bun \
 && ln -sf "${BUN_INSTALL}/bin/bunx" /usr/local/bin/bunx

# Swiftly, installed before the Wasm SDK so all SwiftPM work goes through the
# same toolchain manager used by the host-side repo workflow. Starting from
# Ubuntu lets us use a Swift release as soon as its toolchain is available,
# without waiting for the upstream Swift Docker image to be published.
RUN swiftly_archive="swiftly-${SWIFTLY_VERSION}-$(uname -m).tar.gz" \
 && curl -fsSLO "https://download.swift.org/swiftly/linux/${swiftly_archive}" \
 && tar -zxf "${swiftly_archive}" \
 && ./swiftly init --skip-install --quiet-shell-followup --assume-yes \
 && . "${SWIFTLY_HOME_DIR}/env.sh" \
 && swiftly install --use --assume-yes "${SWIFT_VERSION}" \
 && rm -f "${swiftly_archive}" swiftly

# Wasm Swift SDK. `swiftly run swift sdk install` unpacks the artifact bundle
# into /root/.swiftpm/swift-sdks. We do NOT mount a volume over /root/.swiftpm
# at runtime (see Scripts/linux/README.md "Volumes"), otherwise the SDK
# installed here would be hidden behind the volume.
RUN swiftly run swift sdk install "${WASM_SDK_URL}" --checksum "${WASM_SDK_CHECKSUM}"

# Smoke test the layered tools so a broken image fails the build instead of
# blowing up the first time someone runs `./linux.sh test`.
RUN swiftly --version \
 && swiftly run swift --version \
 && swiftly run swift sdk list \
 && bun --version \
 && wasm-opt --version \
 && brotli --version \
 && python3 --version \
 && rg --version | head -n 1

# Default working directory matches the host bind mount target in linux.sh.
# Override at `docker run` / `docker create` time if you point the script at
# a different LINUX_CONTAINER_DIR.
WORKDIR /workspace

# Long-lived dev container pattern: keep PID 1 alive so `docker exec` is the
# primary interaction model. linux.sh launches us this way; CI overrides it.
CMD ["sleep", "infinity"]
