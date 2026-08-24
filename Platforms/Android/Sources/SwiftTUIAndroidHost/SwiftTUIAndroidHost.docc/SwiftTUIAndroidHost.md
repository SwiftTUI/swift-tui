# ``SwiftTUIAndroidHost``

Host SwiftTUI scenes inside native Android apps.

## Overview

``AndroidHostSceneHost`` retains a SwiftTUI scene in a
`HostedSceneSession` backed by `HostedRasterSurface`. The Swift runtime remains
the source of truth for layout, state, focus, input routing, accessibility
semantics, raster output, damage, and preferred content size. The Android side
renders the consumed wire frame and sends input and surface metrics back to the
session.

``AndroidHostStyle`` supplies the terminal appearance and initial cell size.
The initial size is 80×24 by default. `resize` updates the cell grid and the
reported cell-pixel metrics. Then it requests a surface refresh.

This Swift product is one half of the Android integration. The Compose host,
JNI shim, AAR, and Gradle plugin ship from
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android). See
[Hosts And Platforms](https://swifttui.sh/docs/documentation/swifttuiruntime/hosts-and-platforms)
for the
canonical packaging and engine-profile boundaries.

## Converged Frame Wire

Android does not define a separate frame snapshot or encoder. It emits the
same converged `web-surface` wire that the WASI and WebHost transports use.
Package-only `HostWireFrameModel` derives the host-facing fields. Package-only
`WebSurfaceFrameEncoder` formats the versioned full or delta record.

Encoding happens when the client copies a frame, not when the runtime commits
it:

1. The host retains the latest `SemanticHostFrame`, its style, and damage
   accumulated across every committed-but-unconsumed frame.
2. The first `copyLatestFrameBytes` request for a sequence builds
   `HostWireFrameModel` from the raster, sequence, semantics, focused identity,
   accumulated damage, preferred layout size, and Android terminal style.
3. `WebSurfaceFrameEncoder` emits a full record by default or a delta record
   when capabilities declared before scene start allow it.
4. The encoded UTF-8 bytes are cached by sequence. The ABI's size query,
   subsequent copy, and repeated polls of the same frame reuse those bytes.
   The encoder does not serialize frames that the polling client skips.

The consumed record carries styled cells, hyperlink records, image records,
accessibility nodes, announcements, and scroll regions. It also carries focus
presentation, damage, preferred sizing, and terminal style through the shared
wire model. Accumulating damage until consumption keeps deltas relative to the
previous frame selected by the client's copy handshake, rather than merely the
previous runtime commit.

## JNI And Host Lifecycle

``AndroidHostHandleRegistry`` maps opaque integer handles to retained scene
hosts. The exported `swift_tui_android_*` C entry points let the JNI bridge
start, stop, destroy, tick, resize, and send input. They also let the bridge
declare wire capabilities, copy the latest frame, and drain app-requested
clipboard text.

Frame and clipboard copies use a two-call contract: a nil or undersized output
buffer reports the required UTF-8 byte count without consuming the value. A
large-enough buffer copies the value. A successful copy drains clipboard text.
Frame bytes stay cached until the client consumes a newer sequence.

The Android render poll also drives the Swift main-actor executor so ready
runtime continuations, tasks, and animation wakes make progress on the host
main thread. Current behavior gaps are contributor-facing and tracked in the
repository's divergence and gap register
(`Sources/SwiftTUIViews/SwiftTUIViews.docc/Divergences-And-Gaps.md`), not here.

## Topics

### Integration

- <doc:Hosting-On-Android>

### Scene Host

- ``AndroidHostSceneHost``
- ``AndroidHostStyle``

### C ABI

- ``AndroidHostHandleRegistry``
