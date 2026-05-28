# ``SwiftTUIProfiling``

Opt-in profiling and diagnostics for SwiftTUI apps: frame timing, memory occupancy, and CPU signals in any build.

## Overview

`SwiftTUIProfiling` is a separately linkable product that turns SwiftTUI's
in-runtime diagnostics into a usable profiling surface. Nothing in the default
dependency graph depends on it; an app links it only when it wants profiling,
and activation is zero-cost until explicitly enabled.

The product consumes the runtime's neutral emit contract — a per-frame sample
plus the occupancy registry in `SwiftTUICore` — and owns the consumer-facing
layer: record derivation, formatting, and the sinks that write or summarize the
data. The runtime never depends on the product.

### Activating

Add the ``ProfilingScene/body`` modifier to a scene and gate it with an
environment variable:

```swift
import SwiftTUIProfiling

var body: some Scene {
  WindowGroup { GalleryView() }
    .profiling()   // env-gated; a complete no-op unless SWIFTTUI_PROFILE is set
}
```

With no argument, `.profiling()` reads `SWIFTTUI_PROFILE`. When it is unset the
modifier installs nothing — no sinks, no timers, the runtime registry stays
empty, and the per-frame path stays a single branch. Pass an explicit
``ProfileConfig`` to activate regardless of the environment.

### Signals

Three signals are each independently opt-in, named in the config or env var:

- **frames** — one record per committed frame, derived from the runtime sample.
- **memory** — periodic occupancy snapshots of long-lived stores (caches, the
  view graph, retained frames, the animation controller).
- **cpu** — periodic process CPU and resident-size samples.

### The `SWIFTTUI_PROFILE` grammar

```
SWIFTTUI_PROFILE = signal-list [ ";" sink-list ]
signal           = "frames" | "memory" [ "@" duration ] | "cpu" [ "@" duration ]
sink             = "tsv=" path | "jsonl=" path | "summary"
duration         = e.g. 100ms, 1s, 2s500ms
```

```bash
# Frames + memory once/sec, written as TSV; works in a release build:
SWIFTTUI_PROFILE="frames,memory@1s;tsv=/tmp/run.tsv" ./gallery-demo

# Just the memory signal, summary to stderr — the leak check:
SWIFTTUI_PROFILE="memory@500ms;summary" ./gallery-demo
```

Call ``ProfileActivation/finish()`` at shutdown so buffered sinks (summary)
emit their reduced report.

## Topics

### Activation

- ``ProfilingScene``
- ``ProfileConfig``
- ``ProfileActivation``

### CPU sampling

- ``CPUSampler``
- ``CPUSample``
- ``CPUSampleCollector``
- ``ProcessCPUReading``
- ``CPUSamplerError``
