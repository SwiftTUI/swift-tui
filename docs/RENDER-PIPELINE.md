# Render Pipeline

This file is an internal compatibility pointer for older maintainer links.

Developer-facing render pipeline documentation lives in DocC:

- `Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md`
  covers the runtime callpath, `RunLoop`, `DefaultRenderer`, stage scheduling,
  commit policy, diagnostics, and host handoff.
- `Sources/SwiftTUICore/SwiftTUICore.docc/Rendering-Pipeline.md` covers the
  phase-product model: resolve, measure, place, semantics, draw, raster, and
  commit.

Keep implementation walkthrough content in DocC. Keep this package `docs/`
folder for internal project notes, maintainer references, and generated policy
artifacts.
