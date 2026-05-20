# Vision Gap

This document is the **only** place in the documentation that describes
intended-but-unbuilt work. Every other document describes the code as it is at
`HEAD`. This one records, concretely, where the code falls short of the
project's intent ([VISION.md](VISION.md)).

Each entry states what is **shipped today** and what is **not yet built**. None
of the unbuilt work is scheduled or promised here — this is a gap register, not
a roadmap.

Items that [VISION.md](VISION.md) declares out of scope are intentionally
omitted even when SwiftUI exposes a corresponding API.

## Accessibility

**Shipped.** The semantic substrate, the terminal linear renderer,
cursor-follows-focus, the Web/WASI ARIA tree, and the SwiftUI-host overlay that
pushes runtime focus to VoiceOver.

**Not yet built.**

- **Bidirectional focus.** Focus flows runtime → VoiceOver only.
  VoiceOver-originated focus traversal is not fed back into SwiftTUI's runtime
  focus.
- **A WCAG-referenced conformance suite** and **automated screen-reader
  testing.** Accessibility is verified by unit tests and guardrail scripts, not
  by a conformance checklist.

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

## Canvas and drawing

**Shipped.** The continuous coordinate type system (`Point`/`CellPoint`/
`PixelPoint`, `PointerLocation` with sub-cell precision) and the `Canvas`
drawing surface with Braille subpixel rendering.

**Not yet built.** `Canvas`'s internal drawing coordinate model is still the
legacy integer-cell interface; it has not been migrated to the fractional
cell-coordinate model the rest of the geometry system uses.

## Web packaging

**Shipped.** The `@swifttui/web` runtime and `@swifttui/build` helper packages
exist in the repo, and the localhost WebHost works.

**Not yet built.**

- **npm publishing** of `@swifttui/web` and `@swifttui/build` as consumable
  packages with compiled artifacts, type declarations, and CSS entrypoints.
- A **SwiftPM plugin** wrapping the web build flow.
- Localhost-WebHost extensions: a multi-scene host, remote/shared sessions, and
  lifecycle polish such as ephemeral ports, QR-code launch, and server
  discovery.

## Android

**Shipped.** `aarch64` Android cross-compilation with the Swift Android SDK.

**Not yet built.** `x86_64` Android currently fails: the vendored `swift-png`
LZ77/SIMD path imports Intel builtin intrinsics that are unavailable on that
target. Android is a cross-compilation target, not a declared SwiftPM platform.

## Performance

**Shipped.** The `Tools/TermUIPerf` harness records repeatable scenarios and
compares runs from frame diagnostics.

**Not yet built.** The harness does not enforce pass/fail performance budgets;
its runs are comparative measurements, not a gate.

## Project and release

- **`0.9.0` public beta.** The intended next milestone — broadening
  contributors and stabilizing the surface toward `1.0.0` — has not been
  reached. The project is a single-maintainer `0.1.0` alpha.
- **Global documentation linting.** `AllPublicDeclarationsHaveDocumentation` is
  deliberately off. In its place, `generate_public_api_inventory.sh --check`
  runs a report-only ratchet that counts `canonical` public symbols with no
  `///` summary. It does not fail the gate yet; once the count reaches zero,
  flipping `ENFORCE_DOC_COMMENTS` makes it a hard gate. The global rule stays
  off because it would also force low-value comments onto package-only seams.
- **The name.** "SwiftTUI" collides with other terminal-UI projects in the
  Swift ecosystem. Whether to rename the package is unresolved.
- **The `0.0.1` tag.** It predates the release policy and is kept only as a
  historical artifact; it is not a supported entry point.
