# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build                  # Build all targets
swift test                   # Run all tests
swift test --filter TerminalUITests.SwiftUISurfaceTests  # Run a single test suite
swift test --filter TerminalUITests.SwiftUISurfaceTests/testName  # Run a single test
swift format format -i --configuration .swift-format.json Sources/ Tests/  # Format all code
```

## Development Guidelines

- When implementing a new feature that replaces or extends an existing constraint (e.g., single-scene → multi-scene), search for and remove ALL old guards/assertions that enforce the previous constraint.
- When working with this Swift TUI framework, always run the full test suite (`swift test`) after making changes and confirm all tests pass before considering work complete.

## AnyView Policy

- Prefer typed `@ViewBuilder` closures and generic `Content: View` storage.
- Treat `AnyView` as an escape hatch, not as a default container type.
- Do not introduce public APIs that expose `[AnyView]`, builder closures returning `AnyView`, or node-erasure seams.
- If authored content is stored for later evaluation, capture it with `scopedAnyView(...)`, not plain `AnyView(...)`.
- Add a nearby `AnyView policy:` comment when introducing new stored `AnyView`, `[AnyView]`, or closure-returning-`AnyView` members.

## Pre-commit Hooks (prek)

- **swift-format**: Auto-formats staged `.swift` files on commit.
- **no-foundation-in-library-products**: Blocks commits that add `import Foundation` or `public import Foundation` in the Foundation-free `Sources/Core`, `Sources/View`, and `Sources/TerminalUI` library layers.
- **public-surface-policies**: Enforces public surface guardrails, prototype target packaging rules, and the docs that describe that policy.

There is not currently a separate checked-in source-layout hook. Keep
`docs/SOURCE_LAYOUT.md` aligned with file moves in ordinary review.

## Code Style

- 2-space indentation, 100-character line length.
- `private` (not `fileprivate`) for file-scoped declarations.
- Ordered imports. No block comments. No void return on function signatures.
- Full config in `.swift-format.json`.

## Swift Language Settings

- Swift 6.2 with strict memory safety and Swift 6 language mode.
- Upcoming features enabled: `ExistentialAny`, `NonisolatedNonsendingByDefault`, `MemberImportVisibility`, `InternalImportsByDefault`, among others.
- Platforms: macOS 15+, iOS 18+.

## Architecture

### Target Dependency Chain

```
TerminalUI  ->  View  ->  Core
```

- **Core** -- Pure, terminal-IO-free pipeline: geometry, styling, layout engine, semantic extraction, draw extraction, rasterizer, scheduler, commit planner.
- **View** -- SwiftUI-shaped authoring surface: `View` protocol, `@State`/`@Binding`/`@FocusState`, containers (`VStack`, `HStack`, `ZStack`, `ScrollView`, `List`, `Table`), controls (`Button`, `Toggle`, `TextField`, etc.), environment, and focus system.
- **TerminalUI** -- Terminal runtime: `RunLoop`, `TerminalHost`, input parsing, signal handling, alternate-screen management, lifecycle coordination. Re-exports View and Core.
- **TerminalUICharts** -- Separate track for compact chart/metric views (not core roadmap).

Each layer re-exports its dependency via `@_exported import`, so importing `TerminalUI` gives you everything.

### Frame Pipeline

Every render frame flows through seven strict phases:

```
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

- **Resolve**: Public `View` values lowered into `ResolvedNode` tree. Environment merged, structural views (Group, ForEach, conditionals) expand children.
- **Measure**: `LayoutEngine` probes nodes under size proposals. Produces cacheable `MeasuredNode` tree. Parent proposes, child chooses (SwiftUI layout model).
- **Place**: Measured nodes placed into final geometry (`PlacedNode`). Authoritative source for interaction regions and scroll content.
- **Semantics**: Focus regions, action routes, selection routes extracted from placed tree.
- **Draw**: Placed nodes lowered into draw commands (styling, text, shapes, clipping).
- **Raster**: Draw commands converted to 2D cell grid (`RasterSurface`).
- **Commit**: Lifecycle diffs (appear/disappear/task start/cancel), handler packaging.

### Key Design Rules

- **SwiftUI-faithful layout**: Recursive parent-child negotiation, not global constraint solving. Modifier order matters.
- **No terminal I/O in Core**: All terminal interaction is isolated to TerminalUI.
- **Incremental rendering**: Measurement cache, retained layout sessions, cursor-addressed presentation updates. A second idle frame should reuse all work and write zero bytes.
- **State keyed by identity path + source location**: `@State` persistence uses view identity in the tree, not reference identity.

## Test Organization

Tests are now split by layer:

- `Tests/CoreTests/` -- pipeline, layout, raster, and focus infrastructure
- `Tests/ViewTests/` -- authoring-surface, environment, and actor-isolation behavior
- `Tests/TerminalUITests/` -- runtime, rendering, fixtures, and end-to-end behavioral coverage
- `Runners/TerminalUICLI/Tests/TerminalUICLITests/` -- terminal-native runner, socket, pty, attach, and CLI-scene-management behavior
- `Runners/TerminalUIWASI/Tests/TerminalUIWASITests/` -- WASI runner and manifest-mode behavior
- `Tests/PrototypeUIComponentsTests/` -- prototype-surface regression coverage

Repository-shape and policy regressions that do not require execution are enforced in `prek`
hooks under `Scripts/`.

Rendered-text fixture matrix completeness is currently verified in the Swift
test suite rather than through a separate pre-commit hook.

Fixture updates require explanation when they cross unrelated subsystems or alter previously-stable scenarios. See `docs/TESTING_AND_FIXTURE_POLICY.md`.

## Documentation

Detailed design docs live in `/docs/`:
- `ARCHITECTURE.md` -- target boundaries and pipeline
- `RUNTIME.md` -- lifecycle, task semantics, incremental rendering model
- `SOURCE_LAYOUT.md` -- per-file ownership map
- `PUBLIC_API_INVENTORY.md` -- public surface classification
- `PUBLIC_SURFACE_POLICY.md` -- public API governance rules, including `AnyView` and type-erasure policy
- `FOCUS.md` -- focus system design
- `VISION.md` -- project philosophy and scope
