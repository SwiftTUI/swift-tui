# ``SwiftTUIProfiling``

Opt-in profiling and diagnostics for SwiftTUI apps: frame timing, occupancy, and CPU signals in any build.

## Overview

`SwiftTUIProfiling` is a separately linkable product that turns SwiftTUI's
in-runtime diagnostics into a usable profiling surface. Nothing in the default
dependency graph depends on it; an app links it only when it wants profiling,
and activation is zero-cost until explicitly enabled.

The product consumes the runtime's neutral emit contract — a per-frame
``SwiftTUIRuntime`` sample plus the occupancy registry in `SwiftTUICore` — and
owns the consumer-facing layer: record derivation, formatting, and the sinks
that write or summarize the data.

Three signals are each independently opt-in:

- **frames** — one record per committed frame, derived from the runtime sample.
- **memory** — periodic occupancy snapshots of long-lived stores.
- **cpu** — periodic process CPU and resident-size samples.

> Note: This product is being assembled in phases. The activation surface
> (`.profiling()` and the `SWIFTTUI_PROFILE` environment grammar) and the full
> sink set land in later phases; today it ships the frame TSV sink built on the
> shared contract.
