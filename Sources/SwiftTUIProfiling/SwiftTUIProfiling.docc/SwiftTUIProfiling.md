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

Add the `profiling()` modifier to a scene and gate it with an environment
variable. It wraps the scene in a ``ProfilingScene`` whose `body` activates
profiling during scene setup:

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

The **frames** and **memory** signals have no standalone public types — you
reach them only by naming them in the env grammar or in a ``ProfileConfig``.
The **cpu** signal additionally exposes a reusable sampling API (``CPUSampler``
and friends, under **CPU sampling** below) that you can drive directly outside
the activation path.

Records are routed to sinks selected by ``ProfileConfig/SinkDescriptor`` (or the
`tsv=`/`jsonl=`/`summary` tokens in the grammar). With no sink named, activation
falls back to a stderr ``ProfileConfig/SinkDescriptor/summary``.

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

### `presents.tsv`, the frames file's sibling

A frame row is emitted at commit, but on a real terminal the `write(2)` that
puts its bytes on the wire completes later, on the presentation writer's own
queue. Delaying the frame row to wait for it would reorder the sink contract
and lose rows on teardown, so write completion goes to a **separate file**:
whenever the `frames` signal is paired with a `tsv=` sink, activation also opens
`presents.tsv` in the same directory. Its name is fixed, not derived from the
frames file, so a reducer can find it without knowing what you called the frames
file.

| column | meaning |
| --- | --- |
| `frame` | run-loop frame ordinal — joins `frames.tsv` on its `frame` column |
| `submitted_ms` | when the frame was handed to the presentation writer |
| `written_ms` | when `write(2)` returned; `-` when superseded |
| `write_ms` | `written_ms − submitted_ms`; `-` when superseded |
| `bytes` | UTF-8 size of the submitted emission |
| `outcome` | `written`, or `superseded` when a newer frame displaced it |

The join is total: every submission that carries a frame ordinal produces
exactly one row, whether or not it reached the terminal. Only the terminal host
runs an asynchronous writer, so on other hosts the file is opened and stays
empty — a synchronous host's "write latency" would be a fabricated zero, and an
absent measurement is more useful than a fake one.

## Topics

### Activation

- ``ProfilingScene``
- ``ProfileActivation``

### Configuring signals and sinks

- ``ProfileConfig``
- ``ProfileConfig/Signal``
- ``ProfileConfig/SinkDescriptor``

### CPU sampling

- ``CPUSampler``
- ``CPUSample``
- ``CPUSampleCollector``
- ``ProcessCPUReading``
- ``CPUSamplerError``
