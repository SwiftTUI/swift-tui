# Authoring Views

## Overview

Use the `SwiftTUIViews` module like a small SwiftUI feature. Compose containers,
local state, focused controls, and modifiers around a body-driven tree.

SwiftTUI renders into a cell surface instead of a pixel buffer. Use these
concepts:

- integer cell sizes for layout, with continuous cell-space points reserved for
  input, drawing, and interpolation
- text width and wrapping rather than arbitrary text bounds
- keyboard-first focus and selection
- terminal-safe incremental updates instead of animation-heavy transitions

## Actor Isolation

SwiftTUI follows SwiftUI-style actor isolation for authored view trees.

- `View` bodies are `@MainActor`
- `Resolver.resolve(...)` and `DefaultRenderer.render(...)` evaluate view trees on the main actor
- `Binding.init(get:set:)` requires explicit `@MainActor` get and set closures.
- `.task(...)` inherits the current actor context.
- Button actions, `.onAppear`, `.onDisappear`, and
  `.onChange(of:initial:_:)` stay explicitly `@MainActor`.
- `View.body` is `@MainActor`. Thus, ordinary authored view code uses these
  APIs from the main actor.

The pure `SwiftTUICore` pipeline remains nonisolated. If you need off-main
inspection, move to already-resolved or already-rendered pipeline artifacts
rather than evaluating a fresh `View` tree off the main actor.

## Containers And Controls

The core container and control surface supports many dashboards, forms, and
editor-like flows:

- stacks, sections, scroll views, lists, outline groups, and tables
- text, labels, group boxes, control groups, and shapes
- buttons, toggles, steppers, sliders, pickers, disclosure groups, and text fields

Use built-in containers first. Use a custom ``Layout`` only for a reusable
layout rule that stacks and frames cannot express clearly.

Custom ``Layout`` cache values are pass-local scratch state. SwiftTUI shares
``Layout/Cache`` between measurement and placement for one layout pass, then
drops it after placement. The cache is recreated when a later pass runs because
the proposal, child structure, binding-driven content, or another input changed.
Store state that must survive across frames in a model, ``State``, or another
owned value outside the layout cache.

## Type Erasure

Prefer typed `@ViewBuilder` composition, `some View` helpers, and generic
`Content: View` storage. Use ``AnyView`` only at deliberate boundaries where a
call site must store or transport heterogeneous view values.

`AnyView` participates in the retained graph, but it still hides concrete
structure from the surrounding API. Own state above the erased boundary when it
must survive a change between erased payload types. Pass it down through
bindings or model references.

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
package-only. Ordinary call sites must stay on the modifier surface.

Blend modifiers use SwiftUI ordering. Use `.blendMode(_:)` to blend a subtree's
cell writes with the current backdrop. Add `.compositingGroup()` to flatten the
subtree into one terminal-cell layer before later effects apply.

Image attachments follow the same ordering for decodable PNG/JPEG sources. When
an `Image` has an active blend mode, hosts receive a precomposed image variant
blended against the visible cell backdrop. Unblended images keep the normal
high-fidelity attachment path. `AnimatedImage` frames rendered through
`Image(data:)` inherit this behavior because GIF input is decoded into
pre-composed PNG-backed frames first. Raw GIF container bytes passed directly to
`Image(data:)` are different. Web surfaces can pass them through unchanged when
unblended, and SwiftTUI does not decode or blend those GIF containers. The
backdrop includes cell backgrounds and explicit foreground glyphs, with
deterministic coverage approximations for block, braille, and ordinary text.
Shaded block elements are treated as full-cell foreground in this
approximation. It still does not claim exact terminal font masks, overlapping
image-layer blending, or direct GIF byte blending.

## Preview And Inspection

When you want to inspect authored output without a full terminal session, use
the `DefaultRenderer` type from `SwiftTUIRuntime` or `SwiftTUI`. Run it from the
main actor. It produces resolved trees, frame artifacts, or rendered terminal
text.

See also:

- <doc:Collections>
- <doc:Pointer-And-Canvas>
- <doc:State-Environment-And-Focus>
- ``AnyView``
