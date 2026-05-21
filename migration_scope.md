# Humanization Scope: Last Five Commits

Date: 2026-05-21

## Approved Scope

Review and improve readability for the contents of the latest five commits on
`main`:

- `adbdc882 Add compositing groups for blend modes`
- `bd0ac983 Merge branch 'claude-load'`
- `ec439dc5 Merge branch 'blend-mode'`
- `07af2706 basic blend mode`
- `ff72cc63 prek --all-files`

The active code scope is the blend/compositing implementation and adjacent
raster helpers it depends on:

- `Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift`
- `Sources/SwiftTUICore/Raster/Rasterizer+Sampling.swift`
- `Sources/SwiftTUICore/Draw/DrawEffects.swift`
- `Sources/SwiftTUIViews/Modifiers/StyleModifiers.swift`
- `Sources/SwiftTUIViews/Modifiers/ViewMetadataModifiers.swift`
- Blend/compositing tests in `Tests/SwiftTUICoreTests/`,
  `Tests/SwiftTUIViewsTests/`, and `Tests/SwiftTUITests/`

## Stable Interfaces and Behavior

- Public API remains stable: `.blendMode(_:)` and `.compositingGroup()` keep the
  same signatures and modifier-order behavior.
- Raster behavior remains stable for streaming blend modes, grouped
  compositing, nested groups, clipping, image attachments, wide glyph
  continuations, and post-child inset border ordering.
- No public symbol, fixture, or rendered output change is intentional.

## Non-goals

- Do not broaden into repo-wide formatting from `ff72cc63`.
- Do not redesign the rasterizer storage model or layer allocation strategy.
- Do not change blend math, color spaces, or terminal image attachment behavior.
- Do not alter unrelated gallery, chart, CLI, Web, or example-package code.

## Risk Register

- Medium: compositing groups sit in the core raster path; validate with focused
  raster and public surface tests, then the repo gate.
- Low: public-surface test helper extraction should be compile-only and
  behavior-preserving.

