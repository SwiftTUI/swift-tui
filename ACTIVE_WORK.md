# Active Work

## Rules

- Keep this document up to date whenever active tasks are added, completed, or
  re-scoped.
- Include only work that is not yet completed.
- Use concise task descriptions with links to supporting docs, plans, source
  files, or tests.
- Remove completed work from this document entirely.
- When removing completed work, add a concise self-standing entry to
  [CHANGELOG.md](CHANGELOG.md). Keep long-form details in the supporting docs,
  plans, source, or tests.
- Changelog entries may link to long-lived repo documentation, but every link
  must be prefixed with the short git hash that anchors the referenced material,
  for example: `4ee7a8f9 [docs/STATUS.md](docs/STATUS.md)`.
- Treat this file as additive to the repo documentation structure. It does not
  replace durable docs, proposals, ADRs, plans, or tests.
- Use this file as the first place to check what is next.

## Runtime And Public Surface Gaps

- [ ] Re-scope the remaining `AnyView` / `[AnyView]` reduction before more
  implementation. Current production erasure is concentrated in the builder
  backbone; the next step needs an explicit choice between a typed structural
  builder migration and retained compatibility seams. Supporting docs and
  source:
  [docs/proposals/TYPE_ERASURE_DEFERRAL_PLAN.md](docs/proposals/TYPE_ERASURE_DEFERRAL_PLAN.md),
  [docs/ANYVIEW_INTERNALS.md](docs/ANYVIEW_INTERNALS.md),
  [Sources/SwiftTUIViews/Foundation/ViewFoundation.swift](Sources/SwiftTUIViews/Foundation/ViewFoundation.swift),
  [Sources/SwiftTUIViews/ViewBuilder/TupleView.swift](Sources/SwiftTUIViews/ViewBuilder/TupleView.swift),
  [Sources/SwiftTUIViews/ViewBuilder/ConditionalContentView.swift](Sources/SwiftTUIViews/ViewBuilder/ConditionalContentView.swift),
  [Sources/SwiftTUIViews/ViewBuilder/VariadicView.swift](Sources/SwiftTUIViews/ViewBuilder/VariadicView.swift).
  Ambiguity note: leave this active but do not implement it now. Do not
  continue by mechanically removing erasure; choose a migration direction for
  retained builders first.
- [ ] Turn the current constraints in `docs/STATUS.md` into executable plans or
  explicitly defer them: default-focus scopes, `@FocusedObject`, richer
  `TextEditor`, `NavigationStack`, popover-style presentation, terminal
  workspaces, deeper scroll control, and navigation surfaces. Supporting docs:
  [docs/STATUS.md](docs/STATUS.md),
  [docs/VISION.md](docs/VISION.md),
  [docs/FOCUS.md](docs/FOCUS.md).
  Ambiguity note: park this for later investigation. Some listed constraints
  may already be obsolete, so this remains a prioritization pass rather than a
  single implementation task.

## Canvas And Pointer Work

- [ ] Close the decision-bound leftovers from the fractional-coordinate
  inventory. Core pointer plumbing, host precision, terminal 1016, Canvas
  grids, GIF editor Canvas interaction, slider/scroll precision, chart
  conversion helpers, hover, drop context, content shapes, and named coordinate
  spaces are already present. Remaining choices need product/API decisions
  before implementation: `PointerPath` sample-cap policy, public `Canvas`
  closure-authoring support, `.pixelExact` availability before a graphics
  renderer exists, and whether to add a new standalone Canvas example.
  Ambiguity note: prior implementation already landed the core pointer and
  fractional-coordinate plumbing, so this is not a catch-up checklist. Treat the
  remaining bullets as product/API design choices and do not blindly execute the
  old phase checklist.
  Supporting docs and source:
  [docs/plans/2026-04-28-001-canvas-adaptation-plan.md](docs/plans/2026-04-28-001-canvas-adaptation-plan.md),
  [docs/plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md](docs/plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md),
  [Sources/SwiftTUI/Input/InputReader.swift](Sources/SwiftTUI/Input/InputReader.swift),
  [Sources/SwiftTUIViews/Canvas.swift](Sources/SwiftTUIViews/Canvas.swift),
  [Tests/SwiftTUICoreTests/Pointer](Tests/SwiftTUICoreTests/Pointer),
  [Tests/SwiftTUICoreTests/CanvasGridTests.swift](Tests/SwiftTUICoreTests/CanvasGridTests.swift).
