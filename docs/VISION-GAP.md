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

**Shipped.** The semantic substrate, terminal linear renderer,
cursor-follows-focus, and Web/WASI ARIA tree are complete. The SwiftUI-host
overlay pushes runtime focus to VoiceOver. The Android host provides a Compose
semantics overlay.

**Not yet built.**

- **Bidirectional native accessibility focus.** Focus flows runtime →
  VoiceOver/TalkBack only. Native assistive-technology-originated focus
  traversal is not fed back into SwiftTUI's runtime focus.
- **A WCAG-referenced conformance suite** and **automated screen-reader
  testing.** Unit tests and guardrail scripts cover accessibility, but no
  conformance checklist exists.

## Android host

**Shipped.** `SwiftTUIAndroidHost` builds for `aarch64-unknown-linux-android28`
and the `swift-tui-examples/AndroidGallery` app embeds `GalleryView()` in a
Compose host. The frame snapshot carries styled cells, image payloads, damage,
focus presentation, accessibility nodes, and announcements. The host returns
app-requested clipboard writes through the JNI/C ABI
(`swift_tui_android_copy_clipboard_text`). The Compose renderer paints styled
cells and embedded images. It draws box, block, and braille glyphs with
procedural rules for continuous tiling. The renderer keeps a retained bitmap.
If frame damage is contiguous, it repaints only the damaged rows. A transparent
semantics overlay sends runtime announcements to TalkBack. Input supports
hardware keys, the soft keyboard, touch, wheel scrolling, hyperlinks, and the
system clipboard.

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
- **`x86_64` Android packaging.** The framework — including the vendored
  `swift-png`/`JPEG` image path — cross-compiles for
  `x86_64-unknown-linux-android28`. The earlier `swift-png` SIMD build blocker
  no longer applies (the SIMD pixel path was replaced by a scalar
  reimplementation). `arm64-v8a` is the only ABI that the `AndroidGallery`
  example currently packages and smoke-tests.

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
  partial. Built-in layout still recurses on the Swift call stack. Thus, the
  frame-tail worker uses an enlarged stack instead of a bounded iterative
  engine.
- **`ViewGraph` decomposition.** Several changes remain design-only, with no
  corresponding code. They include smaller `ViewGraph` types with cleaner
  ownership and dependency-aware (profile-gated) body re-evaluation. They also
  include explicit context threading through resolve and interning of `Identity`
  values.

## WASI / browser execution

**Shipped.** The `SwiftTUIWASI` runner, `web-surface` wire, and current
WASI resolve behavior are described by the canonical
[per-host engine profile](HOSTS-AND-PLATFORMS.md#per-host-engine-profiles).
This section records only what remains divergent from the project's intent.

**Not yet built.**

- **Per-tick frame emission under retained reuse.** When retained reuse is
  active, reuse gates coalesce surface publications. This occurs with the full
  profile and the partial lean-profile option. Task-driven ticks that change
  the raster surface do not always produce a frame. In Chromium 0.1.9, Life
  emitted approximately one wire frame for four generations. The default lean
  profile masks this fault because it disables retained reuse. This fault must
  close before the full profile or JSPI main-thread mode becomes the WASI
  default.
- **Bounded-stack resolve as architecture.** The chunked driver is a
  stack-lean profile mechanism, not a fully iterative engine. Resolve and
  built-in layout, registered under "Layout and pipeline internals") still
  recurse on the Swift call stack, so stack budgets remain a per-engine
  constraint rather than a non-issue.

## Animation, transitions, and gestures

**Shipped.** Value-gated `.animation(_:value:)` and the timing-curve family
(bezier, spring, repeat/autoreverse) are complete. The API also includes
`.transition(_:)` with opacity and offset effects and `matchedGeometryEffect`.
`TapGesture`/`DragGesture` provide `.updating`/`.onChanged`/`.onEnded`. A
`Transaction` carries animation intent.

**Not yet built.** These carry the SwiftUI API shape but a narrower behavior.
Each one appears in a source documentation comment. This register makes the
divergence from SwiftUI explicit.

- **Custom `Transition` effects.** The transition compositor interpolates only
  opacity and offset. Other modifiers applied inside a custom `Transition.body`
  are ignored, and there is no built-in `.scale` transition.
- **`Gesture.updating(_:body:)` transaction.** The `inout Transaction` passed to
  the closure is a no-op stand-in. Mutations to it are discarded.
- **`matchedGeometryEffect` size.** It interpolates position only, not size. A
  matched pair that changes size snaps to the destination size for the whole
  animation.
- **`TapGesture` multi-tap timing.** Multi-tap counts have no inter-tap timeout:
  consecutive on-target taps count as a multi-tap regardless of elapsed time.
- **`Transaction` fields.** Only animation intent is exposed. Other SwiftUI
  transaction fields are not.

## Canvas and drawing

**Shipped.** The continuous coordinate type system (`Point`/`CellPoint`/
`PixelPoint`, `PointerLocation` with sub-cell precision) and the `Canvas`
drawing surface with Braille subpixel rendering.

**Not yet built.** `Canvas`'s internal drawing coordinate model is still the
legacy integer-cell interface. It does not use the fractional
cell-coordinate model the rest of the geometry system uses.

## Image rendering and compositing

**Shipped.** PNG and JPEG images render as host presentation attachments, and
`SwiftTUIAnimatedImage` displays pre-composed frames by feeding PNG bytes
through the same image surface. `View.blendMode(_:)` works for terminal-cell
content such as text, fills, strokes, and borders. For a still `Image(...)`
with an active blend mode, the rasterizer precomposes a
still image that has an active blend mode. It samples the backdrop under the
visible image bounds. Then it applies the active `BlendMode` in linear sRGB
with glyph-aware backdrops. It presents the result through the existing
attachment path. Unblended images keep the fast native path.

**Not yet built.**

- **Animated-image / GIF blending.** `AnimatedImage(...).blendMode(...)` still
  emits unblended frames. The precomposition path covers still images only.
- **Ordered-layer compositing** of multiple overlapping blended images, and
  **native-host replay** of the precomposed variant outside the terminal image
  path.
