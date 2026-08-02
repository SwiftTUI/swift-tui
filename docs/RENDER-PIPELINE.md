# Render Pipeline

This file keeps older maintainer links working.

Developers can find the render pipeline documentation in DocC:

- `Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md`
  explains the runtime call path, `RunLoop`, `DefaultRenderer`, stage scheduling,
  commit policy, diagnostics, and host handoff.
- `Sources/SwiftTUICore/SwiftTUICore.docc/Rendering-Pipeline.md` explains the
  phase-product model. Its stages are resolve, measure, place, semantics, draw,
  raster, and commit.

Keep implementation guides in DocC. Use this package's `docs/` folder for
internal project notes, maintainer references, and generated policy artifacts.
