# SwiftTUI Linux Development Environment

This directory owns the Linux build/test environment for SwiftTUI. It exists
because most contributors develop on macOS, but the project ships on Linux
(through `swift:6.3` on native amd64 and arm64 Ubuntu runners) and in browsers
(through the Wasm Swift SDK). Use this environment to reproduce a Linux failure
on a Mac with one command.

If you have not used the project Docker tools, read [Contents](#contents) and
[Daily workflow](#daily-workflow). Use the later sections as a reference for
errors and version updates.

---

## Contents

```
Scripts/
├── linux.sh                 # The CLI you actually use day-to-day
└── linux/
    ├── Dockerfile           # Image definition: Swift + bun + Wasm SDK + …
    └── README.md            # This file

.devcontainer/
└── devcontainer.json        # VS Code / Cursor / Codespaces entrypoint

.github/workflows/
└── build-linux-image.yml    # Builds & pushes the multi-arch image to GHCR
```

These four files cooperate as follows:

```
                        ┌───────────────────────────────────────┐
                        │   .github/workflows/                  │
                        │   build-linux-image.yml               │
                        │                                       │
                        │   native amd64 + arm64 builds         │
                        │   docker manifest push                │
                        └────────────────┬──────────────────────┘
                                         │ (publishes)
                                         ▼
                          ghcr.io/swifttui/swift-tui-linux:latest
                                         ▲
                ┌────────────────────────┼────────────────────────┐
                │                                                 │
   ┌────────────┴───────────┐                       ┌─────────────┴─────────────┐
   │  Scripts/linux.sh      │                       │  .devcontainer/           │
   │  (CLI: pull/start/test)│                       │  devcontainer.json        │
   │                        │                       │  (VS Code / Cursor /      │
   │  docker create + exec  │                       │   Codespaces)             │
   └────────────────────────┘                       └───────────────────────────┘
```

The image is built **once per Linux architecture** in CI, published as one
multi-arch manifest, and consumed by both the script and the devcontainer.
The image does not contain the repository source. The container bind-mounts the
repository at runtime.

---

## Image contents

`Scripts/linux/Dockerfile` layers the following onto the upstream
`swift:6.3.3` base:

| Tool          | Why it is preinstalled                                      |
|---------------|-------------------------------------------------------------|
| Swiftly       | Selects the repo-pinned Swift toolchain                     |
| Swift 6.3.3   | Installed and selected through Swiftly                      |
| bun           | Runs the repo gate scripts                                  |
| Wasm Swift SDK| Cross-compiles Swift packages to wasm32-unknown-wasi        |
| binaryen      | Provides `wasm-opt` for local primary-repo Wasm diagnostics |
| brotli        | Available for local primary-repo web artifact comparisons   |
| ripgrep       | Used by repo tests. Matches the GitHub Actions runner setup. |
| git, curl, unzip, ca-certificates, jq | General build prerequisites           |

Earlier versions of `Scripts/linux.sh` installed these tools during the first
use. It ran `apt-get install`, `curl | bash`, `swiftly install`, and
`swiftly run swift sdk install`.
The current image contains these tools. Thus, installation occurs after a
Dockerfile change instead of after each container reset. A Dockerfile change
occurs approximately 100 times less often.

---

## Daily workflow

Run all CLI calls through `Scripts/linux.sh`. You can run it from any directory.
It resolves the repository root from its own location. Built-in Linux build and test
commands invoke Swift through `swiftly run swift ...`, which matches the host-side
toolchain rule in
[`DEVELOPMENT.md`](https://github.com/SwiftTUI/swift-tui-org/blob/main/docs/swift-tui/DEVELOPMENT.md)
(in the `swift-tui-org` coordination repository).

```bash
# First time on a new machine:
./Scripts/linux.sh pull           # Pull the prebuilt image from GHCR
./Scripts/linux.sh start          # Create + start the long-lived container
./Scripts/linux.sh info           # Sanity check: prints toolchain versions

# Run CI-shaped validation plus optional Linux-only build checks:
./Scripts/linux.sh test           # CI Linux repo gate (Scripts/test_gate.sh)
./Scripts/linux.sh root-build-tests  # raw root-package swift build --build-tests
./Scripts/linux.sh root-test      # raw root-package swiftly run swift test
./Scripts/linux.sh cli-test       # focused SwiftTUICLI tests from the root package
./Scripts/linux.sh examples       # Print the extracted examples workflow location
./Scripts/linux.sh web            # Print the extracted browser workflow location
./Scripts/linux.sh full           # local full gate, incl. split CI checks

# Drop into the container for ad-hoc work:
./Scripts/linux.sh shell
./Scripts/linux.sh run swiftly run swift build

# Lifecycle:
./Scripts/linux.sh stop           # Stop the container (state preserved)
./Scripts/linux.sh reset          # Delete the container (cache survives)
./Scripts/linux.sh nuke           # Delete container AND SwiftPM cache volume
```

`start` is idempotent: if the container is already running with the expected
bind-mounted repository, it does nothing. If the container is stopped, the
command starts it. If the container is absent, the command creates it. It also
recreates a container that points to an old checkout path.

---

## How the runtime pieces fit together

When you run `./Scripts/linux.sh test`, the script:

1. Looks for `docker`. If it is unavailable, uses `podman`.
2. If the image is not local, pulls `ghcr.io/swifttui/swift-tui-linux:latest`.
   Docker selects the host-native image from the multi-arch manifest
   unless you set `LINUX_PLATFORM` explicitly.
3. Creates a named volume `swift-tui-…-swiftpm-cache` for SwiftPM's
   dependency + build artifact cache.
4. Creates a long-lived container with two mounts:
   - The repo root, **bind-mounted** at `/workspace`. Edits on your Mac
     show up immediately inside the container.
   - The SwiftPM cache **volume**, mounted at `/root/.cache/org.swift.swiftpm`.
5. Sets `WORKDIR=/workspace`. Then runs `sleep infinity` as PID 1, so the
   container stays alive between commands.
6. Runs `sh ./Scripts/test_gate.sh --skip-bun-install` through `docker exec`.
   Sets `DISABLE_EXPLICIT_PLATFORMS=1`, so `Package.swift` skips the macOS and
   iOS platform pins. Uses the same public-API and TermUIPerf skip environment
   as the GitHub Linux repository gate.

If a Linux failure is a compile error, use `./Scripts/linux.sh root-build-tests`.
This command does not run tests. For a raw root-package
`swiftly run swift test` run, use `./Scripts/linux.sh root-test`. The
CI-shaped gate intentionally splits root tests by target through
`Scripts/test_gate.sh`, and the broad SwiftTUI runtime step isolates the
high-contention async lifecycle and frame-tail suites. CI also runs the Linux
repo gate on native amd64 and arm64 runners, so architecture coverage does not
depend on x86 emulation.

Use `./Scripts/linux.sh full` when you intentionally want the slower local
superset that also runs the public API baseline and TermUIPerf tests covered by
separate CI workflows.

**Bind mounts vs named volumes** is the key distinction:

- **Bind mount** (`type=bind`): a path on your host is exposed inside the
  container, and changes are visible in both directions. The repo uses this
  mount so your edits are live.
- **Named volume** (`type=volume`): Docker manages an opaque chunk of
  storage. The container sees a normal directory. The host has no direct path
  to it. The SwiftPM cache uses this volume because it contains Linux build
  artifacts. These artifacts do not belong on the Mac file system.

---

## Image lifecycle

### When the image rebuilds automatically

`.github/workflows/build-linux-image.yml` triggers on changes to:

- `Scripts/linux/Dockerfile`
- `.swift-version`
- the workflow file itself

Other commits do not rebuild the image. The image is a build *input*, not an
output of each commit. Pull requests that modify these paths build both native
architectures. They do not push the image. Only `main` and manual
`workflow_dispatch` runs publish the multi-arch manifest to GHCR.

### Tags published to GHCR

Each successful publish emits a manifest containing both `linux/amd64` and
`linux/arm64` images:

| Tag                | When                              | Purpose                       |
|--------------------|-----------------------------------|-------------------------------|
| `:latest`          | `main` only                       | What `linux.sh` defaults to   |
| `:swift-6.3.3`     | every successful build            | Pin to a Swift toolchain      |
| `:sha-<7-char-sha> | every successful build            | Pin to an exact image build   |

Pin to `:sha-…` from `linux.sh`:

```bash
LINUX_IMAGE=ghcr.io/swifttui/swift-tui-linux:sha-abc1234 \
  ./Scripts/linux.sh start
```

### Bumping the Swift toolchain

1. Update `.swift-version` (the source of truth for the workflow's `SWIFT_VERSION` build arg).
2. Update the `ARG SWIFT_VERSION=` default at the top of `Scripts/linux/Dockerfile`.
3. Update `LINUX_SWIFT_VERSION` default in `Scripts/linux.sh` (kept in sync for local builds).
4. Push the change. CI rebuilds and republishes `:latest`.

### Bumping Swiftly

1. Update `SWIFTLY_VERSION` in:
   - `Scripts/linux.sh`
   - `Scripts/linux/Dockerfile`
   - `.github/workflows/build-linux-image.yml`
2. Push the change. CI rebuilds and republishes `:latest`.

### Bumping the Wasm SDK

1. Update `WASM_SDK_URL` and `WASM_SDK_CHECKSUM` in:
   - `Scripts/linux.sh` (top of the file)
   - `Scripts/linux/Dockerfile` (`ARG WASM_SDK_URL=` / `ARG WASM_SDK_CHECKSUM=`)
   - `.github/workflows/cloudflare-pages.yml` (the existing copy lives in the deploy step)
2. Push the change. CI rebuilds the image. Run `./Scripts/linux.sh pull` on
   each development machine.

### Building the image locally

During Dockerfile development, build the image locally:

```bash
./Scripts/linux.sh build              # native docker build with current ARGs
./Scripts/linux.sh reset              # drop the existing container
./Scripts/linux.sh start              # create a new one against the new image
./Scripts/linux.sh full               # validate
./Scripts/linux.sh push               # push only when you're satisfied
```

`build` uses the host-native platform by default. It tags the image with the
`LINUX_IMAGE` value. Thus, the default command overwrites the local `:latest`
tag. Use
`LINUX_IMAGE_BUILD_TAG=ghcr.io/swifttui/swift-tui-linux:experiment` to keep
the published image around. Set `LINUX_PLATFORM=linux/amd64` or
`LINUX_PLATFORM=linux/arm64` only for an intentional cross-platform
diagnostic build.

---

## Devcontainer (VS Code / Cursor / Codespaces)

`.devcontainer/devcontainer.json` points at the same image. To use it:

- **VS Code**: install the *Dev Containers* extension, then `Cmd+Shift+P` →
  *Dev Containers: Reopen in Container*.
- **Cursor**: same flow, same extension.
- **GitHub Codespaces**: create a Codespace from the repository. Codespaces
  reads `.devcontainer/devcontainer.json` automatically.

The devcontainer uses an independent volume name
(`swift-tui-devcontainer-swiftpm-cache`) so the editor's SwiftPM cache
does not conflict with the cache from `Scripts/linux.sh`. You can run both at
the same time. Edit in the devcontainer. Run `./Scripts/linux.sh test` from the
host terminal.

The devcontainer and `linux.sh` are independent surfaces over the same
image. If `linux.sh test` passes but the devcontainer behaves differently, the
environment causes the difference in 99% of cases, not the image. See
[Troubleshooting](#troubleshooting).

---

## Falling back to a vanilla Swift image

If GHCR is unavailable (rate limits, auth issues, fork without write
access), point `LINUX_IMAGE` at the upstream image:

```bash
LINUX_IMAGE=swift:6.3.3 ./Scripts/linux.sh start
LINUX_IMAGE=swift:6.3.3 ./Scripts/linux.sh full
```

`linux.sh` keeps lazy installers for Swiftly, bun, and the Wasm SDK
(`ensure_swiftly`, `ensure_bun`, `ensure_wasm_sdk`) specifically so this
fallback continues to work. The first command that needs Swift will install
Swiftly and the pinned Swift toolchain. The first command that needs Bun will
install Bun and its apt prerequisites. Subsequent runs reuse what got installed
inside the container until `nuke`.

Use this path only as a fallback. Each run downloads approximately 200 MB of
toolchain data.

---

## Volumes

The new setup uses **one** named volume:

| Volume                          | Mount path                          | Why                                              |
|---------------------------------|-------------------------------------|--------------------------------------------------|
| `swift-tui-…-swiftpm-cache`     | `/root/.cache/org.swift.swiftpm`    | SwiftPM dependency and build cache. It survives `reset`. |

Things that **used to** be volumes and are now baked into the image:

| Old volume                       | Replaced by                                  |
|----------------------------------|----------------------------------------------|
| `swift-tui-…-swiftly-home`       | Swiftly + selected toolchain preinstalled in image (`/root/.local/share/swiftly`) |
| `swift-tui-…-swiftpm-home`       | Wasm SDK preinstalled in image (`/root/.swiftpm/swift-sdks`) |
| `swift-tui-…-bun`                | bun installed system-wide in image (`/usr/local/bun`)        |

A named volume mounted on an image path **hides** the existing image content
at that path. For example, a volume at `/root/.swiftpm` hides the installed
Wasm SDK. The current mount layout keeps installed toolchains visible.

`./Scripts/linux.sh nuke` removes the container and the SwiftPM cache
volume. Use it when:

- The cache feels stale or wrong (rare; SwiftPM is good at invalidating)
- You want to time a cold build
- You need to free disk space

`nuke` does not affect the image. If you must remove it, run
`docker image rm ghcr.io/swifttui/swift-tui-linux:latest`.

---

## Troubleshooting

### `docker pull` fails with `denied` or `unauthorized`

The image is public. Docker can try to authenticate first after you run
`docker login ghcr.io`. Use one of these commands:

- `docker logout ghcr.io` and retry, or
- `docker login ghcr.io` with a GitHub PAT that has `read:packages`.

### `swiftly run swift sdk list` does not show the Wasm SDK

Two possible causes:

1. You are on a vanilla `swift:*` image, not the prebuilt image. Run
   `./Scripts/linux.sh web` once; it triggers `ensure_wasm_sdk`.
2. You are on the prebuilt image, but it does not contain the SDK. Pull the
   latest tag (`./Scripts/linux.sh pull`) and `reset` the container.

### `bun: command not found` inside the container

Same diagnostic: vanilla image (run `./Scripts/linux.sh web` to provision)
or stale prebuilt image (re-`pull` and `reset`).

### Builds are slow even after the second run

Make sure that Docker mounts the cache volume:

```bash
./Scripts/linux.sh run mount | grep swiftpm
```

The output must include `…swiftpm-cache on /root/.cache/org.swift.swiftpm`. If
it does not, rerun the command with the current script. The script recreates a
container that uses an older version.

### `./linux.sh shell` exits immediately

The container failed to start. Read the recent logs:

```bash
docker ps --format '{{.Names}}' | grep swift-tui
docker logs <container-name>
```

The image manifest usually changed while the named container kept an older
configuration. Rerun `./Scripts/linux.sh shell`. The current script recreates
containers whose bind mount or work directory does not match.

### Switching between the prebuilt image and a vanilla one mid-session

The container name contains the image and requested platform. If you change
`LINUX_IMAGE` or `LINUX_PLATFORM`, the script creates a *second* container. It does not
reconfigure the first container. To free disk space after this change, run:

```bash
LINUX_IMAGE=swift:6.3.3 ./Scripts/linux.sh nuke
```

If you pulled the old amd64-only `:latest` image on Apple Silicon, `linux.sh`
detects the architecture mismatch. It pulls the host-native manifest before it
creates the new default container.

### `permission denied` on bind-mounted files inside the container

You are probably on Linux. Docker does not remap the UID on Linux. The
container runs as root (UID 0). Files that it creates inside `/workspace` will
be owned by root on the host too. On macOS and Windows this is invisible
because Docker Desktop handles UID mapping. On Linux, either:

- `chown` the files back after a build, or
- run with `--user "$(id -u):$(id -g)"`. SwiftPM can report that root owns the
  cache volume from earlier runs. Run `nuke`
  first.

### Anything `./Scripts/linux.sh build` does, you can do directly

The script's `build` is a thin convenience wrapper. The equivalent raw
command is:

```bash
docker build \
  -f Scripts/linux/Dockerfile \
  -t ghcr.io/swifttui/swift-tui-linux:latest \
  --build-arg SWIFT_VERSION=6.3.3 \
  --build-arg SWIFTLY_VERSION=1.1.3 \
  Scripts/linux
```

If a `Dockerfile` syntax error occurs before `linux.sh` parses arguments, use
this command.

---

## What this setup deliberately does NOT do

- **Emulated default validation.** The published image is multi-arch and
  `linux.sh` leaves Docker's platform unset by default so local runs use the
  host-native image. `LINUX_PLATFORM` remains available for explicit
  cross-architecture diagnostics, but that path can use emulation depending on
  your host.
- **A Compose stack.** There is only one service and no network between
  containers. A `docker-compose.yml` adds unnecessary files.
- **Auto-cleanup of old SHA tags.** GHCR will retain every `:sha-…` tag
  forever unless we add a retention workflow. This is fine until the tag
  list becomes too long. Then we can add a `keep-last-N` cleanup job.
