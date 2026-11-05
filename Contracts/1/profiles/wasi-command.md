# WASI command execution profile 1

Identifier: `swifttui.wasi-command/1`. This profile selects a core WebAssembly
command module, not a component or a JavaScript library. The module exports
one unshared wasm32 `memory` and a function `_start` with signature `() -> ()`.
It has no automatic start section. Its types are flat core function types;
recursive GC types, memory64, imported memory and shared module memory are
outside this profile. Imports are functions from `wasi_snapshot_preview1`
implemented by the selected browser WASI shim. The browser validates the
module and these requirements before instantiation or application execution.
An unknown import is an error, never a silently supplied stub.

The package contains the module, a scene catalog, the selected JavaScript
runtime and, for worker execution, its worker asset. Relative URLs resolve
against the package's configured base. The build helper applies the same
profile check after optimization and after debug-section stripping. A valid
WebAssembly header alone is not a runnable application.

| Mode | Requirements and lifetime |
| --- | --- |
| Worker | A loadable module worker and SharedArrayBuffer/Atomics for input. Deployment must provide the isolation headers required by the browser. Stop terminates the worker and clears pending input and decoder state. |
| JSPI | WebAssembly.Suspending and WebAssembly.promising. Main-thread execution suspends on input; closing the input channel wakes it for shutdown. |
| Auto | The runtime selects an available supported mode; callers can explicitly request one. It does not reinterpret an unknown mode string as auto. |

Stable failure prefixes are `wasi.profile.missingExport`,
`wasi.profile.unsupportedImport`, `wasi.profile.startSignature`,
`wasi.profile.unsupportedModule`, `wasi.profile.unsupportedMode`,
`wasi.profile.requiresJSPI`, `wasi.profile.requiresSharedMemory` and
`wasi.worker.startFailed`. Details after a prefix are explanatory text.
Unsupported browser/mode combinations must be reported before first frame.

The runner receives UTF-8 environment values, including `SWIFTTUI_SCENE`,
`SWIFTTUI_TRANSPORT=surface`, `SWIFTTUI_SURFACE_DELTA`, `SWIFTTUI_SURFACE_STYLE_APPEND`,
`SWIFTTUI_GEOMETRY_REVISIONS` and grid dimensions.
Capabilities are selected at startup, independently of the package version.
Surface output follows `wire.md`; WASI commits the encoding baseline when it
encodes output. There is no foreign size-query/copy transaction. A new module
instance starts a fresh host session and retires pending actions and images.
The browser input encoder emits RS-framed commands from `../grammar/host.abnf`.
The terminal shim's legacy transport remains a separately selected adapter.

`SWIFTTUI_MODE=manifest` runs scene discovery natively without executing the
WASI application. Catalog normalization follows the scene schema and wire
profile; browser mounting an empty catalog fails with a missing-scene error.
Worker and JSPI, Canvas and DOM, and each advertised browser engine require
their own first-frame, input and shutdown qualification.
