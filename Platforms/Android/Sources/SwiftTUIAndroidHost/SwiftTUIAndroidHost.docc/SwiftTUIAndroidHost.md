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
The initial size defaults to 80×24; `resize` updates both the cell grid and
reported cell-pixel metrics before requesting a surface refresh.

This Swift product is one half of the Android integration. The Compose host,
JNI shim, AAR, and Gradle plugin ship from
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android). See
[Hosts and Platforms](https://github.com/SwiftTUI/swift-tui/blob/main/docs/HOSTS-AND-PLATFORMS.md)
for the
canonical packaging and engine-profile boundaries.

## Converged Frame Wire

Android does not define a separate frame snapshot or encoder. It emits the
same converged `web-surface` wire used by the WASI and WebHost transports:
package-only `HostWireFrameModel` derives the host-facing fields, and
package-only `WebSurfaceFrameEncoder` formats the versioned full or delta
record.

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
   subsequent copy, and repeated polls of the same frame reuse those bytes;
   frames skipped by the polling client are never serialized.

The consumed record carries styled cells, hyperlink and image records,
accessibility nodes and announcements, scroll regions, focus presentation,
damage, preferred sizing, and terminal style through the one shared wire
model. Accumulating damage until consumption keeps deltas relative to the
previous frame selected by the client's copy handshake, rather than merely the
previous runtime commit.

## JNI And Host Lifecycle

``AndroidHostHandleRegistry`` maps opaque integer handles to retained scene
hosts. The exported `swift_tui_android_*` C entry points let the JNI bridge
start, stop, destroy, tick, resize, send input, declare wire capabilities, copy
the latest frame, and drain app-requested clipboard text.

Frame and clipboard copies use a two-call contract: a nil or undersized output
buffer reports the required UTF-8 byte count without consuming the value; a
large-enough buffer performs the copy. Clipboard text drains after a successful
copy, while frame bytes remain cached until a newer sequence is consumed.

The Android render poll also drives the Swift main-actor executor so ready
runtime continuations, tasks, and animation wakes make progress on the host
main thread. Current behavior gaps are tracked in
[Vision Gap](https://github.com/SwiftTUI/swift-tui/blob/main/docs/VISION-GAP.md#android-host).

## Topics

### Scene Host

- ``AndroidHostSceneHost``
- ``AndroidHostStyle``

### C ABI

- ``AndroidHostHandleRegistry``
