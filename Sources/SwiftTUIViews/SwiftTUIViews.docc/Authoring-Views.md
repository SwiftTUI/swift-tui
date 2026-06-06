# Authoring Views

## Overview

Use the `SwiftTUIViews` module the same way you would approach a small SwiftUI
feature: compose containers, local state, focused controls, and modifiers around
a body-driven tree.

The main difference is that SwiftTUI eventually renders into a cell surface instead of a pixel buffer. That means you should think in terms of:

- integer cell sizes for layout, with continuous cell-space points reserved for
  input, drawing, and interpolation
- text width and wrapping rather than arbitrary text bounds
- keyboard-first focus and selection
- terminal-safe incremental updates instead of animation-heavy transitions

## Actor Isolation

SwiftTUI now follows SwiftUI-style actor isolation for authored view trees.

- `View` bodies are `@MainActor`
- `Resolver.resolve(...)` and `DefaultRenderer.render(...)` evaluate view trees on the main actor
- `Binding.init(get:set:)` requires explicitly `@MainActor` get/set closures, `.task(...)` inherits the current actor context, and button actions, `.onAppear`, `.onDisappear`, and `.onChange(of:initial:_:)` stay explicitly `@MainActor`
- because `View.body` itself is `@MainActor`, ordinary authored view code still uses those APIs from the main actor

The pure `SwiftTUICore` pipeline remains nonisolated. If you need off-main
inspection, move to already-resolved or already-rendered pipeline artifacts
rather than evaluating a fresh `View` tree off the main actor.

## Containers And Controls

The core container and control surface is already broad enough for many dashboards, forms, and editor-like flows:

- stacks, sections, scroll views, lists, outline groups, and tables
- text, labels, group boxes, control groups, and shapes
- buttons, toggles, steppers, sliders, pickers, disclosure groups, and text fields

Use built-in containers first. Reach for custom ``Layout`` only when the authored structure genuinely has a reusable layout rule that stacks and frames cannot express clearly.

## Type Erasure

Prefer typed `@ViewBuilder` composition, `some View` helpers, and generic
`Content: View` storage. Use ``AnyView`` only at deliberate boundaries where a
call site must store or transport heterogeneous view values.

`AnyView` participates in the retained graph, but it still hides concrete
structure from the surrounding API. State that must survive a change between
different erased payload types should be owned above the erased boundary and
passed down through bindings or model references.

## Modifiers

Most familiar modifier categories are available:

- layout modifiers such as padding, frame, spacing, fixed-size, and clipping
- style modifiers such as foreground style, tint, blend mode, compositing
  groups, and disabled state
- identity modifiers such as `.id(_:)`, which accepts any `Hashable` value and
  scopes it under the view's current tree position
- focus modifiers such as `.focused(...)`, `.defaultFocus(...)`, and `.focusEffectDisabled()`
- pointer modifiers such as gestures, `.contentShape(...)`, named coordinate
  spaces, and `.onPointerHover(...)`
- environment modifiers such as `.environment(...)` and `.transformEnvironment(...)`
- lifecycle modifiers such as `.onAppear`, `.onDisappear`, `.onChange(of:initial:_:)`, and `.task(...)`

Modifiers are first-class public API through `ViewModifier`,
`View.modifier(_:)`, and `ModifiedContent`. Direct lowering hooks remain
package-only; ordinary call sites should stay on the modifier surface.

Blend modifiers follow SwiftUI ordering. Use `.blendMode(_:)` when a subtree's
cell writes should blend with the current backdrop as they stream through the
rasterizer. Add `.compositingGroup()` when the subtree should first flatten into
one terminal-cell layer before later effects, such as an outer blend mode, are
applied.

Image attachments follow the same ordering for decodable PNG/JPEG sources. When
an `Image` has an active blend mode, hosts receive a precomposed image variant
blended against the visible cell-background backdrop; unblended images keep the
normal high-fidelity attachment path. `AnimatedImage` frames rendered through
`Image(data:)` inherit this behavior. This first tranche blends against cell
background colors, not glyph-shaped text, overlapping image layers, or GIF
pass-through bytes.

## Preview And Inspection

When you want to inspect authored output without running a full terminal
session, use ``Resolver`` from `SwiftTUIViews`, or the higher-level
`DefaultRenderer` type from `SwiftTUIRuntime` or `SwiftTUI`, from the main actor
to produce resolved trees, frame artifacts, or rendered terminal text.

See also:

- <doc:Pointer-And-Canvas>
- <doc:State-Environment-And-Focus>
- ``AnyView``
- ``Resolver``
