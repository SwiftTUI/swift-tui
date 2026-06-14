# Vision Gap

This document is the **only gap register** in the documentation. Every other
document describes the code as it is at `HEAD`. This one records, concretely,
where the code falls short of the project's intent ([VISION.md](VISION.md)).

Each entry states what is **shipped today** and what is **not yet built**. None
of the unbuilt work is scheduled or promised here — this is a gap register, not
a roadmap.

Items that [VISION.md](VISION.md) declares out of scope are intentionally
omitted even when SwiftUI exposes a corresponding API.

## Accessibility

**Shipped.** The semantic substrate, the terminal linear renderer,
cursor-follows-focus, the Web/WASI ARIA tree, the SwiftUI-host overlay that
pushes runtime focus to VoiceOver, and the Android host's Compose semantics
overlay.

**Not yet built.**

- **Bidirectional native accessibility focus.** Focus flows runtime →
  VoiceOver/TalkBack only. Native assistive-technology-originated focus
  traversal is not fed back into SwiftTUI's runtime focus.
- **A WCAG-referenced conformance suite** and **automated screen-reader
  testing.** Accessibility is verified by unit tests and guardrail scripts, not
  by a conformance checklist.

## Android host

**Shipped.** `SwiftTUIAndroidHost` builds for `aarch64-unknown-linux-android28`
and the `swift-tui-examples/AndroidGallery` app embeds `GalleryView()` in a
Compose host. The frame snapshot carries styled cells, image attachment payloads,
damage metadata, focus presentation, accessibility nodes, and announcements, and
the host surfaces app-requested clipboard writes back across the JNI/C ABI
(`swift_tui_android_copy_clipboard_text`). The Compose renderer paints styled
cells and embedded images — drawing box-drawing, block, and braille glyphs
procedurally for seamless tiling — maintains a retained bitmap and repaints only
damaged rows when a frame's damage is contiguous, and exposes a transparent
semantics overlay that speaks runtime announcements through TalkBack. Input
bridges hardware keys (arrows, Home/End, Page Up/Down, Delete/Insert, and
Ctrl/Alt modifiers), the soft keyboard for text-input focus, touch press/drag,
wheel scroll, tap-to-open hyperlinks, and system clipboard copy and (bracketed)
paste.

**Not yet built.**

- **Bidirectional Android accessibility focus and IME composition.** Runtime
  focus reaches TalkBack, but TalkBack-originated focus traversal is not fed
  back into the runtime, and full IME pre-edit/marked-text composition (beyond
  committed text) is not implemented.
- **Android content URI import.** SAF / `content://` ingestion into the runtime
  drop path is not implemented.
- **Automated Android runtime gate.** `AndroidGallery` assembles locally and the
  Kotlin client logic now has JVM unit tests (`./gradlew testDebugUnitTest`,
  which run without the NDK), but emulator/device smoke is not in CI.
- **`x86_64` Android.** The first supported target is `arm64-v8a`; `x86_64`
  Android remains blocked by the vendored `swift-png` SIMD path.

## Terminal-program embedding

**Shipped.** `TerminalView`, `TerminalProcessSession` over a pty, and the
`SwiftTUITerminalWorkspace` tabbed/split-pane layer, on macOS and Linux.

**Not yet built.**

- Sixel/Kitty graphics inside embedded panes.
- The Kitty keyboard protocol and OSC 99 notification namespacing.
- A pane-local selection/copy/scrollback mode.
- **Process reattachment** — reconnecting to a still-running child process
  after the host app restarts — and a daemon-backed session lifecycle.
- iOS and WASI builds of the embedding products.

## Layout and pipeline internals

**Shipped.** The seven-phase pipeline, off-main frame-tail execution, and
explicit work-stack paths for parts of measurement and placement.

**Not yet built.**

- **Fully iterative built-in layout.** The explicit work-stack migration is
  partial: built-in layout still recurses on the Swift call stack, so the
  frame-tail worker still runs with an enlarged stack rather than a bounded
  iterative engine.
- **`ViewGraph` decomposition.** Splitting `ViewGraph` into smaller types with
  cleaner ownership, dependency-aware (profile-gated) body re-evaluation,
  explicit context threading through resolve, and interning of `Identity`
  values are all design-only — no corresponding code.

## Animation, transitions, and gestures

**Shipped.** Value-gated `.animation(_:value:)`, the timing-curve family
(bezier, spring, repeat/autoreverse), `.transition(_:)` with opacity and offset
effects, `matchedGeometryEffect`, `TapGesture`/`DragGesture` with
`.updating`/`.onChanged`/`.onEnded`, and a `Transaction` that carries animation
intent.

**Not yet built.** These carry the SwiftUI API shape but a narrower behavior.
Each is noted in a source doc comment; they are registered here so the
divergence from SwiftUI is recorded rather than silent.

- **Custom `Transition` effects.** The transition compositor interpolates only
  opacity and offset; other modifiers applied inside a custom `Transition.body`
  are ignored, and there is no built-in `.scale` transition.
- **`Gesture.updating(_:body:)` transaction.** The `inout Transaction` passed to
  the closure is a no-op stand-in; mutations to it are discarded.
- **`matchedGeometryEffect` size.** It interpolates position only, not size; a
  matched pair that changes size snaps to the destination size for the whole
  animation.
- **`TapGesture` multi-tap timing.** Multi-tap counts have no inter-tap timeout:
  consecutive on-target taps count as a multi-tap regardless of elapsed time.
- **`Transaction` fields.** Only animation intent is exposed; other SwiftUI
  transaction fields are not.

## Canvas and drawing

**Shipped.** The continuous coordinate type system (`Point`/`CellPoint`/
`PixelPoint`, `PointerLocation` with sub-cell precision) and the `Canvas`
drawing surface with Braille subpixel rendering.

**Not yet built.** `Canvas`'s internal drawing coordinate model is still the
legacy integer-cell interface; it has not been migrated to the fractional
cell-coordinate model the rest of the geometry system uses.

## Image rendering and compositing

**Shipped.** PNG and JPEG images render as host presentation attachments, and
`SwiftTUIAnimatedImage` displays pre-composed frames by feeding PNG bytes
through the same image surface. `View.blendMode(_:)` works for terminal-cell
content such as text, fills, strokes, and borders. A still `Image(...)` with an
active blend mode is now precomposed against its captured cell backdrop: the
rasterizer samples the backdrop under the image's visible bounds, applies the
active `BlendMode` in linear sRGB (with glyph-aware backdrops), and presents the
result through the existing attachment path, so unblended images keep their fast
native path.

**Not yet built.**

- **Animated-image / GIF blending.** `AnimatedImage(...).blendMode(...)` still
  emits unblended frames; the precomposition path covers still images only.
- **Ordered-layer compositing** of multiple overlapping blended images, and
  **native-host replay** of the precomposed variant outside the terminal image
  path.
