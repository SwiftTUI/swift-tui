# syntax=docker/dockerfile:1.7
#
# SwiftTUI Linux dev/test image.
#
# Bakes everything Scripts/linux.sh used to install lazily on first use:
#   * Swift toolchain (from the upstream `swift:<version>` image)
#   * Bun (system-wide install at /usr/local/bun)
#   * Wasm Swift SDK (preinstalled at /root/.swiftpm/swift-sdks)
#   * binaryen (wasm-opt), brotli, ripgrep, curl, unzip, git, ca-certificates
#
# Build args mirror the variables Scripts/linux.sh exports so a bump to the
# Swift toolchain or Wasm SDK is a one-line change in both places. CI passes
# these explicitly; local `docker build` falls back to the defaults below.
#
# IMPORTANT: keep these defaults in sync with .swift-version and the
# WASM_SDK_* vars at the top of Scripts/linux.sh.

ARG SWIFT_VERSION=6.3.1
FROM swift:${SWIFT_VERSION}

ARG WASM_SDK_URL=https://download.swift.org/swift-6.3.1-release/wasm-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_wasm.artifactbundle.tar.gz
ARG WASM_SDK_CHECKSUM=bd47baa20771f366d8beed7970afaa30742b2210097afd15f85427226d8f4cf2
ARG BUN_INSTALL=/usr/local/bun

LABEL org.opencontainers.image.title="swift-tui-linux" \
      org.opencontainers.image.description="Swift toolchain + Bun + Wasm SDK + binaryen for SwiftTUI Linux/web builds" \
      org.opencontainers.image.source="https://github.com/GoodHatsLLC/SwiftTUI" \
      org.opencontainers.image.licenses="MIT"

ENV BUN_INSTALL=${BUN_INSTALL} \
    PATH="${BUN_INSTALL}/bin:${PATH}" \
    DEBIAN_FRONTEND=noninteractive

# System dependencies. The upstream swift image ships a slim Ubuntu base, so
# we add the tools the SwiftTUI Linux + WebExample workflows actually use:
#   - curl/unzip:    bun installer + general fetch
#   - ca-certificates+git: SwiftPM dependency resolution over HTTPS
#   - ripgrep:       used by repo tests + matches the GH Actions runner setup
#   - binaryen:      provides wasm-opt for Examples/WebExample
#   - brotli:        WebExample wasm is shipped Brotli-compressed
#   - jq:            convenient for inspecting JSON in the container
#
# `--no-install-recommends` keeps the image close to the minimum, and we wipe
# /var/lib/apt/lists in the same RUN so it never lands in a layer.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      unzip \
      ripgrep \
      binaryen \
      brotli \
      jq \
 && rm -rf /var/lib/apt/lists/*

# Bun, installed system-wide. The official installer wants $BUN_INSTALL set,
# defaults to ~/.bun. We pin it to /usr/local/bun so it isn't shadowed when a
# user mounts a volume at /root/.bun, and symlink the binaries into a
# directory that's already on $PATH for any new shell.
RUN curl -fsSL https://bun.sh/install | bash \
 && ln -sf "${BUN_INSTALL}/bin/bun"  /usr/local/bin/bun \
 && ln -sf "${BUN_INSTALL}/bin/bunx" /usr/local/bin/bunx

# Wasm Swift SDK. `swift sdk install` is the official path; it unpacks the
# artifact bundle into /root/.swiftpm/swift-sdks. We do NOT mount a volume
# over /root/.swiftpm at runtime (see Scripts/linux/README.md "Volumes"),
# otherwise the SDK installed here would be hidden behind the volume.
RUN swift sdk install "${WASM_SDK_URL}" --checksum "${WASM_SDK_CHECKSUM}"

# Smoke test the layered tools so a broken image fails the build instead of
# blowing up the first time someone runs `./linux.sh test`.
RUN swift --version \
 && swift sdk list \
 && bun --version \
 && wasm-opt --version \
 && brotli --version \
 && rg --version | head -n 1

# Default working directory matches the host bind mount target in linux.sh.
# Override at `docker run` / `docker create` time if you point the script at
# a different LINUX_CONTAINER_DIR.
WORKDIR /workspace

# Long-lived dev container pattern: keep PID 1 alive so `docker exec` is the
# primary interaction model. linux.sh launches us this way; CI overrides it.
CMD ["sleep", "infinity"]
