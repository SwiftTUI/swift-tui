# ``SwiftTUIProfiling``

Opt-in profiling and diagnostics for SwiftTUI apps in any build.

## Overview

`SwiftTUIProfiling` is a separately linkable product that turns SwiftTUI's
in-runtime diagnostics into a usable profiling surface. Nothing in the default
dependency graph depends on it. An app links it only when it needs profiling.
Activation has no cost until the app enables it.

The product consumes the runtime's neutral emit contract. This contract
contains a per-frame sample and the occupancy registry in `SwiftTUICore`. The
product derives and formats records. It also owns the sinks that write or
summarize the data. The runtime never depends on this product.

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
modifier installs no sinks or timers. The runtime registry stays empty, and
the per-frame path stays a single branch. Pass an explicit ``ProfileConfig``
to activate profiling independently of the environment.

### Signals

Three signals are independently available. Name them in the configuration or
environment variable:

- **frames** emits one record per committed frame, derived from the runtime
  sample.
- **memory** takes periodic occupancy snapshots of long-lived stores (caches,
  the view graph, retained frames, the animation controller).
- **cpu** takes periodic samples of process CPU and resident size.

The **frames** and **memory** signals have no standalone public types. You
reach them only by naming them in the env grammar or in a ``ProfileConfig``.
The **cpu** signal also exposes a reusable sampling API. You can use
``CPUSampler`` and its related types outside the activation path.

Records are routed to sinks selected by ``ProfileConfig/SinkDescriptor`` (or the
`tsv`/`jsonl`/`summary` tokens in the grammar). With no sink named, activation
falls back to a stderr ``ProfileConfig/SinkDescriptor/summary``. A bare `tsv`
or `jsonl` (no `=path`) writes `profile.tsv` / `profile.jsonl` into the
`SWIFTTUI_DEBUG_DIR` debug bundle (see the `SwiftTUIRuntime`
*Environment Variables* article); without an active bundle directory that
sink is dropped at activation.

### The `SWIFTTUI_PROFILE` grammar

```
SWIFTTUI_PROFILE = signal-list [ ";" sink-list ]
signal           = "frames" | "memory" [ "@" duration ] | "cpu" [ "@" duration ]
sink             = "tsv" [ "=" path ] | "jsonl" [ "=" path ] | "summary"
duration         = e.g. 100ms, 1s, 2s500ms
```

```bash
# Frames + memory once/sec, written as TSV; works in a release build:
SWIFTTUI_PROFILE="frames,memory@1s;tsv=/tmp/run.tsv" ./gallery-demo

# The same, into the session debug bundle:
SWIFTTUI_DEBUG_DIR=/tmp/bundle SWIFTTUI_PROFILE="frames,memory@1s;tsv" ./gallery-demo

# Just the memory signal, summary to stderr — the leak check:
SWIFTTUI_PROFILE="memory@500ms;summary" ./gallery-demo
```

Call ``ProfileActivation/finish()`` at shutdown so buffered sinks (summary)
emit their reduced report.

### `presents.tsv`, the frames file's sibling

The profiler emits a frame row at commit. On a real terminal, the related `write(2)`
operation completes later on the presentation writer queue. Waiting for it
reorders the sink contract and loses rows during teardown. Thus, write
completion goes to a **separate file**. If the `frames` signal uses a `tsv=`
sink, activation also opens `presents.tsv` in the same directory. Its fixed
name does not depend on the frames file. Thus, a reducer can find it without
the frames file name.

| column | meaning |
| --- | --- |
| `frame` | run-loop frame ordinal; joins `frames.tsv` on its `frame` column |
| `submitted_ms` | when the frame was handed to the presentation writer |
| `written_ms` | when `write(2)` returned. `-` means superseded. |
| `write_ms` | `written_ms − submitted_ms`. `-` means superseded. |
| `bytes` | UTF-8 size of the submitted emission |
| `outcome` | `written`, or `superseded` when a newer frame displaced it |

The join is total: every submission that carries a frame ordinal produces
exactly one row, whether or not it reached the terminal. Only the terminal host
runs an asynchronous writer, so on other hosts the file is opened and stays
empty. A synchronous host has no measured write latency. An absent measurement
is more accurate than a fabricated zero.

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
