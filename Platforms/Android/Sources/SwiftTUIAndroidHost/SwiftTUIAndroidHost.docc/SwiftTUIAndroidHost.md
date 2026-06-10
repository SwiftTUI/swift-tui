# ``SwiftTUIAndroidHost``

Host SwiftTUI scenes inside native Android apps.

## Overview

`SwiftTUIAndroidHost` retains SwiftTUI scenes for host-managed Android
surfaces. The Swift runtime stays the source of truth for layout, state,
focus, input routing, accessibility semantics, raster output, and preferred
content size; the Android side renders published frame snapshots and bridges
key and touch input back into SwiftTUI.

The host publishes each frame as a versioned JSON snapshot
(``AndroidHostFrameSnapshot``) carrying styled cells, terminal colors,
underline and strikethrough decorations, image attachment records and
payloads, accessibility nodes and announcements, focus presentation, and the
preferred layout size. A small `swift_tui_android_*` C ABI surface
(``AndroidHostHandleRegistry``) lets JNI embedders create, start, resize,
feed input to, and destroy hosted scenes from Kotlin or Java.

Surface sizing reuses the same platform-neutral
`HostedSurfaceSizeNegotiator` rules as the SwiftUI host, including the
80×24 fallback when the embedding view has not reported a size yet.

The Android host is an early preview: hardware key and text input and basic
touch activation are bridged today, while IME composition, clipboard, link
opening, and precise drag and scroll gestures remain follow-up work. The
`AndroidGallery` example in `swift-tui-examples` shows a complete Jetpack
Compose embedding.

## Topics

### Scene Host

- ``AndroidHostSceneHost``
- ``AndroidHostStyle``

### Frame Snapshots

- ``AndroidHostFrameEncoder``
- ``AndroidHostFrameSnapshot``

### C ABI

- ``AndroidHostHandleRegistry``
