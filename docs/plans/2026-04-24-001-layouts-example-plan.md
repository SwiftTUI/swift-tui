---
title: "feat: layouts example app & test suite"
type: feature
status: design-approved
date: 2026-04-24
---

# Layouts Example App & Test Suite — Design

> This document is the **design** half of the plan. The task-by-task
> implementation breakdown will be produced by
> `superpowers:writing-plans` in a follow-up commit to this same file
> (Tasks section). The body below is the approved design — it
> describes *what* we are building and *why*, not the step-by-step
> *how*.

## Summary

Add a new sub-package under `Examples/` that is a dedicated layouts
workbench: 56 focused layout examples, each rendered full-screen from a
picker in the app, each covered by at least a smoke test, most covered
by an additional behaviour test that pins the specific
measure/place rule the layout is meant to demonstrate. The goal is
coverage of the tricky corners of TerminalUI's layout surface — stack
alignment, frame clamping, padding/border ordering, `GeometryReader`
gotchas, `ViewThatFits` boundaries, custom `Layout` types, and
cross-component intersections — not a polished showcase.

Finding layout bugs is an explicit outcome of this work: tests pin
the current behaviour as-is, and the design doc calls out entries
where the "correct" answer is not yet known.

## Goals

- **Pin behaviour.** Convert "I think this is what the runtime does"
  into test assertions the CI will keep honest.
- **One file per layout, one source of truth.** Adding a layout is a
  single struct literal in `LayoutCatalog.all`; the picker and the
  parameterised smoke test both read from that list.
- **Full-screen push/pop nav.** Each layout gets the whole viewport so
  edge/overflow/ambiguity behaviours are visible without list chrome
  competing for cells.
- **Smoke floor + behaviour ceiling.** Every layout has a smoke test;
  layouts that encode an ambiguity add a targeted behaviour test.
- **Mirror the `Examples/gallery/` conventions** — same package shape,
  same SPM layout, same test style.

## Non-goals

- Not a polished demo. The UX bar is "the layout is visible and its
  quirks are testable."
- Not a replacement for `Examples/gallery/`. The gallery is a
  component-level demo with tabs, a palette, and a curated surface;
  `Examples/layouts/` is specifically about layout-engine behaviour.
- Not a pixel-golden snapshot suite. Behaviour tests pin named
  invariants (cell positions, measured sizes, truncation survivors),
  not raster diffs.
- Not an animation/RunLoop test suite. Exactly one entry was going to
  need RunLoop coverage; it was cut because there is no RunLoop-free
  way to pin mid-animation raster honestly. The `Examples/gallery/`
  suite already covers RunLoop-driven animation.

## Package shape

```
Examples/layouts/
├── Package.swift
├── README.md
├── Sources/
│   ├── Layouts/              # library — one file per layout
│   │   ├── LayoutEntry.swift     # id, title, category, marker, tier, view factory
│   │   ├── LayoutCatalog.swift   # static `let all: [LayoutEntry]`
│   │   ├── Stacks/               # A
│   │   ├── Frames/               # B
│   │   ├── Padding/              # C
│   │   ├── BordersOverlays/      # D
│   │   ├── OffsetPosition/       # E
│   │   ├── ZStack/               # F
│   │   ├── Spacers/              # G
│   │   ├── Scrolling/            # H
│   │   ├── Geometry/             # I
│   │   ├── ViewThatFits/         # J
│   │   ├── CustomLayout/         # K
│   │   ├── AlignmentGuides/      # L
│   │   ├── Collections/          # M
│   │   ├── ShapesCanvas/         # N
│   │   ├── PresentationLayout/   # O
│   │   └── Matched/              # P
│   └── LayoutsApp/           # executable — picker + detail host
│       └── LayoutsApp.swift
└── Tests/
    └── LayoutsTests/
        ├── CatalogIntegrityTests.swift
        ├── LayoutSmokeTests.swift              # parameterised over LayoutCatalog.all
        ├── PickerShellTests.swift              # picker list resolves with N entries
        └── <Category>/<Layout>BehaviourTests.swift
```

Targets:

- **`Layouts`** (library) — depends on `TerminalUI`, `TerminalUICharts`
  (same as `GalleryDemoViews`).
- **`LayoutsTests`** (test target) — depends on `Layouts` + `TerminalUI`.
- **`LayoutsApp`** (executable target) — depends on `Layouts`,
  `TerminalUI`, `TerminalUICLI`. Executable product named
  `layouts-demo`; `swift run layouts-demo` mirrors
  `swift run gallery-demo`.

Package platforms and Swift settings match `Examples/gallery/Package.swift`
verbatim (macOS 15 / iOS 18, Swift language mode 6, strict memory
safety, the full upcoming-features list from the root package).

## Core types

```swift
public struct LayoutEntry: Identifiable, Hashable, Sendable {
  public let id: String        // stable; e.g. "stacks.hstack-alignment-triad"
  public let category: Category
  public let title: String     // shown in the picker
  public let blurb: String     // one-line "what this demonstrates"
  public let marker: String    // substring guaranteed to appear in the raster
  public let tier: TestTier    // .smoke | .behaviour
  public let makeView: @MainActor () -> AnyView

  public enum Category: String, CaseIterable, Sendable { … }
  public enum TestTier: Sendable { case smoke, behaviour }
}

public enum LayoutCatalog {
  public static let all: [LayoutEntry] = [ /* 56 literals */ ]
  public static func entry(id: String) -> LayoutEntry? { … }
}
```

`makeView` returns `AnyView` (the one AnyView usage, with the required
policy comment per `docs/PUBLIC_SURFACE_POLICY.md`), because the
picker and smoke test want a heterogeneous `[LayoutEntry]`. All 56
entry *implementations* are strongly typed concrete `View`s wrapped at
the catalog literal only.

## App shell

```swift
@main
struct LayoutsApp: App {
  var body: some Scene {
    WindowGroup { LayoutsRoot() }
  }
}

struct LayoutsRoot: View {
  @State private var selectedID: LayoutEntry.ID?
  var body: some View {
    if let id = selectedID, let entry = LayoutCatalog.entry(id: id) {
      LayoutDetailHost(entry: entry, onBack: { selectedID = nil })
    } else {
      LayoutPicker(onSelect: { selectedID = $0 })
    }
  }
}
```

- **Picker**: `List` with sections per `Category`. Row displays
  `title` + `blurb`. Enter on a row sets `selectedID`. Footer reminds:
  `↑↓ move · ⏎ open · ⌃C quit`.
- **Detail**: renders `entry.makeView()` full-screen, 1-row footer
  `esc back · ⌃C quit · <category>/<title>`. Esc handler attached via
  `.keyCommand(.escape, action: onBack)` at the detail host level.
- **Esc semantics**: Framework Esc dismisses presentations first
  (memory: `project_presentation_escape_dismiss.md`). Detail host
  never owns a sheet, so its Esc is unambiguous. Individual layouts
  that demo presentations (e.g. #54) own their own Esc internally.

## Test strategy

### Tier 0 — catalog integrity (1 file, ~3 tests)

- All `id`s unique.
- All `title`/`blurb`/`marker` non-empty.
- Every `Category` case is represented.

### Tier 1 — smoke (1 parameterised test, 56 invocations)

```swift
@Suite @MainActor
struct LayoutSmokeTests {
  @Test("Every catalog entry resolves and rasterises",
        arguments: LayoutCatalog.all)
  func rasterisesNonEmpty(entry: LayoutEntry) {
    let size = Size(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = size
    let artifacts = DefaultRenderer().render(
      entry.makeView(),
      context: .init(
        identity: Identity(components: [.named("layout-smoke-\(entry.id)")]),
        environmentValues: env
      ),
      proposal: .init(width: size.width, height: size.height)
    )
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(artifacts.rasterSurface.lines.contains { !$0.isEmpty })
    #expect(
      artifacts.rasterSurface.lines.joined(separator: "\n").contains(entry.marker),
      "entry \(entry.id) did not paint its marker '\(entry.marker)'"
    )
  }
}
```

Pattern copied from
`Examples/gallery/Tests/GalleryDemoViewsTests/BordersAndShapesTabTests.rendersNonEmptySurface`.

### Tier 2 — behaviour (one file per `.behaviour` entry)

Location: `Tests/LayoutsTests/<Category>/<Title>BehaviourTests.swift`.
Each file contains 1–3 `@Test` functions with focused assertions on
the invariant the entry is meant to pin. Examples:

- Render at two different proposals; compare measured widths/positions.
- Assert a specific glyph lands at a specific cell (hit a known
  marker at a known `(row, col)`).
- Assert a cell that should be empty *is* empty (clip, overflow).
- Render before/after a state change; diff two rasters.

All Tier 2 tests are single-render or two-render. No RunLoop.

### Tier 3 — picker shell (1 file)

- Picker resolves with a non-empty raster containing the first
  entry's title.
- Picker renders all `Category.allCases` section headers.

## Layout taxonomy (56 entries)

Tier: **S** = smoke only, **B** = smoke + behaviour file.
ID convention: `<category>.<kebab-title>`.

### A — Stack fundamentals (5)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 1 | HStackAlignmentTriad | `.top`/`.center`/`.bottom` with mixed-height children | B |
| 2 | VStackSpacingVsPadding | spacing-between vs padding-around | S |
| 3 | ZStackAlignmentGrid | 9 alignment cells, anchor per corner | B |
| 4 | HStackPriorityTug | `layoutPriority` 0/1/0 under squeeze | B |
| 5 | VStackLeadingGuideShift | one row's leading edge shifted via `alignmentGuide` | B |

### B — Frame & sizing (8)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 6 | FrameFixedInsideUnbounded | fixed frame in infinite vs tight parent | S |
| 7 | FlexibleFrameAlignmentGrid | 9× `.frame(maxWidth:.infinity, maxHeight:.infinity, alignment:)` | B |
| 8 | FixedSizeText | narrow parent + `.fixedSize()` → content escapes | B |
| 9 | FixedSizeOneAxis | `.fixedSize(horizontal: false, vertical: true)` | B |
| 10 | MinIdealMaxFrameClamp | clamp points under 3 proposals | B |
| 11 | LayoutPriorityCascade | priorities 0/1/0/2, drop order | B |
| 12 | ProposalTightening | `.frame(width:30)` caps inner `GeometryReader` proxy | B |
| 13 | IntrinsicTextUnderZeroProposal | Text at `0×0` proposal | B |

### C — Padding, insets, safe areas (4)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 14 | AsymmetricPaddingInsets | `EdgeInsets(0, 4, 2, 0)` | S |
| 15 | PaddingBorderOrdering | `.padding.border` vs `.border.padding` | B |
| 16 | SafeAreaInsetBottomBar | bar pinned bottom; inner proposal reduced | B |
| 17 | IgnoresSafeAreaBleed | content paints through the bar zone | B |

### D — Borders, overlays, backgrounds (6)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 18 | BackgroundVsOverlayPaintOrder | overlay wins at collisions | B |
| 19 | NestedBorderOrdering | two concentric rings at known offsets | B |
| 20 | PerSideBorderColors | `BorderEdgeStyle` 4-color | B |
| 21 | BorderBlendStaticPhase | phase 0 vs 0.5 (no RunLoop) | B |
| 22 | BackgroundShapeStyleVsContentOverloads | two `.background` overloads | S |
| 23 | OverlayAlignmentBadge | `.overlay(alignment: .bottomTrailing)` | B |

### E — Offset, position, clip (4)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 24 | OffsetPreservesMeasuredSize | siblings don't shift | B |
| 25 | PositionIgnoresLayout | `.position(x,y)` anchor | B |
| 26 | ClippedOverflowCrop | `.clipped()` drops overflow | B |
| 27 | NegativeOffsetEscape | `.offset(x:-2)` without clip | B |

### F — ZStack depth & order (3)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 28 | ZStackPaintOrderOverlap | later paints over earlier | B |
| 29 | ZStackSizedByLargest | stack size = largest child | B |
| 30 | ZStackSpacerNoop | Spacer in ZStack has no size effect | B |

### G — Spacer, Divider (3)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 31 | ThreeSpacerSharing | spacers split residual equally | B |
| 32 | SpacerMinLengthRespected | min honoured under tight proposal | B |
| 33 | DividerOrientationFlip | Divider flips with stack axis | B |

### H — ScrollView (3)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 34 | VerticalScrollMeasuresContent | raster height = proposal, content exceeds | B |
| 35 | HorizontalScrollWithInfiniteChild | `.frame(maxWidth:.infinity)` in H-scroll | B |
| 36 | ScrollViewWithSafeAreaInset | first content row below inset | B |

### I — GeometryReader (3)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 37 | GeometryReaderTakesProposal | proxy size = frame | B |
| 38 | GeometryReaderInHStackHogs | classic "eats everything" gotcha | B |
| 39 | GeometryReaderAnchorCorner | `.position` using proxy.size | B |

### J — ViewThatFits (3)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 40 | ViewThatFitsAxisChoice | 3 variants at 3 widths | B |
| 41 | ViewThatFitsVerticalOnly | `axis: .vertical` height swap | B |
| 42 | ViewThatFitsBoundaryInclusive | exact-threshold rule | B |

### K — Custom Layout / AnyLayout (3)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 43 | FlowLayoutWrap | custom wrap Layout | B |
| 44 | AnyLayoutHVSwap | runtime H↔V swap | B |
| 45 | RadialLayout | polar placement via `place(at:)` | B |

### L — Alignment guides (advanced) (2)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 46 | ColonAlignedForm | custom `HorizontalAlignment` at ":" | B |
| 47 | AlignmentGuideDimensionDependent | `{ d in d.height }` guide | B |

### M — Collections in layouts (3)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 48 | ListInShortFrame | 20-row List in 5-row frame | B |
| 49 | ForEachIdentityReorder | reorder preserves identity | B |
| 50 | TableColumnPrioritization | column compression order | B |

### N — Shape & canvas (3)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 51 | CircleInNonSquareFrame | empty-corner cells | B |
| 52 | CapsuleAxisFlip | wide vs tall Capsule | B |
| 53 | CanvasHonorsClipped | canvas overflow clipped | B |

### O — Presentation × layout (2)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 54 | SheetOverScrollLayout | sheet present doesn't break underlying resolve | S |
| 55 | AlertAnchorStable | underlying top-left stable across alert show/hide | B |

### P — Matched geometry & composition (1)

| # | Title | Demonstrates | Tier |
|---|---|---|---|
| 56 | MatchedGeometryBadgeMove | `matchedGeometryEffect`: before/after measured-position delta | B |

**Category totals:** A5 · B8 · C4 · D6 · E4 · F3 · G3 · H3 · I3 · J3 · K3 · L2 · M3 · N3 · O2 · P1 = **56**.

**Tier totals:** smoke-only: #2, #6, #14, #22, #54 (5 entries). Behaviour: 51 entries.

**Assertion budget estimate:**
- Tier 0 (catalog integrity): ~3
- Tier 1 (smoke parameterised): 56 invocations × ~3 expects = 168 expect calls (1 test function, 56 runs)
- Tier 2 (behaviour): 51 files × ~2 tests × ~2 expects ≈ 200 expect calls
- Tier 3 (picker shell): ~4
- **Total:** ~375 `#expect` calls across ~110 `@Test` functions.

## Risks & open questions

### Layouts that may pin bugs, not behaviour

These entries test invariants whose "correct" answer is not yet
documented and may not match SwiftUI. The test pins *current*
behaviour. If the test fails under a later refactor the first
question should be "did we fix a bug?" not "did we break a test?".

- **#38 GeometryReaderInHStackHogs** — SwiftUI's `GeometryReader`
  greedily takes offered space along both axes. TerminalUI's rule is
  not documented. The test will assert whatever the runtime does at
  time of writing.
- **#42 ViewThatFitsBoundaryInclusive** — SwiftUI's rule at exact
  threshold is "fits" (inclusive). TerminalUI's rule is not verified.
- **#13 IntrinsicTextUnderZeroProposal** — Text sizing under a
  `0×0` proposal is subtle. SwiftUI usually produces a zero-size
  Text; TerminalUI may or may not.
- **#27 NegativeOffsetEscape** — painting at negative cell
  coordinates within a host surface. Whether the raster accepts or
  drops those cells is an implementation detail worth pinning.
- **#30 ZStackSpacerNoop** — ZStack's sizing rule when a child is a
  Spacer. SwiftUI treats Spacer as layout-neutral in ZStack;
  TerminalUI's `ZStackLayout` behaviour needs to be verified.

If any of these turn up a behaviour we'd rather change, we record
the finding as its own file under `docs/proposals/layout/`
(new directory; one file per finding, named for the behaviour under
question — e.g. `docs/proposals/layout/GEOMETRYREADER_IN_HSTACK.md`).
The finding file describes the current behaviour, the rule we think
is correct, and a proposed fix. We do not retro-edit the pinning
test to match an imagined "correct" answer; the fix ships in a
subsequent PR that updates both the runtime and the test together.

### Cross-cutting concerns

- **`AnyView` usage in `LayoutCatalog.all`** — the repo policy
  (`docs/PUBLIC_SURFACE_POLICY.md`) requires a nearby `AnyView policy:`
  comment. The catalog literal will carry that comment justifying the
  heterogeneous collection.
- **Test parallelism** — Swift Testing runs tests in parallel by
  default. Parameterised smoke test is isolated per invocation
  because `DefaultRenderer()` is a fresh instance per call; no shared
  state.
- **RunLoop tests not included** — this suite is single-render. The
  gallery covers RunLoop-driven animation already
  (`BordersAndShapesTabTests.chasingLightSchedulesVisibleRuntimeFrames`).
- **macOS-only runtime** — `TerminalUICLI` declares `.macOS(.v15)`.
  The sub-package will mirror that. Library/test targets build on
  Linux; the `layouts-demo` executable does not.

## Validation checklist

Pre-implementation:
- [x] Design approved by user
- [ ] Spec committed to git

Post-implementation:
- [ ] `swift build` succeeds in `Examples/layouts/`
- [ ] `swift test` succeeds in `Examples/layouts/` (all ~110 test functions)
- [ ] `swift run layouts-demo` launches the picker and the picker
      renders 56 rows across 16 category sections
- [ ] `bun run test` at repo root passes
- [ ] Pre-commit hooks (`swift-format`, `public-surface-policies`)
      pass on the new files
- [ ] `Examples/layouts/README.md` documents run/test invocations
- [ ] Any findings from behaviour tests pinning unexpected behaviour
      are recorded as individual files under `docs/proposals/layout/`

## Out of scope

- Command palette / fuzzy filter in the picker (out of scope; straight
  `List` selection only).
- Animations beyond `BorderBlend` static phase snapshots.
- Integration with `Runners/TerminalUIWASI` — macOS executable only.
- Back-porting any layout finding as a fix in this spec's
  implementation. Findings are logged; fixes go in a subsequent PR.

---

# Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `Examples/layouts/` — a sub-package with three targets
(`Layouts` library, `LayoutsTests` test target, `LayoutsApp`
executable) containing 56 focused layout examples reachable from a
full-screen push/pop picker, each covered by a smoke test and (where
`.behaviour`-tagged) a targeted behaviour test.

**Architecture:** Mirror `Examples/gallery/` exactly — SPM sub-package,
platforms `.macOS(.v15)`/`.iOS(.v18)`, Swift 6 language mode, strict
memory safety, same upcoming-features list. Single `LayoutCatalog.all`
literal drives both the picker list and a parameterised smoke test so
adding a layout is one struct literal and "forgot to wire it up" is
impossible. App shell is a two-state `@State var selectedID:
LayoutEntry.ID?` — nil → picker, non-nil → detail host. Esc at the
detail host pops selection back to nil.

**Tech Stack:** Swift 6.3 strict concurrency, Swift Testing (`@Test` /
`#expect`), `@MainActor`-isolated view and test code, `@testable
import Layouts` in tests. Depends on `TerminalUI`,
`TerminalUICharts`, and `TerminalUICLI` (same as
`Examples/gallery/`). macOS executable only; library + tests build on
Linux.

**Reference APIs used throughout (read these once before Task 8):**

- `DefaultRenderer()` + `.render(_:context:proposal:)` →
  `Sources/TerminalUI/TerminalUI.swift:45-124`
- `ResolveContext(identity:environmentValues:...)` →
  `Sources/View/Environment/Environment.swift:260`
- `Identity(components: [.named("...")])` →
  `Sources/Core/GeometryTypes.swift:549`
- `ProposedSize(width: Int?, height: Int?)` →
  `Sources/Core/GeometryTypes.swift:716`
- `Size(width:height:)` → `Sources/Core/GeometryTypes.swift:638`
- `FrameArtifacts.rasterSurface` (`.cells`, `.lines`) →
  `Sources/Core/CommitAndFrameTypes.swift:840` +
  `Sources/Core/RasterTypes.swift:65`
- `WindowGroup { content }` / `App` / `Scene` →
  `Sources/TerminalUI/App.swift:19-462`
- `.panel(id:)` ActionScope wrapper →
  `Sources/View/ActionScopes/Panel.swift:78`
- Gallery reference test pattern →
  `Examples/gallery/Tests/GalleryDemoViewsTests/BordersAndShapesTabTests.swift`

---

## File Structure

### New files — library (`Sources/Layouts/`)

| File | Responsibility |
|------|----------------|
| `LayoutEntry.swift` | Public `LayoutEntry` struct + `Category` + `TestTier` enums. One `AnyView`-returning factory per entry (the single justified `AnyView` use, with policy comment). |
| `LayoutCatalog.swift` | `public enum LayoutCatalog { public static let all: [LayoutEntry] = [...] }` — 56 literal entries. Plus `static func entry(id: String) -> LayoutEntry?`. |
| `Stacks/HStackAlignmentTriad.swift` | Layout #1 |
| `Stacks/VStackSpacingVsPadding.swift` | Layout #2 |
| `Stacks/ZStackAlignmentGrid.swift` | Layout #3 |
| `Stacks/HStackPriorityTug.swift` | Layout #4 |
| `Stacks/VStackLeadingGuideShift.swift` | Layout #5 |
| `Frames/FrameFixedInsideUnbounded.swift` | Layout #6 |
| `Frames/FlexibleFrameAlignmentGrid.swift` | Layout #7 |
| `Frames/FixedSizeText.swift` | Layout #8 |
| `Frames/FixedSizeOneAxis.swift` | Layout #9 |
| `Frames/MinIdealMaxFrameClamp.swift` | Layout #10 |
| `Frames/LayoutPriorityCascade.swift` | Layout #11 |
| `Frames/ProposalTightening.swift` | Layout #12 |
| `Frames/IntrinsicTextUnderZeroProposal.swift` | Layout #13 |
| `Padding/AsymmetricPaddingInsets.swift` | Layout #14 |
| `Padding/PaddingBorderOrdering.swift` | Layout #15 |
| `Padding/SafeAreaInsetBottomBar.swift` | Layout #16 |
| `Padding/IgnoresSafeAreaBleed.swift` | Layout #17 |
| `BordersOverlays/BackgroundVsOverlayPaintOrder.swift` | Layout #18 |
| `BordersOverlays/NestedBorderOrdering.swift` | Layout #19 |
| `BordersOverlays/PerSideBorderColors.swift` | Layout #20 |
| `BordersOverlays/BorderBlendStaticPhase.swift` | Layout #21 |
| `BordersOverlays/BackgroundShapeStyleVsContentOverloads.swift` | Layout #22 |
| `BordersOverlays/OverlayAlignmentBadge.swift` | Layout #23 |
| `OffsetPosition/OffsetPreservesMeasuredSize.swift` | Layout #24 |
| `OffsetPosition/PositionIgnoresLayout.swift` | Layout #25 |
| `OffsetPosition/ClippedOverflowCrop.swift` | Layout #26 |
| `OffsetPosition/NegativeOffsetEscape.swift` | Layout #27 |
| `ZStack/ZStackPaintOrderOverlap.swift` | Layout #28 |
| `ZStack/ZStackSizedByLargest.swift` | Layout #29 |
| `ZStack/ZStackSpacerNoop.swift` | Layout #30 |
| `Spacers/ThreeSpacerSharing.swift` | Layout #31 |
| `Spacers/SpacerMinLengthRespected.swift` | Layout #32 |
| `Spacers/DividerOrientationFlip.swift` | Layout #33 |
| `Scrolling/VerticalScrollMeasuresContent.swift` | Layout #34 |
| `Scrolling/HorizontalScrollWithInfiniteChild.swift` | Layout #35 |
| `Scrolling/ScrollViewWithSafeAreaInset.swift` | Layout #36 |
| `Geometry/GeometryReaderTakesProposal.swift` | Layout #37 |
| `Geometry/GeometryReaderInHStackHogs.swift` | Layout #38 |
| `Geometry/GeometryReaderAnchorCorner.swift` | Layout #39 |
| `ViewThatFits/ViewThatFitsAxisChoice.swift` | Layout #40 |
| `ViewThatFits/ViewThatFitsVerticalOnly.swift` | Layout #41 |
| `ViewThatFits/ViewThatFitsBoundaryInclusive.swift` | Layout #42 |
| `CustomLayout/FlowLayoutWrap.swift` | Layout #43 (includes custom `Layout` type) |
| `CustomLayout/AnyLayoutHVSwap.swift` | Layout #44 |
| `CustomLayout/RadialLayout.swift` | Layout #45 (includes custom `Layout` type) |
| `AlignmentGuides/ColonAlignedForm.swift` | Layout #46 (includes custom `HorizontalAlignment`) |
| `AlignmentGuides/AlignmentGuideDimensionDependent.swift` | Layout #47 |
| `Collections/ListInShortFrame.swift` | Layout #48 |
| `Collections/ForEachIdentityReorder.swift` | Layout #49 |
| `Collections/TableColumnPrioritization.swift` | Layout #50 |
| `ShapesCanvas/CircleInNonSquareFrame.swift` | Layout #51 |
| `ShapesCanvas/CapsuleAxisFlip.swift` | Layout #52 |
| `ShapesCanvas/CanvasHonorsClipped.swift` | Layout #53 |
| `PresentationLayout/SheetOverScrollLayout.swift` | Layout #54 |
| `PresentationLayout/AlertAnchorStable.swift` | Layout #55 |
| `Matched/MatchedGeometryBadgeMove.swift` | Layout #56 |

### New files — executable (`Sources/LayoutsApp/`)

| File | Responsibility |
|------|----------------|
| `LayoutsApp.swift` | `@main struct LayoutsApp: App` + `LayoutsRoot` two-state router. |
| `LayoutPicker.swift` | Picker view: sectioned `List` over `LayoutCatalog.all`, grouped by `Category`. |
| `LayoutDetailHost.swift` | Detail view: renders `entry.makeView()` with footer + Esc keyCommand. |

### New files — tests (`Tests/LayoutsTests/`)

| File | Responsibility |
|------|----------------|
| `CatalogIntegrityTests.swift` | ID uniqueness, non-empty fields, every `Category` represented. |
| `LayoutSmokeTests.swift` | Parameterised smoke test over `LayoutCatalog.all` (56 invocations). |
| `PickerShellTests.swift` | Picker rasterises with all category section headers visible. |
| `<Category>/<Title>BehaviourTests.swift` | 51 files (one per `.behaviour` entry). |

### New files — package root

| File | Responsibility |
|------|----------------|
| `Examples/layouts/Package.swift` | SPM manifest with three targets. |
| `Examples/layouts/README.md` | How to run + test, one paragraph each. |

---

## Task 1: Package scaffolding

**Files:**
- Create: `Examples/layouts/Package.swift`
- Create: `Examples/layouts/README.md`
- Create: `Examples/layouts/Sources/Layouts/.gitkeep`
- Create: `Examples/layouts/Sources/LayoutsApp/.gitkeep`
- Create: `Examples/layouts/Tests/LayoutsTests/.gitkeep`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "layouts-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "layouts-demo",
      targets: ["LayoutsApp"]
    ),
    .library(
      name: "Layouts",
      targets: ["Layouts"]
    ),
  ],
  dependencies: [
    .package(name: "swift-terminal-ui", path: "../.."),
    .package(path: "../../Runners/TerminalUICLI"),
  ],
  targets: [
    .executableTarget(
      name: "LayoutsApp",
      dependencies: [
        "Layouts",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICLI", package: "TerminalUICLI"),
      ]
    ),
    .target(
      name: "Layouts",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ]
    ),
    .testTarget(
      name: "LayoutsTests",
      dependencies: [
        "Layouts",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
      ]
    ),
  ]
)
```

- [ ] **Step 2: Write `README.md`**

````markdown
# Layouts Example

56 focused layout examples of the public `TerminalUI` surface,
reachable from a full-screen push/pop picker. Each layout is pinned
with a smoke test; `.behaviour`-tagged layouts add targeted
behaviour tests that pin the specific measure/place rule the layout
is meant to demonstrate.

Design and taxonomy live in
[../../docs/plans/2026-04-24-001-layouts-example-plan.md](../../docs/plans/2026-04-24-001-layouts-example-plan.md).

## Run

```bash
cd Examples/layouts
swift run layouts-demo
```

The app launches directly into the picker. `↑↓` move, `⏎` opens a
layout, `esc` pops back, `⌃C` quits.

## Test

```bash
cd Examples/layouts
swift test
```
````

- [ ] **Step 3: Create the three empty source directories**

Run:

```bash
mkdir -p Examples/layouts/Sources/Layouts
mkdir -p Examples/layouts/Sources/LayoutsApp
mkdir -p Examples/layouts/Tests/LayoutsTests
touch Examples/layouts/Sources/Layouts/.gitkeep
touch Examples/layouts/Sources/LayoutsApp/.gitkeep
touch Examples/layouts/Tests/LayoutsTests/.gitkeep
```

- [ ] **Step 4: Verify SPM resolves**

Run: `cd Examples/layouts && swift build`
Expected: build fails with "no Swift source files in target" — that is
OK; it proves SPM resolved the dependencies and found every target
directory. Do not try to build further until Task 2 lands real code.

- [ ] **Step 5: Commit**

```bash
git add Examples/layouts/Package.swift Examples/layouts/README.md \
        Examples/layouts/Sources Examples/layouts/Tests
git commit -m "chore(layouts): scaffold Examples/layouts/ SPM package"
```

---

## Task 2: `LayoutEntry` + `Category` + `TestTier`

**Files:**
- Create: `Examples/layouts/Sources/Layouts/LayoutEntry.swift`

- [ ] **Step 1: Write `LayoutEntry.swift`**

```swift
import TerminalUI

/// Metadata + factory for one layout example.
///
/// One `LayoutEntry` literal per layout is added to
/// ``LayoutCatalog/all``. The app picker reads the catalog to render
/// the list of entries and to open one full-screen; the parameterised
/// ``LayoutSmokeTests`` iterates the same catalog so "added a layout
/// but forgot to wire it up" is not possible.
///
/// AnyView policy: `makeView` must return `AnyView` because the
/// catalog is a heterogeneous `[LayoutEntry]`. The concrete view per
/// layout is still a strongly-typed `struct`; the erasure happens
/// at the catalog literal only (`AnyView(ConcreteLayout())`).
/// See `docs/PUBLIC_SURFACE_POLICY.md` for the AnyView policy.
public struct LayoutEntry: Identifiable, Hashable, Sendable {
  public let id: String
  public let category: Category
  public let title: String
  public let blurb: String
  public let marker: String
  public let tier: TestTier
  public let makeView: @MainActor @Sendable () -> AnyView

  public init(
    id: String,
    category: Category,
    title: String,
    blurb: String,
    marker: String,
    tier: TestTier,
    makeView: @escaping @MainActor @Sendable () -> AnyView
  ) {
    self.id = id
    self.category = category
    self.title = title
    self.blurb = blurb
    self.marker = marker
    self.tier = tier
    self.makeView = makeView
  }

  public static func == (lhs: LayoutEntry, rhs: LayoutEntry) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

extension LayoutEntry {
  public enum Category: String, CaseIterable, Sendable, Hashable {
    case stacks = "Stacks"
    case frames = "Frames & Sizing"
    case padding = "Padding & Safe Area"
    case bordersOverlays = "Borders & Overlays"
    case offsetPosition = "Offset · Position · Clip"
    case zStack = "ZStack"
    case spacers = "Spacers & Dividers"
    case scrolling = "Scrolling"
    case geometry = "GeometryReader"
    case viewThatFits = "ViewThatFits"
    case customLayout = "Custom Layout"
    case alignmentGuides = "Alignment Guides"
    case collections = "Collections"
    case shapesCanvas = "Shapes & Canvas"
    case presentationLayout = "Presentation × Layout"
    case matched = "Matched Geometry"
  }

  public enum TestTier: Sendable, Hashable {
    case smoke
    case behaviour
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd Examples/layouts && swift build`
Expected: fails with "no targets" on `Layouts` (still no members of
the catalog) — but `LayoutEntry.swift` itself compiles. If you see a
Swift syntax error on `LayoutEntry.swift`, fix it now.

- [ ] **Step 3: Commit**

```bash
git add Examples/layouts/Sources/Layouts/LayoutEntry.swift
git commit -m "feat(layouts): add LayoutEntry + Category + TestTier"
```

---

## Task 3: `LayoutCatalog` (empty scaffold)

**Files:**
- Create: `Examples/layouts/Sources/Layouts/LayoutCatalog.swift`

- [ ] **Step 1: Write `LayoutCatalog.swift` with an empty `all`**

```swift
/// Source-of-truth list of every layout in the Layouts example app.
///
/// The app picker iterates this to render the list; the parameterised
/// smoke test iterates it to prove every entry resolves. Adding a
/// layout is one struct literal in ``all`` — do not introduce any
/// other registration seam.
public enum LayoutCatalog {
  /// All 56 layouts, in picker display order.
  ///
  /// Entries are appended as their underlying layout file lands;
  /// the list is deliberately sparse during the mid-implementation
  /// phase of the plan. `LayoutCatalog` is complete once 56 entries
  /// are listed and `CatalogIntegrityTests.entries_coverAllCategories`
  /// passes.
  public static let all: [LayoutEntry] = []

  public static func entry(id: String) -> LayoutEntry? {
    all.first { $0.id == id }
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd Examples/layouts && swift build --target Layouts`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Examples/layouts/Sources/Layouts/LayoutCatalog.swift
git commit -m "feat(layouts): add empty LayoutCatalog"
```

---

## Task 4: Catalog integrity tests

**Files:**
- Create: `Examples/layouts/Tests/LayoutsTests/CatalogIntegrityTests.swift`

- [ ] **Step 1: Write the integrity tests**

```swift
import Testing

@testable import Layouts

@Suite
struct CatalogIntegrityTests {
  @Test("All catalog IDs are unique")
  func ids_areUnique() {
    let ids = LayoutCatalog.all.map(\.id)
    let unique = Set(ids)
    #expect(ids.count == unique.count, "duplicate IDs: \(ids)")
  }

  @Test("All entries have non-empty title, blurb, and marker")
  func entries_haveRequiredFields() {
    for entry in LayoutCatalog.all {
      #expect(!entry.title.isEmpty, "entry \(entry.id) has empty title")
      #expect(!entry.blurb.isEmpty, "entry \(entry.id) has empty blurb")
      #expect(!entry.marker.isEmpty, "entry \(entry.id) has empty marker")
    }
  }

  @Test("Every Category case is represented by at least one entry")
  func entries_coverAllCategories() {
    let represented = Set(LayoutCatalog.all.map(\.category))
    let missing = Set(LayoutEntry.Category.allCases).subtracting(represented)
    #expect(
      missing.isEmpty,
      "categories with no entries: \(missing.map(\.rawValue).sorted())"
    )
  }

  @Test("entry(id:) returns the matching entry")
  func lookup_returnsMatch() {
    guard let first = LayoutCatalog.all.first else {
      return  // empty catalog is valid during early plan tasks
    }
    #expect(LayoutCatalog.entry(id: first.id)?.id == first.id)
    #expect(LayoutCatalog.entry(id: "::not-a-real-id::") == nil)
  }
}
```

- [ ] **Step 2: Run the tests**

Run: `cd Examples/layouts && swift test --filter LayoutsTests.CatalogIntegrityTests`
Expected:
- `ids_areUnique` PASS (empty catalog → empty set, count matches)
- `entries_haveRequiredFields` PASS (empty loop trivially holds)
- `entries_coverAllCategories` **FAIL** — every category is "missing"
- `lookup_returnsMatch` PASS (early-return on empty)

The `entries_coverAllCategories` failure is the expected red state
that unblocks Task 9 onward — once the catalog is fully populated at
the end of Task 24 it turns green.

- [ ] **Step 3: Commit**

```bash
git add Examples/layouts/Tests/LayoutsTests/CatalogIntegrityTests.swift
git commit -m "test(layouts): add catalog integrity tests (coverAllCategories red)"
```

---

## Task 5: `LayoutPicker` view

**Files:**
- Create: `Examples/layouts/Sources/LayoutsApp/LayoutPicker.swift`

- [ ] **Step 1: Write `LayoutPicker.swift`**

```swift
import Layouts
import TerminalUI

/// Full-screen picker: a sectioned list of every ``LayoutEntry`` in
/// ``LayoutCatalog/all``, grouped by ``LayoutEntry/Category``.
/// Selecting an entry calls `onSelect` with its ID; the parent
/// ``LayoutsRoot`` flips into the detail host.
struct LayoutPicker: View {
  let onSelect: (LayoutEntry.ID) -> Void

  @State private var selection: LayoutEntry.ID?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      List(selection: $selection) {
        ForEach(LayoutEntry.Category.allCases, id: \.rawValue) { category in
          let entries = LayoutCatalog.all.filter { $0.category == category }
          if !entries.isEmpty {
            Section(category.rawValue) {
              ForEach(entries, id: \.id) { entry in
                row(entry)
              }
            }
          }
        }
      }
      .listStyle(.plain)
      Divider()
      footer
    }
    .onChange(of: selection) { _, newValue in
      if let id = newValue {
        onSelect(id)
        // Clear selection so returning to the picker doesn't re-open
        // the same entry on the next render.
        selection = nil
      }
    }
    .panel(id: "layouts.picker")
    .keyCommand(
      "Open",
      key: .return,
      action: {
        if let id = selection { onSelect(id); selection = nil }
      }
    )
  }

  private func row(_ entry: LayoutEntry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(entry.title).foregroundStyle(.foreground)
      Text(entry.blurb).foregroundStyle(.separator)
    }
    .tag(entry.id)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("TerminalUI — Layouts").foregroundStyle(.foreground)
      Text("\(LayoutCatalog.all.count) layouts across \(LayoutEntry.Category.allCases.count) categories")
        .foregroundStyle(.separator)
    }
    .padding(.horizontal, 1)
  }

  private var footer: some View {
    Text("↑↓ move  ·  ⏎ open  ·  ⌃C quit").foregroundStyle(.muted)
      .padding(.horizontal, 1)
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd Examples/layouts && swift build --target LayoutsApp`
Expected: fails — `LayoutsApp.swift` doesn't exist yet. What matters
is that `LayoutPicker.swift` itself has no errors. If Swift reports
errors from inside `LayoutPicker.swift`, fix them now.

- [ ] **Step 3: Commit**

```bash
git add Examples/layouts/Sources/LayoutsApp/LayoutPicker.swift
git commit -m "feat(layouts): add LayoutPicker (sectioned list over catalog)"
```

---

## Task 6: `LayoutDetailHost` view

**Files:**
- Create: `Examples/layouts/Sources/LayoutsApp/LayoutDetailHost.swift`

- [ ] **Step 1: Write `LayoutDetailHost.swift`**

```swift
import Layouts
import TerminalUI

/// Full-screen detail host for one ``LayoutEntry``. Renders
/// `entry.makeView()` occupying the body, with a 1-row footer and an
/// Esc key command that calls `onBack`.
///
/// The host deliberately owns no sheet / alert / other presentation
/// seam; individual layouts that demo presentations own their own Esc
/// handling. See `project_presentation_escape_dismiss.md`.
struct LayoutDetailHost: View {
  let entry: LayoutEntry
  let onBack: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      entry.makeView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      Text("esc back  ·  ⌃C quit  ·  \(entry.category.rawValue) / \(entry.title)")
        .foregroundStyle(.muted)
        .padding(.horizontal, 1)
    }
    .panel(id: "layouts.detail.\(entry.id)")
    .keyCommand(
      "Back",
      key: .escape,
      action: onBack
    )
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd Examples/layouts && swift build --target LayoutsApp`
Expected: still fails (no `@main`). Again, only `LayoutDetailHost.swift`
needs to be error-free.

- [ ] **Step 3: Commit**

```bash
git add Examples/layouts/Sources/LayoutsApp/LayoutDetailHost.swift
git commit -m "feat(layouts): add LayoutDetailHost (full-screen entry host + esc)"
```

---

## Task 7: `LayoutsApp` entry point

**Files:**
- Create: `Examples/layouts/Sources/LayoutsApp/LayoutsApp.swift`

- [ ] **Step 1: Write `LayoutsApp.swift`**

```swift
import Layouts
import TerminalUI
import TerminalUICLI

@main
struct LayoutsApp: App {
  var body: some Scene {
    WindowGroup {
      LayoutsRoot()
    }
  }
}

/// Two-state router: nil → picker, non-nil → detail host.
///
/// `selectedID` lives on the router because only the router owns the
/// routing bit — `LayoutDetailHost.onBack` must flip it on the parent,
/// and `LayoutPicker.onSelect` must write it from below. The
/// `ConditionalContent` branch swap tears down each subview on
/// transition; the picker self-clears its local `selection` after
/// firing `onSelect`, so a fresh picker on back-trip is the correct
/// state.
struct LayoutsRoot: View {
  @State private var selectedID: LayoutEntry.ID?

  var body: some View {
    if let id = selectedID, let entry = LayoutCatalog.entry(id: id) {
      LayoutDetailHost(entry: entry, onBack: { selectedID = nil })
    } else {
      LayoutPicker(onSelect: { selectedID = $0 })
    }
  }
}
```

- [ ] **Step 2: Build the executable**

Run: `cd Examples/layouts && swift build --target LayoutsApp`
Expected: success. The binary links (even with an empty catalog).

- [ ] **Step 3: Smoke-launch the picker**

Run: `cd Examples/layouts && swift run layouts-demo` and immediately
press `⌃C`.
Expected: the picker renders with the "0 layouts across 16
categories" header text, no list body, then ⌃C exits cleanly. If the
process hangs after ⌃C, check that `TerminalUICLI`'s
`ExitKeyBindings.default` handles SIGINT — no further fix is needed
from this plan (it already does in `Runners/TerminalUICLI`).

- [ ] **Step 4: Commit**

```bash
git add Examples/layouts/Sources/LayoutsApp/LayoutsApp.swift
git commit -m "feat(layouts): add @main LayoutsApp + LayoutsRoot two-state router"
```

---

## Task 8: Parameterised smoke test + first archetype layout (#1 HStackAlignmentTriad)

This task establishes the reusable testing patterns — the
parameterised smoke test and the first behaviour test — that every
subsequent layout task in Tasks 9–24 follows. Read it carefully.

**Files:**
- Create: `Examples/layouts/Sources/Layouts/Stacks/HStackAlignmentTriad.swift`
- Create: `Examples/layouts/Tests/LayoutsTests/RenderSupport.swift`
- Create: `Examples/layouts/Tests/LayoutsTests/LayoutSmokeTests.swift`
- Create: `Examples/layouts/Tests/LayoutsTests/Stacks/HStackAlignmentTriadBehaviourTests.swift`
- Modify: `Examples/layouts/Sources/Layouts/LayoutCatalog.swift`

- [ ] **Step 1: Write the layout view**

```swift
// Sources/Layouts/Stacks/HStackAlignmentTriad.swift
import TerminalUI

/// Three HStacks of mixed-height children, one per `VerticalAlignment`
/// (`.top`, `.center`, `.bottom`). Pins where the shorter child
/// anchors within each row. The marker text `"triad"` appears
/// exactly once (in the header) so it identifies this layout in the
/// raster without colliding with children.
public struct HStackAlignmentTriad: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("HStack alignment triad").foregroundStyle(.muted)
      row("top", alignment: .top)
      row("center", alignment: .center)
      row("bottom", alignment: .bottom)
    }
    .padding(1)
  }

  private func row(_ label: String, alignment: VerticalAlignment) -> some View {
    HStack(alignment: alignment, spacing: 1) {
      Text(label).frame(width: 7, alignment: .leading)
      Text("tall\ntall\ntall").border(.separator)
      Text("short").border(.separator)
    }
  }
}
```

- [ ] **Step 2: Add the catalog entry**

Replace the `public static let all: [LayoutEntry] = []` line in
`Sources/Layouts/LayoutCatalog.swift` with:

```swift
public static let all: [LayoutEntry] = [
  // AnyView policy: `makeView` is the single documented AnyView seam
  // for the heterogeneous catalog. Every concrete layout below is a
  // strongly-typed `View`; erasure happens only in the closure.
  LayoutEntry(
    id: "stacks.hstack-alignment-triad",
    category: .stacks,
    title: "HStack alignment triad",
    blurb: ".top vs .center vs .bottom with mixed-height children",
    marker: "HStack alignment triad",
    tier: .behaviour,
    makeView: { AnyView(HStackAlignmentTriad()) }
  ),
]
```

- [ ] **Step 3: Write the parameterised smoke test**

```swift
// Tests/LayoutsTests/LayoutSmokeTests.swift
import TerminalUI
import Testing

@testable import Layouts

/// Every catalog entry must resolve, rasterise to a non-empty
/// surface, and paint its ``LayoutEntry/marker`` string somewhere
/// in the viewport. Replicates the pattern used by
/// `BordersAndShapesTabTests.rendersNonEmptySurface`.
@MainActor
@Suite
struct LayoutSmokeTests {
  @Test("Every catalog entry resolves and paints its marker",
        arguments: LayoutCatalog.all)
  func rasterisesAndShowsMarker(entry: LayoutEntry) {
    let size = Size(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = size
    let artifacts = DefaultRenderer().render(
      entry.makeView(),
      context: ResolveContext(
        identity: Identity(components: [.named("layouts.smoke.\(entry.id)")]),
        environmentValues: env
      ),
      proposal: ProposedSize(width: size.width, height: size.height)
    )
    #expect(artifacts.rasterSurface.cells.count > 0,
            "\(entry.id) produced zero raster rows")
    #expect(artifacts.rasterSurface.lines.contains { !$0.isEmpty },
            "\(entry.id) produced only empty lines")
    let joined = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(joined.contains(entry.marker),
            "\(entry.id) did not paint marker '\(entry.marker)'\n\(joined)")
  }
}
```

- [ ] **Step 4: Write the behaviour test**

```swift
// Tests/LayoutsTests/Stacks/HStackAlignmentTriadBehaviourTests.swift
import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct HStackAlignmentTriadBehaviourTests {
  /// At `.top`, the "short" child anchors to the top row of the
  /// HStack — its single line sits on the same row as the tall
  /// child's first line. At `.bottom`, it anchors to the last.
  /// At `.center`, it sits in the middle of the 3-line tall child.
  @Test("Short child anchors per vertical alignment")
  func shortChildAnchorsPerAlignment() {
    let artifacts = render(HStackAlignmentTriad(), width: 40, height: 20)
    let lines = artifacts.rasterSurface.lines
    // The three rows of the triad each contain a "short" label.
    let shortRowIndices = lines.enumerated().compactMap {
      $0.element.contains("short") ? $0.offset : nil
    }
    #expect(shortRowIndices.count == 3,
            "expected 3 rows containing 'short', got \(shortRowIndices.count)")
    // top-row triad's short label is on the row aligned with
    // "tall"'s first line; bottom-row's is aligned with "tall"'s
    // last line. The rows are ordered top < center < bottom.
    // Behaviour we pin: those three indices are strictly increasing
    // and spaced apart by at least 4 rows (one triad row + 1 spacing
    // + border ring).
    let sorted = shortRowIndices.sorted()
    #expect(sorted == shortRowIndices, "rows not emitted in display order")
    #expect(sorted[1] - sorted[0] >= 4)
    #expect(sorted[2] - sorted[1] >= 4)
  }
}
```

- [ ] **Step 4a: Write the shared render helper**

```swift
// Tests/LayoutsTests/RenderSupport.swift
import TerminalUI

@testable import Layouts

/// Single-shot render helper used by every behaviour test file.
/// Identity is derived from `#function` so parallel test invocations
/// get unique identities.
@MainActor
func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = #function
) -> FrameArtifacts {
  var env = EnvironmentValues()
  env.terminalSize = Size(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: [.named("layouts.behaviour.\(id)")]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
```

- [ ] **Step 5: Run the tests**

Run: `cd Examples/layouts && swift test`
Expected (all PASS):
- `CatalogIntegrityTests.ids_areUnique`
- `CatalogIntegrityTests.entries_haveRequiredFields`
- `CatalogIntegrityTests.lookup_returnsMatch`
- `LayoutSmokeTests.rasterisesAndShowsMarker(HStackAlignmentTriad)`
- `HStackAlignmentTriadBehaviourTests.shortChildAnchorsPerAlignment`

Still expected FAIL (the red we want):
- `CatalogIntegrityTests.entries_coverAllCategories` (15 categories
  still empty)

If any of the 5 "expected PASS" tests fails, **stop and investigate** —
the behaviour has drifted from what the spec pinned. Do not relax
the assertion. Record the finding under
`docs/proposals/layout/<SYMBOL>.md` and pause the plan until the user
decides whether to (a) accept the current behaviour and update the
test assertion or (b) file a runtime fix.

- [ ] **Step 6: Commit**

```bash
git add Examples/layouts/Sources/Layouts/Stacks/HStackAlignmentTriad.swift \
        Examples/layouts/Sources/Layouts/LayoutCatalog.swift \
        Examples/layouts/Tests/LayoutsTests/RenderSupport.swift \
        Examples/layouts/Tests/LayoutsTests/LayoutSmokeTests.swift \
        Examples/layouts/Tests/LayoutsTests/Stacks/HStackAlignmentTriadBehaviourTests.swift
git commit -m "feat(layouts): add #1 HStackAlignmentTriad + smoke/behaviour test archetype"
```

---

## Tasks 9-24: Category batches

Each of the next 16 tasks implements one category from the taxonomy.
The task shape is identical for every category:

> **Category task template** (each task below expands this template
> with concrete code per layout):
>
> 1. For each layout in the category, in order:
>    - Create the layout view file with a `struct <Title>: View` that
>      contains `Text("<marker>")` visible at `80×28`.
>    - Add the corresponding `LayoutEntry(...)` literal to
>      `LayoutCatalog.all` (append in the category's declared order).
>    - If tier `.behaviour`: create the behaviour test file under
>      `Tests/LayoutsTests/<Category>/<Title>BehaviourTests.swift`
>      using the shared `render(_:width:height:id:)` helper from Task 8.
> 2. Run `swift test` after each layout lands; every test must be
>    green before moving to the next layout. A failing **behaviour**
>    test means the layout's view or the test's assertion is wrong;
>    fix until green. A failing **smoke** test on only the new entry
>    almost always means the marker string is wrong.
> 3. Commit per layout, not per category, using message:
>    `feat(layouts): add #<N> <Title>` (or
>    `test(layouts): add #<N> <Title> behaviour test` if the view was
>    committed separately).
> 4. When the last layout of the category lands, the failing
>    `CatalogIntegrityTests.entries_coverAllCategories` case for that
>    category is eliminated.
>
> The behaviour-test assertions below are the starting point. They
> encode what the layout is *supposed* to demonstrate. If an
> assertion fails because the runtime's behaviour is different than
> assumed:
> 1. **Do not relax the assertion** to match reality. The point of
>    the test is to pin behaviour.
> 2. Record the finding in `docs/proposals/layout/<SYMBOL>.md` with
>    current behaviour / assumed behaviour / proposed fix.
> 3. Pause and raise with the user.
> 4. If the user accepts current behaviour, update the assertion and
>    annotate the test file with a comment linking the finding.
> 5. If the user wants a runtime fix, leave the test red and ship the
>    fix in a subsequent PR (the test flips green with no test
>    changes).

Tasks 9–24 follow. Each dispatches a subagent with a category brief.
The subagent's scope: create the listed view files, append the
listed catalog entries, create the listed behaviour test files, run
`swift test` until green, commit per-layout.

---

## Task 9: Category A — Stacks remainder (#2-5, 4 layouts)

**Files:**
- Create: `Sources/Layouts/Stacks/VStackSpacingVsPadding.swift` — #2
- Create: `Sources/Layouts/Stacks/ZStackAlignmentGrid.swift` — #3
- Create: `Sources/Layouts/Stacks/HStackPriorityTug.swift` — #4
- Create: `Sources/Layouts/Stacks/VStackLeadingGuideShift.swift` — #5
- Create: `Tests/LayoutsTests/Stacks/ZStackAlignmentGridBehaviourTests.swift` — #3
- Create: `Tests/LayoutsTests/Stacks/HStackPriorityTugBehaviourTests.swift` — #4
- Create: `Tests/LayoutsTests/Stacks/VStackLeadingGuideShiftBehaviourTests.swift` — #5
- Modify: `Sources/Layouts/LayoutCatalog.swift` (append 4 entries)

**Per-layout invariants to pin:**

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 2 | `stacks.vstack-spacing-vs-padding` | `"VStack spacing vs padding"` | S | (none) |
| 3 | `stacks.zstack-alignment-grid` | `"ZStack alignment grid"` | B | At 60×30 proposal, find cells containing `"TL"`, `"TR"`, `"BL"`, `"BR"`, `"C"`. Assert `TL` row < `C` row < `BR` row and `TL` col < `C` col < `BR` col. |
| 4 | `stacks.hstack-priority-tug` | `"HStack priority tug"` | B | Render at width 40 (all fit) and width 16 (squeeze). At 16, assert the medium-priority child's full text `"keep"` is still present; low-priority siblings may truncate. |
| 5 | `stacks.vstack-leading-guide-shift` | `"VStack leading guide shift"` | B | Render at width 40. Find row containing `"shifted"`; assert its first non-space column is 4 greater than the row containing `"normal"`. |

**Dispatch brief:**

- [ ] **Step 1: Dispatch a subagent**

Invoke `superpowers:subagent-driven-development` with scope:

> Implement Category A remainder (layouts #2-5) for the Layouts
> example. Reference: Task 8 archetype (view + catalog entry +
> behaviour test + RenderSupport) and design doc §4 Category A. Each
> layout is ~15-30 lines of view code; each behaviour test is a
> single `@Test` using the shared `render(_:width:height:)` helper
> and asserting the invariant from the table above. Catalog entries
> append to `LayoutCatalog.all` using the IDs/markers/tiers in the
> table. Commit per-layout with message
> `feat(layouts): add #<N> <Title>` (and a separate
> `test(layouts): ...` commit if view + test can ship as two
> commits).

- [ ] **Step 2: Verify the category is green**

Run: `cd Examples/layouts && swift test --filter LayoutsTests`
Expected: 1 new smoke invocation + 3 new behaviour test functions
pass. `CatalogIntegrityTests.entries_coverAllCategories` still fails
(15 other categories missing).

- [ ] **Step 3: Verify picker shows the new rows**

Run: `cd Examples/layouts && swift run layouts-demo`, confirm the
Stacks section has 5 rows (#1-5), then ⌃C.

---

## Task 10: Category B — Frames & Sizing (#6-13, 8 layouts)

**Files:**
- Create: `Sources/Layouts/Frames/FrameFixedInsideUnbounded.swift` — #6
- Create: `Sources/Layouts/Frames/FlexibleFrameAlignmentGrid.swift` — #7
- Create: `Sources/Layouts/Frames/FixedSizeText.swift` — #8
- Create: `Sources/Layouts/Frames/FixedSizeOneAxis.swift` — #9
- Create: `Sources/Layouts/Frames/MinIdealMaxFrameClamp.swift` — #10
- Create: `Sources/Layouts/Frames/LayoutPriorityCascade.swift` — #11
- Create: `Sources/Layouts/Frames/ProposalTightening.swift` — #12
- Create: `Sources/Layouts/Frames/IntrinsicTextUnderZeroProposal.swift` — #13
- Create 7 behaviour test files under `Tests/LayoutsTests/Frames/` (one per tier B entry)
- Modify: `Sources/Layouts/LayoutCatalog.swift`

**Per-layout invariants to pin:**

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 6 | `frames.frame-fixed-inside-unbounded` | `"Frame fixed inside unbounded"` | S | (none) |
| 7 | `frames.flexible-frame-alignment-grid` | `"Flex grid"` | B | At 60×30, render a `VStack` of 9 cells each `.frame(maxWidth:.infinity, maxHeight:.infinity, alignment:)` with corner-marker labels `TL/T/TR/L/C/R/BL/B/BR`. Assert `TL` sits at cell column 0 and `BR` at the last non-empty column of its row; `C`'s row is in the middle third. |
| 8 | `frames.fixed-size-text` | `"FixedSize text"` | B | Render a long text with `.fixedSize()` inside a `.frame(width: 10)` parent on an 80-wide surface. Assert the text's full content (e.g. `"thelongerstring"`) appears in the raster — proving it escaped the 10-wide frame. |
| 9 | `frames.fixed-size-one-axis` | `"FixedSize one axis"` | B | Render `Text("abc def ghi jkl").fixedSize(horizontal: false, vertical: true)` in a `.frame(width: 8)`. Assert the text wraps horizontally (multiple rows) but the row count equals the natural wrapped row count — not expanded. |
| 10 | `frames.min-ideal-max-frame-clamp` | `"Min/ideal/max clamp"` | B | Render same inner view under three frames: `.frame(minWidth: 20, idealWidth: 40, maxWidth: 60)` at proposals 10 / 40 / 80. Assert measured widths are 20 / 40 / 60 respectively. |
| 11 | `frames.layout-priority-cascade` | `"Priority cascade"` | B | 4 siblings with priorities `0, 1, 0, 2`; proposal 24. Assert priority-2 keeps its text intact, priority-1 keeps its text intact, priority-0 siblings may truncate. |
| 12 | `frames.proposal-tightening` | `"Proposal tightening"` | B | `.frame(width: 30)` wraps a `GeometryReader` that renders `Text("w=\(Int(proxy.size.width))")`. Assert the raster contains `"w=30"` regardless of outer terminal width. |
| 13 | `frames.intrinsic-text-under-zero-proposal` | `"Zero proposal"` | B | Two renders: Text alone (natural size) vs `.frame(width: 0, height: 0)` Text. Assert the second raster has a row where the Text's content does not appear (collapsed) OR — if the runtime's current behaviour is "ignore zero proposal and render natural" — assert that. Record the observed rule in a comment. |

**Dispatch brief:** (as Task 9, for Category B)

- [ ] **Step 1: Dispatch subagent**

Scope: implement #6-13 following Task 8 archetype + design doc §4
Category B. Table above gives the assertion shapes. #13 is a
pinning test for an unknown runtime rule — the subagent must
record the observed behaviour in the test file comments and
mention it in the commit message.

- [ ] **Step 2: Verify the category is green**

Run: `cd Examples/layouts && swift test`
Expected: 8 new smoke invocations + 7 behaviour tests pass.

- [ ] **Step 3: Check for any `.behaviour` test that had to adapt**

If the subagent reported adapting an assertion because runtime
behaviour differed from the spec's expectation, add a one-line
entry to `docs/proposals/layout/` per the Risks process. Do not
skip this step.

---

## Task 11: Category C — Padding, insets, safe areas (#14-17, 4 layouts)

**Files:**
- Create: 4 views under `Sources/Layouts/Padding/`
- Create: 3 behaviour tests under `Tests/LayoutsTests/Padding/`
- Modify: `Sources/Layouts/LayoutCatalog.swift`

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 14 | `padding.asymmetric-insets` | `"Asymmetric insets"` | S | (none) |
| 15 | `padding.border-ordering` | `"Border ordering"` | B | Two columns: `Text.padding(1).border(.separator)` and `Text.border(.separator).padding(1)`. Assert measured widths differ by 2 and the border ring glyphs sit at different x offsets. |
| 16 | `padding.safe-area-inset-bottom-bar` | `"Safe area inset bar"` | B | ScrollView of 30 lines + `.safeAreaInset(edge: .bottom)` of a 1-row bar. At height 10, assert the bar's marker is on the last row and the row above contains content (not bar). |
| 17 | `padding.ignores-safe-area-bleed` | `"Ignores safe area"` | B | Same shape as #16 but content uses `.ignoresSafeArea(.container, edges: .bottom)`. Assert content cells occupy the row the bar would otherwise reserve (content marker visible at the bar's row). |

**Dispatch brief:** (as Task 9, for Category C.) Verify, commit.

---

## Task 12: Category D — Borders, overlays, backgrounds (#18-23, 6 layouts)

**Files:**
- Create: 6 views under `Sources/Layouts/BordersOverlays/`
- Create: 5 behaviour tests under `Tests/LayoutsTests/BordersOverlays/`
- Modify: `Sources/Layouts/LayoutCatalog.swift`

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 18 | `borders.background-vs-overlay-paint-order` | `"Background vs overlay"` | B | Two same-size stacks: one with `.background(.red)` + inner Text; one with `.overlay(.red)` + inner Text. Assert the overlay version's shared cell is the overlay's color (inner Text is obscured); the background version shows the Text. |
| 19 | `borders.nested-border-ordering` | `"Nested borders"` | B | `Text.padding(1).border(.single).padding(1).border(.double)`. Assert two distinct border sets appear at the expected radial offsets (inner ring one char inside outer ring). |
| 20 | `borders.per-side-border-colors` | `"Per-side border colors"` | B | `BorderEdgeStyle(top:.red, right:.yellow, bottom:.green, left:.blue)` on a known-sized Text. Assert the top-row border cells are red, bottom are green, left column blue, right column yellow. (See `BordersAndShapesTab.swift` for `BorderEdgeStyle` usage.) |
| 21 | `borders.border-blend-static-phase` | `"BorderBlend static"` | B | Two renders: `BorderBlend([.red, .yellow, .green, .cyan])` at phase 0.0 and phase 0.5. Assert the top-left corner's color differs between the two rasters. No RunLoop. |
| 22 | `borders.background-shapestyle-vs-content-overloads` | `"Background overloads"` | S | (none) |
| 23 | `borders.overlay-alignment-badge` | `"Overlay alignment badge"` | B | `.overlay(alignment: .bottomTrailing) { Text("●") }` on a 20×5 frame. Assert `"●"` is painted at the bottom-right corner cell. |

---

## Task 13: Category E — Offset, position, clip (#24-27, 4 layouts)

**Files:** 4 views under `Sources/Layouts/OffsetPosition/`, 4
behaviour tests under `Tests/LayoutsTests/OffsetPosition/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 24 | `offset.preserves-measured-size` | `"Offset preserves size"` | B | `HStack { A("a").frame(width: 2); B("b").frame(width: 2).offset(x: 4); C("c").frame(width: 2) }`. Assert `"a"` at col 0, `"b"` at col 6 (natural col 2 + offset 4), `"c"` at col 4 (B's natural end, unshifted by B's offset). |
| 25 | `offset.position-ignores-layout` | `"Position anchor"` | B | `.position(x: 40, y: 14)` on an 80×28 surface. Assert the inner Text centers at (40, 14) — the Text's visible cells cluster around that anchor. |
| 26 | `offset.clipped-overflow-crop` | `"Clipped crop"` | B | Wider content `.frame(width: 10).clipped()` on a 30-wide surface. Assert columns 10-29 of the content's row are empty. |
| 27 | `offset.negative-escape` | `"Negative escape"` | B | Content at `.offset(x: -2)` inside a parent without `.clipped()`. Assert the inner content's leading glyph appears at the expected negative-ish cell (or whatever the runtime's actual rule is — pin it). |

---

## Task 14: Category F — ZStack depth & order (#28-30, 3 layouts)

**Files:** 3 views under `Sources/Layouts/ZStack/`, 3 behaviour
tests under `Tests/LayoutsTests/ZStack/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 28 | `zstack.paint-order-overlap` | `"Paint order"` | B | `ZStack { Rectangle().fill(.red); Rectangle().fill(.blue) }` same-sized. Assert shared cell is blue (later paints over). |
| 29 | `zstack.sized-by-largest` | `"Sized by largest"` | B | `ZStack { small: Text("s"); large: .frame(width: 20, height: 5) }`. Assert measured size of the ZStack is 20×5. |
| 30 | `zstack.spacer-noop` | `"Spacer noop"` | B | `ZStack { Spacer(); Text("x") }`. Assert stack's measured size equals `Text("x")`'s natural size (1 column, 1 row or whatever Text's intrinsic is), not the full proposal. |

---

## Task 15: Category G — Spacer, Divider (#31-33, 3 layouts)

**Files:** 3 views under `Sources/Layouts/Spacers/`, 3 behaviour
tests under `Tests/LayoutsTests/Spacers/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 31 | `spacers.three-sharing` | `"Three spacers"` | B | `HStack { Spacer(); Text("a"); Spacer(); Text("b"); Spacer() }` width 40. Assert `"a"` ≈ col 13-14 (1/3 of residual before a, residual is 38 after a+b, 38/3≈12.66), `"b"` ≈ col 26-27. (Use inclusive tolerance ±2 for rounding.) |
| 32 | `spacers.min-length-respected` | `"Min length"` | B | `HStack { Spacer(minLength: 10); Text("x") }` in a width-12 proposal. Assert Text is at col 10 or later. |
| 33 | `spacers.divider-orientation-flip` | `"Divider orientation"` | B | Two layouts: `VStack { ...; Divider(); ... }` and `HStack { ...; Divider(); ... }`. Assert the first has a horizontal rule glyph row; the second has a vertical rule glyph column. |

---

## Task 16: Category H — ScrollView (#34-36, 3 layouts)

**Files:** 3 views under `Sources/Layouts/Scrolling/`, 3 behaviour
tests under `Tests/LayoutsTests/Scrolling/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 34 | `scrolling.vertical-measures-content` | `"Vertical scroll"` | B | 100-row VStack inside ScrollView + `.frame(height: 10)`. Assert the rendered surface is 10 rows (proposal height), and content marker for rows 0-8 visible while row 99 is not. |
| 35 | `scrolling.horizontal-infinite-child` | `"Horizontal infinite"` | B | Horizontal ScrollView containing `HStack { items.map { $0 }.frame(maxWidth: .infinity) }`. Assert the render completes (doesn't hang/explode) and contains the first item's marker. |
| 36 | `scrolling.safe-area-inset` | `"Scroll safe area"` | B | ScrollView with `.safeAreaInset(edge: .top) { bar }`. Assert the bar's marker is on row 0 and the first content row starts at row 1. |

---

## Task 17: Category I — GeometryReader (#37-39, 3 layouts)

**Files:** 3 views under `Sources/Layouts/Geometry/`, 3 behaviour
tests under `Tests/LayoutsTests/Geometry/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 37 | `geometry.takes-proposal` | `"Geometry takes proposal"` | B | `.frame(width: 40, height: 10) { GeometryReader { proxy in Text("w=\(Int(proxy.size.width)) h=\(Int(proxy.size.height))") } }`. Assert raster contains `"w=40 h=10"`. |
| 38 | `geometry.in-hstack-hogs` | `"Geometry in HStack"` | B | `HStack { GeometryReader { _ in Text("g") }; Text("b") }` at width 20. Pin the observed behaviour (whether `b` survives, gets pushed to col 19, or is elided). Record rule in test comment. Flag as a Risks finding if surprising. |
| 39 | `geometry.anchor-corner` | `"Geometry anchor"` | B | `GeometryReader { proxy in Text("x").position(x: proxy.size.width - 1, y: 0) }` in `.frame(width: 40, height: 5)`. Assert `"x"` at (col 39, row 0). |

---

## Task 18: Category J — ViewThatFits (#40-42, 3 layouts)

**Files:** 3 views under `Sources/Layouts/ViewThatFits/`, 3
behaviour tests under `Tests/LayoutsTests/ViewThatFits/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 40 | `view-that-fits.axis-choice` | `"VTF axis choice"` | B | `ViewThatFits { long; medium; short }` at widths 60, 30, 10. Assert raster at 60 contains `long`, at 30 contains `medium` (not `long`), at 10 contains `short` (not `medium`). |
| 41 | `view-that-fits.vertical-only` | `"VTF vertical"` | B | `ViewThatFits(in: .vertical) { tall; medium; single }` at heights 20, 10, 3. Assert heights resolve to tall / medium / single respectively. |
| 42 | `view-that-fits.boundary-inclusive` | `"VTF boundary"` | B | Variant `Text("abc")` needing width 3. Render at width 3 and width 2. Assert at 3 the Text is chosen; at 2 the fallback (e.g. `Text("a")`) is chosen. Pins the inclusive-vs-exclusive rule; record in comment. |

---

## Task 19: Category K — Custom Layout / AnyLayout (#43-45, 3 layouts)

**Files:** 3 views under `Sources/Layouts/CustomLayout/` (two
include custom `Layout` types), 3 behaviour tests under
`Tests/LayoutsTests/CustomLayout/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 43 | `custom-layout.flow-wrap` | `"Flow wrap"` | B | Custom `FlowLayout` wrapping 10 `Text` children onto rows that fit in the proposal. At width 60, assert 1 row; at width 20, assert ≥2 rows. |
| 44 | `custom-layout.any-layout-hv-swap` | `"AnyLayout swap"` | B | `AnyLayout(isCompact ? VStackLayout() : HStackLayout())` with 3 fixed-size children. Render `isCompact = true`, assert height ≥ 3 rows. Render `false`, assert height is 1 row. |
| 45 | `custom-layout.radial` | `"Radial"` | B | Custom `RadialLayout` placing 4 children at angles 0°, 90°, 180°, 270° around a center. Assert the first child sits to the right of center (angle 0) — its col > center col, row ≈ center row. |

**Notes for the subagent:** `Layout` protocol signatures live at
`Sources/View/Layout/Layout.swift:119` + usages at
`HStackLayout`/`VStackLayout` (lines 365+, 420+). `Layout.callAsFunction`
lets `MyLayout { children }` syntax work. `AnyLayout.callAsFunction`
at line 353. Any polymorphism between layouts at runtime uses
`AnyLayout(concreteLayout)` per `Layout.swift:262`.

---

## Task 20: Category L — Alignment guides (advanced) (#46-47, 2 layouts)

**Files:** 2 views under `Sources/Layouts/AlignmentGuides/` (#46
includes a custom `HorizontalAlignment`), 2 behaviour tests.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 46 | `alignment.colon-aligned-form` | `"Colon-aligned form"` | B | 3 rows of `HStack { Text("label of variable length"); Text(":"); Text("value") }` all pinned to a custom `HorizontalAlignment` at the colon. Assert all `":"` glyphs share the same column across the three rows. |
| 47 | `alignment.dimension-dependent-guide` | `"Dimension-dependent guide"` | B | 3 boxes of different heights aligned bottom via `.alignmentGuide(.bottom) { d in d.height }`. Assert the last row of each box sits on the same terminal row. |

**Notes:** Custom `HorizontalAlignment` example is not in the
gallery; the subagent should find the runtime's public alignment
constructor. `Sources/View/Foundation/StylePrimitives.swift` or
`Sources/Core/GeometryTypes.swift` near `HorizontalAlignment`. If no
constructor is public, fall back to using a built-in alignment like
`.leading` with per-row `.alignmentGuide(.leading) { d in d[.trailing of colon subview] }` — adapt and document.

---

## Task 21: Category M — Collections in layouts (#48-50, 3 layouts)

**Files:** 3 views under `Sources/Layouts/Collections/`, 3
behaviour tests under `Tests/LayoutsTests/Collections/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 48 | `collections.list-in-short-frame` | `"List short frame"` | B | `List { ForEach(0..<20) { Text("row \($0)") } }.frame(height: 5)`. Assert `"row 0"` is visible; `"row 19"` is not. |
| 49 | `collections.for-each-identity-reorder` | `"ForEach reorder"` | B | Two renders of `ForEach(items, id: \.id) { ... }` with items reordered between renders. Assert both rasters contain the same set of item markers (identity preserved — no items dropped). Positions may change. |
| 50 | `collections.table-column-prioritization` | `"Table column priority"` | B | Table with 4 columns of varied priorities under narrow proposal. Assert the highest-priority column's full header text survives; at least one lower-priority column's content truncates. |

**Notes:** `List` public init is at
`Sources/View/Collections/List.swift:131`; `Table` + `TableColumn`
at `Sources/View/Collections/Table.swift:40`; `TableColumn` struct
at `Sources/View/Foundation/StylePrimitives.swift:10`.

---

## Task 22: Category N — Shape & canvas (#51-53, 3 layouts)

**Files:** 3 views under `Sources/Layouts/ShapesCanvas/`, 3
behaviour tests under `Tests/LayoutsTests/ShapesCanvas/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 51 | `shapes.circle-in-non-square-frame` | `"Circle non-square"` | B | `Circle().fill(.red).frame(width: 12, height: 5)`. Assert cells at corners (0,0), (11,0), (0,4), (11,4) are empty/non-fill; center cell is fill. |
| 52 | `shapes.capsule-axis-flip` | `"Capsule axis flip"` | B | `Capsule().fill(.blue)` in 20×3 vs 3×20. Assert wide variant's leftmost cells are rounded (not flat fill at the corners); tall variant rounds the top/bottom. |
| 53 | `shapes.canvas-honors-clipped` | `"Canvas clipped"` | B | Custom `Canvas` drawing a polyline that extends past its frame + `.clipped()`. Assert no cells are painted outside the frame's columns/rows. |

**Notes:** Shape APIs at
`Sources/View/Shapes/{Rectangle,Circle,Ellipse,Capsule,RoundedRectangle}.swift`.
`Canvas` + `CanvasDrawing` at `Sources/View/Canvas.swift`. See
`Examples/gallery/Sources/GalleryDemoViews/BordersAndShapesTab.swift`
for a `Sparkline: CanvasDrawing` reference.

---

## Task 23: Category O — Presentation × layout (#54-55, 2 layouts)

**Files:** 2 views under `Sources/Layouts/PresentationLayout/`, 1
behaviour test under `Tests/LayoutsTests/PresentationLayout/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 54 | `presentation.sheet-over-scroll` | `"Sheet over scroll"` | S | (none) — smoke only. The smoke test verifies the layout + sheet state combination rasterises without explosion. |
| 55 | `presentation.alert-anchor-stable` | `"Alert anchor stable"` | B | Two renders: with `isPresented: false` alert state and `true`. Assert cell (0, 0) of the underlying layout is identical in both rasters (the underlying content's top-left does not reflow when the alert appears). |

**Notes:** Alert/sheet APIs at
`Sources/View/Presentation/PresentationModifiers.swift`. #54 renders
a view that has `.sheet(isPresented:)` bound to a state toggle; the
smoke test just confirms it rasterises. #55's behaviour test
toggles a state in the view being tested to create the two snapshots;
do this by driving two separate `render(...)` calls with two different
state values in the wrapper view.

---

## Task 24: Category P — Matched geometry (#56, 1 layout)

**Files:** 1 view under `Sources/Layouts/Matched/`, 1 behaviour
test under `Tests/LayoutsTests/Matched/`.

| # | ID | Marker | Tier | Behaviour test assertion |
|---|------|--------|------|--------------------------|
| 56 | `matched.badge-move` | `"Matched badge"` | B | Badge `.matchedGeometryEffect(id: "badge", ...)` switches between two container layouts based on state. Render in state A and state B. Assert the badge's marker cell sits at different (x, y) in the two rasters; both rasters are valid (non-empty). |

**Notes:** `matchedGeometryEffect` modifier at
`Sources/View/Modifiers/ViewModifiers.swift:242`. The test does not
assert any animation / interpolation — it only asserts the two
discrete states produce the expected position delta. Animation
coverage is out of scope for this suite (Non-goals, §2).

---

## Task 25: Picker shell tests, README polish, end-to-end verify

**Files:**
- Create: `Examples/layouts/Tests/LayoutsTests/PickerShellTests.swift`
- Modify: `Examples/layouts/README.md` (if needed after all layouts land)

- [ ] **Step 1: Write the picker shell test**

```swift
// Tests/LayoutsTests/PickerShellTests.swift
import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct PickerShellTests {
  @Test("Picker rasterises with one section per represented Category")
  func pickerShowsAllCategories() {
    // Reach into LayoutPicker via the package — need to either make
    // it `public` or build the picker view via a `LayoutsApp`-level
    // re-export. Simplest: use the strategy from RenderSupport and
    // construct the picker in the test.
    // NOTE: LayoutPicker is currently `internal` to LayoutsApp. If
    // the test can't import LayoutsApp, re-home LayoutPicker to
    // `Layouts` (the library) or expose a thin wrapper. Choose
    // whichever has the smaller blast radius; the repo convention is
    // to keep demo views public on the library, so promoting the
    // picker to `public` in `Layouts` is fine.
    let artifacts = render(
      LayoutPicker(onSelect: { _ in }),
      width: 80,
      height: 40,
      id: "picker-shell"
    )
    let joined = artifacts.rasterSurface.lines.joined(separator: "\n")
    for category in LayoutEntry.Category.allCases {
      #expect(joined.contains(category.rawValue),
              "picker did not show category section '\(category.rawValue)'")
    }
    #expect(joined.contains("56 layouts"),
            "picker header did not show 56-layout count")
  }
}
```

- [ ] **Step 2: Resolve the LayoutPicker visibility**

If `LayoutPicker` is currently in `Sources/LayoutsApp/` and
`LayoutsTests` can't see it, move it to
`Sources/Layouts/LayoutPicker.swift` and mark it `public`. Update
`LayoutsApp.swift`'s import + usage accordingly. Commit this as:
`refactor(layouts): move LayoutPicker into Layouts library for tests`.

- [ ] **Step 3: Run the full test suite**

Run: `cd Examples/layouts && swift test`
Expected: every test green. In particular:
- 1 parameterised `LayoutSmokeTests` × 56 arguments = 56 PASSES
- 51 `*BehaviourTests` × ~1-2 functions each ≈ ~60-90 PASSES
- 4 `CatalogIntegrityTests` PASS (including
  `entries_coverAllCategories` — now satisfied)
- 1 `PickerShellTests` PASS
- **Total: ~120 PASSES, 0 FAILS** (unless a Risks-flagged layout
  surfaced a runtime bug — in which case there's a finding in
  `docs/proposals/layout/` explaining the red.)

- [ ] **Step 4: Smoke-launch the app**

Run: `cd Examples/layouts && swift run layouts-demo`
- Header shows: `56 layouts across 16 categories`.
- Arrow keys navigate; press `⏎` to open entry #1 (`HStack
  alignment triad`). Verify the detail host renders with the
  `esc back · ⌃C quit` footer.
- Press `esc` — returns to the picker.
- Page down through the full list; confirm each of the 16
  categories has rows.
- `⌃C` exits.

- [ ] **Step 5: Run the full repo test harness**

Run (from repo root): `bun run test`
Expected: all root-package, gallery, TerminalUICLI,
TerminalUIWASI, and now `Examples/layouts/` suites pass. If `bun
run test` doesn't yet know about `Examples/layouts/`, add it to
the runner — check
`Scripts/` or `package.json` for the test orchestration. Commit
any runner update as a separate commit:
`chore(layouts): teach bun run test about Examples/layouts`.

- [ ] **Step 6: Verify pre-commit hooks**

Run: `prek run --all-files`
Expected: all hooks pass. In particular:
- `swift-format` (reformats if needed — commit the formatting pass)
- `public-surface-policies` — expected PASS because the only
  `AnyView` usage is in `LayoutCatalog.all` with a documented
  `AnyView policy:` comment.
- `no-foundation-in-library-products` — expected PASS because
  `Layouts` does not `import Foundation`.

- [ ] **Step 7: Update README (if needed)**

If README needs updates — e.g. if `swift run layouts-demo` takes
non-default arguments or the picker's keybindings changed during
implementation — update `Examples/layouts/README.md` and commit:
`docs(layouts): README polish after full implementation`.

- [ ] **Step 8: Final commit & open PR**

If everything is green, create a branch, push, and open a PR
summarising the work. The PR should reference the plan:
"Implements `docs/plans/2026-04-24-001-layouts-example-plan.md`
Tasks 1-25."

```bash
git checkout -b feat/layouts-example
git push -u origin feat/layouts-example
gh pr create --title "feat: layouts example app & test suite" --body "$(cat <<'EOF'
## Summary

- New \`Examples/layouts/\` sub-package with three targets: \`Layouts\` (library of 56 layout views), \`LayoutsTests\` (smoke + behaviour tests), \`LayoutsApp\` (executable picker + detail host).
- Full-screen push/pop picker — Esc pops back.
- ~120 test assertions (56 smoke + 51 behaviour + integrity + picker shell).

Implements \`docs/plans/2026-04-24-001-layouts-example-plan.md\`.

## Findings

Findings from behaviour tests that pinned unexpected runtime behaviour are in \`docs/proposals/layout/\` (one file per finding, linked from the PR body if any exist).

## Test plan

- [ ] \`cd Examples/layouts && swift test\` — all green
- [ ] \`bun run test\` at repo root — all green
- [ ] \`swift run layouts-demo\` — picker launches, 56 rows across 16 categories, Esc pops detail back to picker, ⌃C quits cleanly
EOF
)"
```

---

## Self-review

Before handing off, run through the plan once more:

1. **Spec coverage.** Every section of the design doc should map to tasks:
   - Package shape → Task 1.
   - Core types → Task 2.
   - LayoutCatalog → Task 3.
   - App shell → Tasks 5-7.
   - Test strategy Tier 0 → Task 4. Tier 1 → Task 8 (harness) +
     every subsequent task appends an entry picked up by the
     parameterised test. Tier 3 (picker shell) → Task 25.
   - Layout taxonomy (§4) — 56 entries → Task 8 (entry #1) + Tasks
     9-24 (entries #2-56).
   - Risks — enforced by the "fail closed on behavior drift"
     language in Tasks 8, 10, and the category template.
2. **Placeholders.** No TBDs, no "implement later", no "add appropriate
   X". Where runtime behaviour is genuinely unknown (#13, #27, #30,
   #38, #42), the plan is explicit about pinning observed behaviour
   and recording a finding rather than guessing.
3. **Type consistency.** `LayoutEntry`, `LayoutCatalog`, `Category`,
   `TestTier`, `LayoutPicker`, `LayoutDetailHost`, `LayoutsApp`,
   `LayoutsRoot`, `render(_:width:height:id:)` — same spellings
   throughout.
4. **Budget sanity.** 25 tasks. Tasks 1-8 have complete code. Tasks
   9-24 are category dispatch briefs with per-layout invariant tables
   pointing at §4 of the design doc and Task 8's archetype. Task 25
   is end-to-end verify + PR open.

---

## Execution handoff

**Plan complete. Two execution options:**

1. **Subagent-Driven** (recommended) — I dispatch a fresh subagent
   per category task using
   `superpowers:subagent-driven-development`. Faster parallel
   execution, tighter per-subagent context, review between tasks.

2. **Inline Execution** — Execute tasks in this session using
   `superpowers:executing-plans`. Batch execution with checkpoints
   for review.

Which approach?


