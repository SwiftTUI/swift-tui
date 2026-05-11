# SwiftTUI Linux dev environment

This directory owns the Linux build/test environment for SwiftTUI. It exists
because most contributors develop on macOS, but the project ships on Linux
(via `swift:6.3` on `ubuntu-latest`) and to the browser (via the Wasm Swift
SDK). Reproducing a Linux failure on a Mac means running it inside Linux —
which is what this setup gives you, with one command.

If you've never touched the Docker side of the project before, read all of
[What's in here](#whats-in-here) and [Daily workflow](#daily-workflow). The
later sections are reference for when something breaks or needs bumping.

---

## What's in here

```
Scripts/
├── linux.sh                 # The CLI you actually use day-to-day
└── linux/
    ├── Dockerfile           # Image definition: Swift + bun + Wasm SDK + …
    └── README.md            # This file

.devcontainer/
└── devcontainer.json        # VS Code / Cursor / Codespaces entrypoint

.github/workflows/
└── build-linux-image.yml    # Builds & pushes the image to GHCR
```

These four files cooperate as follows:

```
                        ┌───────────────────────────────────────┐
                        │   .github/workflows/                  │
                        │   build-linux-image.yml               │
                        │                                       │
                        │   docker buildx build                 │
                        │   docker push ghcr.io/.../swift-tui-… │
                        └────────────────┬──────────────────────┘
                                         │ (publishes)
                                         ▼
                          ghcr.io/goodhatsllc/swift-tui-linux:latest
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

The image is built **once** in CI and consumed by both the script and the
devcontainer. Nothing in the image references the repo source — the repo is
bind-mounted at runtime.

---

## What's in the image

`Scripts/linux/Dockerfile` layers the following onto the upstream
`swift:6.3.1` base:

| Tool          | Why it's preinstalled                                       |
|---------------|-------------------------------------------------------------|
| Swift 6.3.1   | From the base image                                         |
| bun           | Builds `Examples/WebExample` and the Astro website          |
| Wasm Swift SDK| Cross-compiles Swift packages to wasm32-unknown-wasi        |
| binaryen      | Provides `wasm-opt` for the WebExample wasm pipeline        |
| brotli        | WebExample wasm is shipped Brotli-compressed                |
| ripgrep       | Used by repo tests; matches the GH Actions runner setup     |
| git, curl, unzip, ca-certificates, jq | General build prerequisites           |

Everything in this table used to be installed lazily on first use by
`Scripts/linux.sh` (`apt-get install`, `curl | bash`, `swift sdk install`).
Baking it into the image moves a one-time cost from "every container reset"
to "every Dockerfile change", which is roughly 100x less often.

---

## Daily workflow

All CLI calls go through `Scripts/linux.sh`. Run it from anywhere — it
resolves the repo root from its own location.

```bash
# First time on a new machine:
./Scripts/linux.sh pull           # Pull the prebuilt image from GHCR
./Scripts/linux.sh start          # Create + start the long-lived container
./Scripts/linux.sh info           # Sanity check: prints toolchain versions

# Run the same things CI runs:
./Scripts/linux.sh test           # swift test (root package)
./Scripts/linux.sh cli-test       # focused SwiftTUICLI tests from the root package
./Scripts/linux.sh examples       # Build Linux example packages
./Scripts/linux.sh web            # Build WebExample + Platforms/Web host bundle
./Scripts/linux.sh workflow       # examples + web (mirrors CI)
./Scripts/linux.sh full           # test + workflow

# Drop into the container for ad-hoc work:
./Scripts/linux.sh shell
./Scripts/linux.sh run swift build --package-path Examples/gallery

# Lifecycle:
./Scripts/linux.sh stop           # Stop the container (state preserved)
./Scripts/linux.sh reset          # Delete the container (cache survives)
./Scripts/linux.sh nuke           # Delete container AND SwiftPM cache volume
```

`start` is idempotent: if the container is already running it does nothing,
if it exists but is stopped it starts it, and if it doesn't exist it creates
it. You don't need to babysit it.

---

## How the runtime pieces fit together

When you run `./Scripts/linux.sh test`, the script:

1. Checks for `docker` (or falls back to `podman`).
2. Pulls `ghcr.io/goodhatsllc/swift-tui-linux:latest` if you don't have it
   locally.
3. Creates a named volume `swift-tui-…-swiftpm-cache` for SwiftPM's
   dependency + build artifact cache.
4. Creates a long-lived container with two mounts:
   - The repo root, **bind-mounted** at `/workspace`. Edits on your Mac
     show up immediately inside the container.
   - The SwiftPM cache **volume**, mounted at `/root/.cache/org.swift.swiftpm`.
5. Sets `WORKDIR=/workspace`, then runs `sleep infinity` as PID 1 so the
   container stays alive between commands.
6. `docker exec`s `swift test` inside it, with `DISABLE_EXPLICIT_PLATFORMS=1`
   so `Package.swift` skips the macOS/iOS platform pins.

**Bind mounts vs named volumes** is the key distinction:

- **Bind mount** (`type=bind`): a path on your host is exposed inside the
  container. Two-way visibility. Used for the repo so your edits are live.
- **Named volume** (`type=volume`): Docker manages an opaque chunk of
  storage. The container sees a normal directory; the host doesn't have an
  obvious path to it. Used for the SwiftPM cache because it's
  Linux-format build artifacts that have no business living on your Mac
  filesystem and would only confuse you.

---

## Image lifecycle

### When the image rebuilds automatically

`.github/workflows/build-linux-image.yml` triggers on changes to:

- `Scripts/linux/Dockerfile`
- `.swift-version`
- the workflow file itself

Other commits don't rebuild — the image is a build *input*, not an output of
each commit. PRs that modify these paths build the image but don't push;
only `main` pushes (and manual `workflow_dispatch` runs) publish to GHCR.

### Tags published to GHCR

Each successful push job emits:

| Tag                | When                              | Purpose                       |
|--------------------|-----------------------------------|-------------------------------|
| `:latest`          | `main` only                       | What `linux.sh` defaults to   |
| `:swift-6.3.1`     | every successful build            | Pin to a Swift toolchain      |
| `:sha-<7-char-sha> | every successful build            | Pin to an exact image build   |

Pin to `:sha-…` from `linux.sh`:

```bash
LINUX_IMAGE=ghcr.io/goodhatsllc/swift-tui-linux:sha-abc1234 \
  ./Scripts/linux.sh start
```

### Bumping the Swift toolchain

1. Update `.swift-version` (the source of truth for the workflow's `SWIFT_VERSION` build arg).
2. Update the `ARG SWIFT_VERSION=` default at the top of `Scripts/linux/Dockerfile`.
3. Update `LINUX_SWIFT_VERSION` default in `Scripts/linux.sh` (kept in sync for local builds).
4. Push the change. CI rebuilds and republishes `:latest`.

### Bumping the Wasm SDK

1. Update `WASM_SDK_URL` and `WASM_SDK_CHECKSUM` in:
   - `Scripts/linux.sh` (top of the file)
   - `Scripts/linux/Dockerfile` (`ARG WASM_SDK_URL=` / `ARG WASM_SDK_CHECKSUM=`)
   - `.github/workflows/cloudflare-pages.yml` (the existing copy lives in the deploy step)
2. Push — CI rebuilds the image. Local devs rerun `./Scripts/linux.sh pull`.

### Building the image locally

When iterating on the Dockerfile itself, you don't want to push for every
attempt. Do it locally:

```bash
./Scripts/linux.sh build              # docker build with current ARGs
./Scripts/linux.sh reset              # drop the existing container
./Scripts/linux.sh start              # create a new one against the new image
./Scripts/linux.sh full               # validate
./Scripts/linux.sh push               # push only when you're satisfied
```

`build` defaults to tagging the image with whatever `LINUX_IMAGE` is — so by
default you'll overwrite the `:latest` tag on your local machine. Override
with `LINUX_IMAGE_BUILD_TAG=ghcr.io/goodhatsllc/swift-tui-linux:experiment`
to keep the published image around.

---

## Devcontainer (VS Code / Cursor / Codespaces)

`.devcontainer/devcontainer.json` points at the same image. To use it:

- **VS Code**: install the *Dev Containers* extension, then `Cmd+Shift+P` →
  *Dev Containers: Reopen in Container*.
- **Cursor**: same flow, same extension.
- **GitHub Codespaces**: just create a Codespace from the repo. Codespaces
  reads `.devcontainer/devcontainer.json` automatically.

The devcontainer uses an independent volume name
(`swift-tui-devcontainer-swiftpm-cache`) so the editor's SwiftPM cache
doesn't fight with the cache used by `Scripts/linux.sh`. You can run both
side-by-side: edit in the devcontainer, run `./Scripts/linux.sh test` from
your host terminal.

The devcontainer and `linux.sh` are independent surfaces over the same
image. If `linux.sh test` passes but the devcontainer behaves differently,
99% of the time the difference is environment, not the image — see
[Troubleshooting](#troubleshooting).

---

## Falling back to a vanilla Swift image

If GHCR is unavailable (rate limits, auth issues, fork without write
access), point `LINUX_IMAGE` at the upstream image:

```bash
LINUX_IMAGE=swift:6.3.1 ./Scripts/linux.sh start
LINUX_IMAGE=swift:6.3.1 ./Scripts/linux.sh full
```

`linux.sh` keeps lazy installers for bun and the Wasm SDK
(`ensure_bun`, `ensure_wasm_sdk`) specifically so this fallback continues to
work. The first `web` build will be slow (downloads bun, downloads the
Wasm SDK, installs binaryen/brotli/etc via apt); subsequent runs reuse what
got installed inside the container until `nuke`.

This path exists for resilience — don't make it the default. Every time it
runs it re-downloads ~200MB of toolchain.

---

## Volumes

The new setup uses **one** named volume:

| Volume                          | Mount path                          | Why                                              |
|---------------------------------|-------------------------------------|--------------------------------------------------|
| `swift-tui-…-swiftpm-cache`     | `/root/.cache/org.swift.swiftpm`    | SwiftPM dep + build artifact cache; survives `reset` |

Things that **used to** be volumes and are now baked into the image:

| Old volume                       | Replaced by                                  |
|----------------------------------|----------------------------------------------|
| `swift-tui-…-swiftpm-home`       | Wasm SDK preinstalled in image (`/root/.swiftpm/swift-sdks`) |
| `swift-tui-…-bun`                | bun installed system-wide in image (`/usr/local/bun`)        |

Why this matters: a named volume mounted on top of a path in the image
**hides** whatever the image had at that path on first use. If you mounted
a volume at `/root/.swiftpm`, the Wasm SDK installed there at build time
would vanish behind the volume. Removing those mounts is what lets us bake
toolchains into the image at all.

`./Scripts/linux.sh nuke` removes the container and the SwiftPM cache
volume. Use it when:

- The cache feels stale or wrong (rare — SwiftPM is good at invalidating)
- You want to time a cold build
- You're freeing disk space

The image itself isn't affected by `nuke`; remove it with
`docker image rm ghcr.io/goodhatsllc/swift-tui-linux:latest` if needed.

---

## Troubleshooting

### `docker pull` fails with `denied` or `unauthorized`

The image is public, but Docker may try to authenticate first if you've
ever run `docker login ghcr.io`. Either:

- `docker logout ghcr.io` and retry, or
- `docker login ghcr.io` with a GitHub PAT that has `read:packages`.

### `swift sdk list` doesn't show the Wasm SDK

Two possible causes:

1. You're on a vanilla `swift:*` image (not the prebuilt one). Run
   `./Scripts/linux.sh web` once — it triggers `ensure_wasm_sdk`.
2. You're on the prebuilt image but the SDK didn't make it in. Pull the
   latest tag (`./Scripts/linux.sh pull`) and `reset` the container.

### `bun: command not found` inside the container

Same diagnostic: vanilla image (run `./Scripts/linux.sh web` to provision)
or stale prebuilt image (re-`pull` and `reset`).

### Builds are slow even after the second run

Check that the cache volume is actually mounted:

```bash
./Scripts/linux.sh run mount | grep swiftpm
```

You should see `…swiftpm-cache on /root/.cache/org.swift.swiftpm`. If not,
the container was created against an older script version — `reset` and
`start` to recreate.

### `./linux.sh shell` exits immediately

Means the container failed to start. Look at recent logs:

```bash
docker logs swift-tui-ghcr.io-goodhatsllc-swift-tui-linux--latest
```

Most common cause: image manifest changed and the named container is bound
to an older config. `./Scripts/linux.sh reset` recreates it.

### Switching between the prebuilt image and a vanilla one mid-session

The container name encodes the image, so switching `LINUX_IMAGE` creates a
*second* container alongside the first rather than reconfiguring. To free
disk space when you're done with one:

```bash
LINUX_IMAGE=swift:6.3.1 ./Scripts/linux.sh nuke
```

### `permission denied` on bind-mounted files inside the container

You're probably on Linux (Docker doesn't UID-remap on Linux). The
container runs as root (UID 0); files it creates inside `/workspace` will
be owned by root on the host too. On macOS and Windows this is invisible
because Docker Desktop handles UID mapping. On Linux, either:

- `chown` the files back after a build, or
- run with `--user "$(id -u):$(id -g)"` (but then SwiftPM may complain
  about the cache volume being owned by root from earlier runs — `nuke`
  first).

### Anything `./Scripts/linux.sh build` does, you can do directly

The script's `build` is a thin convenience wrapper. The equivalent raw
command is:

```bash
docker build \
  -f Scripts/linux/Dockerfile \
  -t ghcr.io/goodhatsllc/swift-tui-linux:latest \
  --build-arg SWIFT_VERSION=6.3.1 \
  Scripts/linux
```

Useful when iterating on `Dockerfile` syntax errors that fail before
`linux.sh` can even parse args.

---

## What this setup deliberately does NOT do

- **Multi-arch builds.** The CI workflow only builds `linux/amd64`.
  Apple Silicon developers run it under Rosetta-emulated Linux containers
  (Docker Desktop handles this transparently). Adding `linux/arm64` is
  ~10 minutes of work in the workflow if it ever becomes painful — for
  now, the cost (doubled build time, doubled cache) outweighs the win.
- **A Compose stack.** There's only one service, with no networking
  between containers. A `docker-compose.yml` would add ceremony without
  removing anything.
- **Auto-cleanup of old SHA tags.** GHCR will retain every `:sha-…` tag
  forever unless we add a retention workflow. This is fine until the tag
  list gets unwieldy; then we can add a `keep-last-N` cleanup job.
