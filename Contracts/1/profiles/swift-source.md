# Native Swift source profile 1

Identifier: `swifttui.swift-host/1`. The supported language mode is Swift 6 with
the repository's pinned Swift 6.4 toolchain. Use the published SwiftPM products;
`SwiftTUICore`, `SwiftTUIGraph` and `SwiftTUIPrimitives` are implementation
modules, not supported direct product imports. Their values re-exported through
a supported product can appear in supported signatures.

`../swift/inventory.jsonl` classifies every emitted public/SPI declaration and
records its complete declaration, generic constraints, referenced types,
conformances and default-implementation relationships. Actor annotations are
part of the declaration. Entries reachable through supported signatures retain
an explicit disposition even when their defining module is internal. A
signature-only disposition permits that value in the documented operation; it
does not promise its module's engine APIs or make a private module import public.
The inventory is generated from compiler symbol graphs and the framework's
single public API classification policy. A change under the same printed method
name still changes the ratchet. Platform-conditional APIs require their native
platform qualification in addition to the complete macOS census.

| Import | Supported purpose |
| --- | --- |
| `SwiftTUIViews` | Author views, styles and modifiers using ordinary public declarations classified canonical. |
| `SwiftTUIRuntime` | Scenes, application configuration, committed raster/semantic values and public host roles. |
| `@_spi(Host) import SwiftTUIRuntime` | Native-host operations below, without opting into broad runner internals. |
| `@_spi(Testing) import SwiftTUITestSupport` | Synchronous snapshot facade and documented test synchronization/assistive-output helpers. |
| `@_spi(Testing) import SwiftTUIRuntime` | Hosted-frame test waiters and explicit retained-history initialization. |
| `@_spi(StyleFixtures) import SwiftTUIViews` | Inert style configurations and captured slots for style tests. |

## Native host values and ownership

`AccessibilityNode.presentationIdentity` distinguishes repeated presentation
occurrences. `runtimeFocusIdentity` is the runtime keyboard-focus comparison
identity, which can be a row's selection control rather than its reported
identity. `Identity.hasPresentationOccurrence` is the typed occurrence query.
Hosts compare these values; they do not parse rendered identity paths. Neither
value substitutes for an opaque action target, request correlation ID or focus
generation. A removed target cannot be made live by retaining an old node.

`ImageBlendCompositor.encodedPNGPayload` returns owned value bytes, pixel size and
an opaque content ID. A host may retain the payload after another lookup or
compositor destruction. Mutating its Array value cannot mutate the compositor's
cache. The same rendered content reuses its ID within the selected framework;
changed blend inputs may change it. Do not parse the ID or assume a particular
hash algorithm or persistent stability across framework releases.

`SemanticHostFramePresentationSurface` accepts committed values directly, with
the standard capabilities supplied by its default witness. Metrics-provider
default witnesses remain available to an external conformer. A host owns its
presentation and callbacks; it need not serialize and decode a frame in process.
The explicit `HostedRasterSurfaceFrameDelivery.assumedMainActor` option requires
the producer to call from the main actor and checks that promise in optimized
builds. The ordinary initializer schedules callbacks on the main actor.

## Test behavior

`ViewTestRenderer` renders on the main actor. `ViewTestContext` supplies identity,
environment and explicit invalidations without a graph, renderer-stage or phase
tree API. The returned `RenderSnapshot` contains owned committed values and
diagnostics, with no retained private phase tree. `reset()` discards renderer
state without invalidating earlier snapshots. This is synchronous rendering;
application tasks, event loops and user actions require the real runtime. Node
counts and diagnostic labels are observational instrumentation, not fixed layout
or complexity promises.

Style fixture configurations have no live control routing identity. Their route
wrappers preserve content but install no pointer/action route; activation and
dismissal helpers are inert. Calling a style's `makeBody` directly does not run
dynamic-property preparation. Test dynamic properties by applying the style to
a real control through its modifier.

Hosted-frame waiters match retained or future committed frames. They are test
synchronization, not a production subscription API: arrange a matching frame
and a bounded test lifetime; cancellation does not synthesize a frame or resume
an unmatched waiter. Production hosts use callbacks and bounded default history.
Graph dumps, phase-tree assertions and broad `Runners` SPI remain internal or
legacy tooling. `Runners` aliases are retained for the tagged compatibility
floor, but new native host code uses Host and Testing explicitly.

The shipping native SwiftUI host and external test packages preserve their
exact tagged dependency's adapter until that tag contains this profile. A
coordination-owned candidate selection enables the new profile without changing
the public manifests or requiring coordination tooling for a fresh clone.
