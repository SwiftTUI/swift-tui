# Migrating to SwiftTUI 0.21

SwiftTUI 0.21 starts an explicit pre-1.0 compatibility policy. Supported public
API and the documented Host, Testing and StyleFixtures SPI are protected within
the 0.21.x line. Compatible fixes and additions may ship as patches; incompatible
source or promised behavior changes require a new minor and migration guidance.
The promise covers rebuilding source with the documented platform/toolchain set,
not precompiled Swift ABI across toolchains. Unratified implementation SPI remains
experimental. See [the compatibility policy](COMPATIBILITY.md).

Each SwiftTUI repository has its own version. Reusable supported Swift libraries
select a bounded framework line with `.upToNextMajor(from: "0.21.0")`, meaning
`>= 0.21.0` and `< 0.22.0`. Do not substitute SwiftPM's broader `from:` requirement.
Applications can retain exact tested selections. A new framework release does
not require a matching Charts, host, application or site release.

## Source changes from 0.20.1

- `Identity.lastComponent` returns `IdentityComponent?`. Read
  `lastComponent?.rawValue` for its former string result. The `components`
  string projection and deprecated `child(String)` overload remain available.
- Matched geometry IDs require `Hashable & Sendable`. Add the Sendable constraint
  to generic callers. `MatchedGeometryKey.id` stores `AnyID`; numeric `1` and
  textual `"1"` are distinct in the same namespace.
- `Shape.kindName` is no longer a requirement or a framework customization point.
  Remove generic reads of it. Keep an application-owned label when needed for
  diagnostics; express rendering through the shape's path. A custom same-named
  property no longer changes the framework node kind.
- `RasterReuseDiagnostics` uses `RasterPath` and `[FrameTailRasterReuseBarrier]`
  rather than strings. Construct values with enum cases; use `.rawValue` for
  textual output. These types are available through the supported runtime
  imports; `SwiftTUICore` is not a supported direct product import.
- New typed overloads can make unapplied references ambiguous. Annotate the
  function type when selecting a retained string overload:

  ```swift
  let makeIssue: (RuntimeIssueSeverity, String, String, Identity?, String?) -> RuntimeIssue = RuntimeIssue.init
  let send: (String) -> Void = reader.send
  ```

- `WASIRunnerError` adds `sceneNotFound(WindowIdentifier)`. Handle it in exhaustive
  switches. The enum retains Hashable and Sendable conformances.

`SwiftTUIRuntime.WindowIdentifier` remains available as a public typealias after
its definition moved to Primitives. Runtime-qualified imports, string literals,
raw-value construction and scene/configuration APIs remain source usable. Legacy
`SignalReading` and `FrameScheduling` conformers retain default typed adapters,
including host-defined signal names. Existing string projections for issue codes,
accessibility targets, task and lifecycle IDs remain readable/writable.

The deprecated string-keyed `AnimationState` API remains separate from the typed
`AnimationStateKey` store. It retains its existing store/read/remove behavior
through the compatibility line.

## Host and testing contracts

The public `Contracts/1` kit names Swift source, wire, WASM and Android C/JNI
profiles separately. Hosts use supported Host SPI for typed presentation identity
and owned image payloads. A native host can install a main-actor clipboard
reader on its hosted raster surface with `setClipboardReader(_:)`, so focused
paste commands read the current system clipboard. Existing initializers are
unchanged. Downstream tests use the supported Testing facade and
StyleFixtures. Private renderer/graph access, raw internal Runners/Testing probes
and outgoing SwiftUIHost Raster capture tooling are experimental, even when an
exact package selection happens to build them.

Platform-only public hosting APIs remain protected on their platforms. WASI's
`WebTerminalHost` provides the ANSI terminal surface. Android's
`AndroidMainExecutorPump.installIfNeeded()` must run before all main-actor work;
the C host creation entry point performs that bootstrap. Android profiling now
imports its platform libc and builds as a separately linkable product.
