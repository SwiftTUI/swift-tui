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
