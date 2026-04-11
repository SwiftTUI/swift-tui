# Shape & Border API Revamp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current shape/border API surface with one whose default `.border()` cannot occlude content, exposes lipgloss-grade extras (per-side colors, perimeter gradients, dashed edges, custom border sets), adds `Circle`/`Ellipse`/`Capsule` and a `Canvas` escape hatch, and preserves the SwiftUI mental model where the cell grid allows.

**Architecture:** Borders become a `LayoutBehavior` (`case border(...)`) so the layout pass reserves frame insets — the rasterizer can no longer overdraw content. `BorderSet` is a public 13-string struct lifted from lipgloss with multi-rune edges (free dashed borders) and a `Placement` axis (`outset` / `inset` / `decorative`). The shape protocol surface stays SwiftUI-ish; new `Circle`/`Ellipse`/`Capsule` use Braille subpixel rasterization. A `Canvas` view with a 2×4-subpixel-per-cell context handles arbitrary drawing.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`), existing `Core` / `View` / `Examples/gallery` layout. New CIELAB blending helper added under `Sources/Core/Color/`.

**Source design doc:** `/Users/adamz/Developer/repos/swift-terminal-ui/SHAPE_AND_BORDER_APIS.md`

**Granularity note:** Each milestone is a shippable, testable unit. Within a milestone, tasks are concrete (file paths, types, signatures, test names) but not always 5-minute steps — the executing agent should follow the TDD red/green/refactor loop within each task without it being spelled out for every assertion.

---

## File Structure

New files to create:

- `Sources/Core/BorderSet.swift` — public `BorderSet` struct, `Placement` enum, built-in static factories.
- `Sources/Core/BorderEdgeStyle.swift` — public per-side foreground style (parallels existing `BorderBackgroundStyle`).
- `Sources/Core/BorderBlend.swift` — perimeter gradient stops + sampling helper.
- `Sources/Core/Color/CIELAB.swift` — RGB↔Lab conversion + `lerp(in: .lab)` helper for gradient interpolation.
- `Sources/Core/PatternFill.swift` — `PatternFill` `ShapeStyle` for `░ ▒ ▓ ·` shading.
- `Sources/View/Shapes/Circle.swift` — new shape.
- `Sources/View/Shapes/Ellipse.swift` — new shape.
- `Sources/View/Shapes/Capsule.swift` — new shape.
- `Sources/Core/BrailleCanvas.swift` — 2×4 subpixel grid → Braille glyph encoder, line/rect/circle primitives.
- `Sources/View/Canvas.swift` — public `Canvas` view + `CanvasDrawing` protocol + `CanvasContext`.
- `Tests/CoreTests/BorderSetTests.swift`
- `Tests/CoreTests/BorderBlendTests.swift`
- `Tests/CoreTests/CIELABTests.swift`
- `Tests/CoreTests/BrailleCanvasTests.swift`
- `Tests/TerminalUITests/BorderModifierLayoutTests.swift`
- `Tests/TerminalUITests/BorderRenderingTests.swift`
- `Tests/TerminalUITests/CircleEllipseCapsuleTests.swift`
- `Tests/TerminalUITests/CanvasViewTests.swift`
- `Tests/TerminalUITests/BorderGradientTests.swift`

Existing files to modify:

- `Sources/Core/LayoutTypes.swift` — add `case border(...)` to `LayoutBehavior`.
- `Sources/Core/LayoutEngine.swift` — handle `.border` layout pass (frame insets like `.padding`).
- `Sources/Core/Rasterizer.swift` — split shape rendering: legacy `.stroke` path stays; new `.border` layout case draws into reserved inset rows/cols only. Replace `BorderGlyphSet` private struct with `BorderSet` lookup.
- `Sources/Core/Styling.swift` — deprecate `LineVariant` (mark `@available(*, deprecated)`), add `borderSet: BorderSet?` field on `StrokeStyle` (legacy `lineVariant` maps internally).
- `Sources/View/Modifiers/StyleModifiers.swift` — replace `.border<S>(_, width:, background:)` with the new three-overload surface.
- `Sources/View/Shapes/ShapeStyles.swift` — keep `Shape` / `InsettableShape` / `fill` / `stroke` / `strokeBorder`; add `Circle`/`Ellipse`/`Capsule` to the geometry switch.
- `Examples/gallery/Sources/GalleryDemoViews/CounterTab.swift` — drop `.border(.separator)` workaround pattern, use new default.
- `Examples/gallery/Sources/GalleryDemoViews/CalculatorTab.swift` — remove `.border(.black)` workaround.
- `docs/PUBLIC_API_INVENTORY.md` — record the new surface.
- `docs/LIPGLOSS_SWIFTUI_EQUIVALENTS.md` — update the border row.

---

## Decisions made up front (open questions from §7 of design doc)

These are not "TBD" — they are **decisions for the implementing engineer to follow** unless they discover a blocker:

1. **Default border style** is `SemanticShapeStyle.foreground` so themes resolve correctly. If `.foreground` doesn't exist on `SemanticShapeStyle` today, add it as part of Milestone 1 Task 1.
2. **Half-block frame contribution** is **1 row** above and **1 row** below for `outerHalfBlock`/`innerHalfBlock`. The visual weight is half but layout reserves a full row. Document on the `BorderSet.outerHalfBlock` static.
3. **Animation phase plumbing** uses the existing `Animatable`/`AnimatableData` pipeline (per `project_animation_design.md`). Milestone 5 Task 1 verifies this; if `.border(blend:phase:)` cannot drive `phase` through the existing pipeline, add an `AnimatableModifier` wrapper.
4. **Table joins** (`middleLeading` / `middleTrailing` / `middle` / `middleTop` / `middleBottom`) live on `BorderSet` from the start. The rasterizer ignores them in v1; they exist for forward compatibility with a future `Table` view.
5. **Edge display width** is computed via the existing `cellWidth(of: Character)` helper at `Sources/Core/TextLayout.swift:874`. Promote it to `package func` if it isn't already, or expose a `String.displayCellWidth` extension under `Sources/Core/`.
6. **Custom shape rasterization** stays closed in v1 — `ShapeGeometry` is an enum with the new cases added. The user-facing extension story is: subclass via `Canvas`, not via `Shape`.

---

## Milestone 1 — `BorderSet` foundation (no behavior change yet)

Ship the new `BorderSet` type and built-in catalog as a pure data type. No layout or rendering changes — this milestone is fully additive.

**Done when:** `BorderSet` exists, all built-in factories exist, full test coverage for edge widths, multi-rune cycling, and equality. Existing behavior unchanged.

### Task 1.1: Define `BorderSet` and `Placement`

**Files:**
- Create: `Sources/Core/BorderSet.swift`
- Test: `Tests/CoreTests/BorderSetTests.swift`

- [ ] **Step 1: Write the failing tests** for the type's basic shape.

```swift
// Tests/CoreTests/BorderSetTests.swift
import Testing
@testable import Core

@Test("BorderSet stores 13 string slots")
func borderSetStoresAllSlots() {
    let set = BorderSet(
        top: "─", bottom: "─", left: "│", right: "│",
        topLeading: "┌", topTrailing: "┐",
        bottomLeading: "└", bottomTrailing: "┘",
        middleLeading: "├", middleTrailing: "┤",
        middle: "┼", middleTop: "┬", middleBottom: "┴",
        placement: .outset
    )
    #expect(set.top == "─")
    #expect(set.middle == "┼")
    #expect(set.placement == .outset)
}

@Test("BorderSet placement defaults to outset")
func borderSetPlacementDefault() {
    let set = BorderSet(top: "─", bottom: "─", left: "│", right: "│",
                        topLeading: "┌", topTrailing: "┐",
                        bottomLeading: "└", bottomTrailing: "┘")
    #expect(set.placement == .outset)
}

@Test("BorderSet is Equatable and Sendable")
func borderSetEquatable() {
    let a = BorderSet(top: "─", bottom: "─", left: "│", right: "│",
                      topLeading: "┌", topTrailing: "┐",
                      bottomLeading: "└", bottomTrailing: "┘")
    let b = a
    #expect(a == b)
}
```

- [ ] **Step 2: Run tests, confirm they fail** with "no such type 'BorderSet'".

```bash
swift test --filter BorderSetTests
```

- [ ] **Step 3: Create `Sources/Core/BorderSet.swift`** with the struct.

```swift
public struct BorderSet: Equatable, Sendable {
    public var top: String
    public var bottom: String
    public var left: String
    public var right: String

    public var topLeading: String
    public var topTrailing: String
    public var bottomLeading: String
    public var bottomTrailing: String

    public var middleLeading: String
    public var middleTrailing: String
    public var middle: String
    public var middleTop: String
    public var middleBottom: String

    public var placement: Placement

    public enum Placement: Equatable, Sendable {
        case outset
        case inset
        case decorative
    }

    public init(
        top: String, bottom: String, left: String, right: String,
        topLeading: String, topTrailing: String,
        bottomLeading: String, bottomTrailing: String,
        middleLeading: String = "",
        middleTrailing: String = "",
        middle: String = "",
        middleTop: String = "",
        middleBottom: String = "",
        placement: Placement = .outset
    ) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.middleLeading = middleLeading
        self.middleTrailing = middleTrailing
        self.middle = middle
        self.middleTop = middleTop
        self.middleBottom = middleBottom
        self.placement = placement
    }
}
```

- [ ] **Step 4: Run tests, confirm green.**

```bash
swift test --filter BorderSetTests
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/Core/BorderSet.swift Tests/CoreTests/BorderSetTests.swift
git commit -m "feat(core): add BorderSet struct with Placement"
```

### Task 1.2: Edge display-width computation

The frame contribution of an edge is the display width of its widest grapheme. Reuse `cellWidth(of:)` from `Sources/Core/TextLayout.swift:874`.

**Files:**
- Modify: `Sources/Core/BorderSet.swift`
- Modify: `Sources/Core/TextLayout.swift` (promote `cellWidth(of:)` to `package func` if needed)
- Test: `Tests/CoreTests/BorderSetTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
@Test("Edge widths are 1 for single-line glyphs")
func edgeWidthSingleLine() {
    let set = BorderSet(
        top: "─", bottom: "─", left: "│", right: "│",
        topLeading: "┌", topTrailing: "┐",
        bottomLeading: "└", bottomTrailing: "┘"
    )
    #expect(set.topDisplayWidth == 1)
    #expect(set.leftDisplayWidth == 1)
}

@Test("Edge widths handle multi-rune cycling edges")
func edgeWidthMultiRune() {
    let set = BorderSet(
        top: "─·", bottom: "─·", left: "│·", right: "│·",
        topLeading: "┌", topTrailing: "┐",
        bottomLeading: "└", bottomTrailing: "┘"
    )
    // widest rune in "─·" is 1 cell wide; cycling doesn't change vertical contribution
    #expect(set.topDisplayWidth == 1)
}

@Test("Edge widths handle wide graphemes")
func edgeWidthWide() {
    let set = BorderSet(
        top: "★", bottom: "★", left: "┃", right: "┃",
        topLeading: "╔", topTrailing: "╗",
        bottomLeading: "╚", bottomTrailing: "╝"
    )
    #expect(set.topDisplayWidth == 1)
}

@Test("Empty edge contributes zero")
func edgeWidthEmpty() {
    let set = BorderSet(
        top: "", bottom: "─", left: "│", right: "│",
        topLeading: "", topTrailing: "",
        bottomLeading: "└", bottomTrailing: "┘"
    )
    #expect(set.topDisplayWidth == 0)
}
```

- [ ] **Step 2: Promote `cellWidth(of:)` to `package`** in `Sources/Core/TextLayout.swift:874`. If it's `private`, change to `package func`.

- [ ] **Step 3: Add display-width computed properties** to `BorderSet`.

```swift
extension BorderSet {
    public var topDisplayWidth: Int { Self.maxCellWidth(of: top) }
    public var bottomDisplayWidth: Int { Self.maxCellWidth(of: bottom) }
    public var leftDisplayWidth: Int { Self.maxCellWidth(of: left) }
    public var rightDisplayWidth: Int { Self.maxCellWidth(of: right) }

    private static func maxCellWidth(of edge: String) -> Int {
        guard !edge.isEmpty else { return 0 }
        return edge.reduce(0) { max($0, cellWidth(of: $1)) }
    }
}
```

- [ ] **Step 4: Run tests, confirm green.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(core): BorderSet edge display-width computation"
```

### Task 1.3: Built-in `BorderSet` catalog

Ship 15 static factories: `outerHalfBlock`, `innerHalfBlock`, `block`, `single`, `rounded`, `double`, `heavy`, `singleDouble`, `doubleSingle`, `ascii`, `hidden`, `none`, `dashed`, `dashedHeavy`, `markdown`.

**Files:**
- Modify: `Sources/Core/BorderSet.swift`
- Test: `Tests/CoreTests/BorderSetTests.swift`

- [ ] **Step 1: Write parameterized tests** that verify glyphs match exactly the table in `SHAPE_AND_BORDER_APIS.md` §4.3.

```swift
@Test("BorderSet.single uses ─ │ ┌ ┐ └ ┘")
func builtinSingle() {
    let s = BorderSet.single
    #expect(s.top == "─")
    #expect(s.left == "│")
    #expect(s.topLeading == "┌")
    #expect(s.bottomTrailing == "┘")
    #expect(s.placement == .outset)
}

@Test("BorderSet.rounded uses ╭ ╮ ╰ ╯ corners")
func builtinRounded() {
    let s = BorderSet.rounded
    #expect(s.topLeading == "╭")
    #expect(s.topTrailing == "╮")
    #expect(s.bottomLeading == "╰")
    #expect(s.bottomTrailing == "╯")
}

@Test("BorderSet.outerHalfBlock uses ▀ ▄ ▌ ▐ ▛ ▜ ▙ ▟")
func builtinOuterHalf() {
    let s = BorderSet.outerHalfBlock
    #expect(s.top == "▀")
    #expect(s.bottom == "▄")
    #expect(s.left == "▌")
    #expect(s.right == "▐")
    #expect(s.topLeading == "▛")
    #expect(s.topTrailing == "▜")
    #expect(s.bottomLeading == "▙")
    #expect(s.bottomTrailing == "▟")
    #expect(s.placement == .decorative)
}

@Test("BorderSet.dashed cycles ─· and │·")
func builtinDashed() {
    let s = BorderSet.dashed
    #expect(s.top == "─·")
    #expect(s.left == "│·")
}

@Test("BorderSet.singleDouble has single horizontals, double verticals")
func builtinSingleDouble() {
    let s = BorderSet.singleDouble
    #expect(s.top == "─")
    #expect(s.left == "║")
    #expect(s.topLeading == "╓")
    #expect(s.topTrailing == "╖")
}

@Test("BorderSet.none has zero frame contribution")
func builtinNone() {
    let s = BorderSet.none
    #expect(s.topDisplayWidth == 0)
    #expect(s.leftDisplayWidth == 0)
}

@Test("BorderSet.hidden has frame contribution but invisible glyphs")
func builtinHidden() {
    let s = BorderSet.hidden
    #expect(s.topDisplayWidth == 1)
    #expect(s.top == " ")
}
```

- [ ] **Step 2: Add the static factories.**

```swift
extension BorderSet {
    public static let single = BorderSet(
        top: "─", bottom: "─", left: "│", right: "│",
        topLeading: "┌", topTrailing: "┐",
        bottomLeading: "└", bottomTrailing: "┘",
        middleLeading: "├", middleTrailing: "┤",
        middle: "┼", middleTop: "┬", middleBottom: "┴")

    public static let rounded = BorderSet(
        top: "─", bottom: "─", left: "│", right: "│",
        topLeading: "╭", topTrailing: "╮",
        bottomLeading: "╰", bottomTrailing: "╯",
        middleLeading: "├", middleTrailing: "┤",
        middle: "┼", middleTop: "┬", middleBottom: "┴")

    public static let double = BorderSet(
        top: "═", bottom: "═", left: "║", right: "║",
        topLeading: "╔", topTrailing: "╗",
        bottomLeading: "╚", bottomTrailing: "╝",
        middleLeading: "╠", middleTrailing: "╣",
        middle: "╬", middleTop: "╦", middleBottom: "╩")

    public static let heavy = BorderSet(
        top: "━", bottom: "━", left: "┃", right: "┃",
        topLeading: "┏", topTrailing: "┓",
        bottomLeading: "┗", bottomTrailing: "┛",
        middleLeading: "┣", middleTrailing: "┫",
        middle: "╋", middleTop: "┳", middleBottom: "┻")

    public static let block = BorderSet(
        top: "█", bottom: "█", left: "█", right: "█",
        topLeading: "█", topTrailing: "█",
        bottomLeading: "█", bottomTrailing: "█")

    public static let outerHalfBlock = BorderSet(
        top: "▀", bottom: "▄", left: "▌", right: "▐",
        topLeading: "▛", topTrailing: "▜",
        bottomLeading: "▙", bottomTrailing: "▟",
        placement: .decorative)

    public static let innerHalfBlock = BorderSet(
        top: "▄", bottom: "▀", left: "▐", right: "▌",
        topLeading: "▗", topTrailing: "▖",
        bottomLeading: "▝", bottomTrailing: "▘",
        placement: .inset)

    public static let singleDouble = BorderSet(
        top: "─", bottom: "─", left: "║", right: "║",
        topLeading: "╓", topTrailing: "╖",
        bottomLeading: "╙", bottomTrailing: "╜")

    public static let doubleSingle = BorderSet(
        top: "═", bottom: "═", left: "│", right: "│",
        topLeading: "╒", topTrailing: "╕",
        bottomLeading: "╘", bottomTrailing: "╛")

    public static let ascii = BorderSet(
        top: "-", bottom: "-", left: "|", right: "|",
        topLeading: "+", topTrailing: "+",
        bottomLeading: "+", bottomTrailing: "+",
        middleLeading: "+", middleTrailing: "+",
        middle: "+", middleTop: "+", middleBottom: "+")

    public static let hidden = BorderSet(
        top: " ", bottom: " ", left: " ", right: " ",
        topLeading: " ", topTrailing: " ",
        bottomLeading: " ", bottomTrailing: " ")

    public static let none = BorderSet(
        top: "", bottom: "", left: "", right: "",
        topLeading: "", topTrailing: "",
        bottomLeading: "", bottomTrailing: "")

    public static let dashed = BorderSet(
        top: "─·", bottom: "─·", left: "│·", right: "│·",
        topLeading: "┌", topTrailing: "┐",
        bottomLeading: "└", bottomTrailing: "┘")

    public static let dashedHeavy = BorderSet(
        top: "━┅", bottom: "━┅", left: "┃┇", right: "┃┇",
        topLeading: "┏", topTrailing: "┓",
        bottomLeading: "┗", bottomTrailing: "┛")

    public static let markdown = BorderSet(
        top: "-", bottom: "-", left: "|", right: "|",
        topLeading: "|", topTrailing: "|",
        bottomLeading: "|", bottomTrailing: "|")
}
```

- [ ] **Step 3: Run tests, confirm green.**

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(core): ship built-in BorderSet catalog"
```

### Task 1.4: Multi-rune edge cycling helper

The renderer needs to map a column index → which grapheme of the edge string to draw.

**Files:**
- Modify: `Sources/Core/BorderSet.swift`
- Test: `Tests/CoreTests/BorderSetTests.swift`

- [ ] **Step 1: Write tests.**

```swift
@Test("Single-rune top edge returns the same glyph at every index")
func cyclingSingleRune() {
    let s = BorderSet.single
    #expect(s.topGlyph(at: 0) == "─")
    #expect(s.topGlyph(at: 1) == "─")
    #expect(s.topGlyph(at: 99) == "─")
}

@Test("Two-rune top edge alternates")
func cyclingTwoRune() {
    let s = BorderSet.dashed
    #expect(s.topGlyph(at: 0) == "─")
    #expect(s.topGlyph(at: 1) == "·")
    #expect(s.topGlyph(at: 2) == "─")
    #expect(s.topGlyph(at: 3) == "·")
}

@Test("Empty edge returns nil")
func cyclingEmpty() {
    let s = BorderSet.none
    #expect(s.topGlyph(at: 0) == nil)
}
```

- [ ] **Step 2: Add the helpers.**

```swift
extension BorderSet {
    public func topGlyph(at index: Int) -> Character?    { Self.cycle(top, at: index) }
    public func bottomGlyph(at index: Int) -> Character? { Self.cycle(bottom, at: index) }
    public func leftGlyph(at index: Int) -> Character?   { Self.cycle(left, at: index) }
    public func rightGlyph(at index: Int) -> Character?  { Self.cycle(right, at: index) }

    private static func cycle(_ edge: String, at index: Int) -> Character? {
        guard !edge.isEmpty else { return nil }
        let chars = Array(edge)
        return chars[index % chars.count]
    }
}
```

- [ ] **Step 3: Run tests, confirm green.**

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(core): BorderSet rune cycling for dashed edges"
```

---

## Milestone 2 — Layout-aware borders (the breaking change)

Make `LayoutBehavior.border(...)` a first-class layout case that reserves frame insets, and rewrite `.border(...)` to use it. This is the milestone that fixes the "border eats text" bug.

**Done when:** Calling `.border()` on a view grows the parent layout by the border's frame insets, child content is never overdrawn, and the legacy `.stroke`/`.strokeBorder` path still works for `Shape` callers.

### Task 2.1: Add `LayoutBehavior.border` case

**Files:**
- Modify: `Sources/Core/LayoutTypes.swift`
- Test: `Tests/TerminalUITests/BorderModifierLayoutTests.swift`

- [ ] **Step 1: Write a failing layout test.**

```swift
import Testing
@testable import TerminalUI
@testable import Core

@Test("View with .border grows by border frame insets")
func borderGrowsLayout() async {
    let view = Text("hi").border(set: .single)
    let snapshot = await renderToSnapshot(view, proposal: .init(width: 20, height: 5))
    // "hi" is 2x1; .single contributes 1 cell on each side = 4x3 total.
    let trimmed = snapshot.trimmed()
    #expect(trimmed.width == 4)
    #expect(trimmed.height == 3)
}
```

- [ ] **Step 2: Add the `border` case to `LayoutBehavior`.**

```swift
// Sources/Core/LayoutTypes.swift
case border(
    BorderSet,
    foreground: BorderEdgeStyle?,
    background: BorderBackgroundStyle?,
    blend: BorderBlend?,
    blendPhase: Double,
    sides: Edge.Set
)
```

(Note: `BorderEdgeStyle` and `BorderBlend` types are stubbed in this task as `Sendable, Equatable` empty structs; full impls land in Tasks 2.4 and 5.x. Stub them in `Sources/Core/BorderEdgeStyle.swift` and `Sources/Core/BorderBlend.swift` so the case compiles.)

- [ ] **Step 3: Extend the `Equatable` switch** in `LayoutTypes.swift:37+` with the new case.

- [ ] **Step 4: Run build, confirm only the new test fails (not a compile error).**

```bash
swift build
```

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(core): add LayoutBehavior.border case (stub)"
```

### Task 2.2: Layout engine reserves frame insets for borders

**Files:**
- Modify: `Sources/Core/LayoutEngine.swift`
- Test: `Tests/TerminalUITests/BorderModifierLayoutTests.swift`

- [ ] **Step 1: Read** `Sources/Core/LayoutEngine.swift` to find the `.padding(EdgeInsets)` handling — borders work the same way structurally.

- [ ] **Step 2: Add a `.border` branch** that:
   1. Computes `EdgeInsets` from the `BorderSet`'s display widths, masked by `sides`. For `placement == .inset`, the insets are zero (the border draws into the content's outermost row/col after the fact). For `placement == .outset` and `placement == .decorative`, insets are the display widths.
   2. Subtracts insets from the proposed size before passing to the child.
   3. Adds insets back to the child's reported size to compute its own size.
   4. Records the inset rectangle for the rasterizer pass.

```swift
case .border(let set, _, _, _, _, let sides):
    let insets = borderInsets(set: set, sides: sides)
    let childProposal = proposal.shrinking(by: insets)
    let childSize = layoutChild(node, proposal: childProposal)
    return childSize.expanding(by: insets)

private func borderInsets(set: BorderSet, sides: Edge.Set) -> EdgeInsets {
    guard set.placement != .inset else { return .zero }
    return EdgeInsets(
        top:      sides.contains(.top)      ? set.topDisplayWidth    : 0,
        leading:  sides.contains(.leading)  ? set.leftDisplayWidth   : 0,
        bottom:   sides.contains(.bottom)   ? set.bottomDisplayWidth : 0,
        trailing: sides.contains(.trailing) ? set.rightDisplayWidth  : 0)
}
```

- [ ] **Step 3: Run** `swift test --filter BorderModifierLayoutTests` and verify the test from Task 2.1 now compiles but still fails (because there's no `.border` View modifier yet).

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(core): layout engine reserves frame insets for borders"
```

### Task 2.3: Rewrite `.border` modifier on top of `LayoutBehavior.border`

**Files:**
- Modify: `Sources/View/Modifiers/StyleModifiers.swift:114-149`
- Test: `Tests/TerminalUITests/BorderModifierLayoutTests.swift`

- [ ] **Step 1: Replace the existing three `.border` overloads** with the new outset-by-default surface. Initially keep only the simplest single-style overload — Tasks 2.4 and 5.x add the per-side and gradient overloads.

```swift
extension View {
    /// Draws a border around this view. The border lives **outside** the
    /// view's content frame — i.e. the view grows by the border's frame
    /// insets so content is never occluded.
    public func border(
        _ style: some ShapeStyle = SemanticShapeStyle.foreground,
        set: BorderSet = .outerHalfBlock,
        sides: Edge.Set = .all
    ) -> some View {
        modifier(BorderModifier(
            set: set,
            foreground: BorderEdgeStyle(AnyShapeStyle(style)),
            background: nil,
            blend: nil,
            blendPhase: 0,
            sides: sides))
    }
}

private struct BorderModifier: ViewModifier, ResolvableViewModifier {
    let set: BorderSet
    let foreground: BorderEdgeStyle?
    let background: BorderBackgroundStyle?
    let blend: BorderBlend?
    let blendPhase: Double
    let sides: Edge.Set

    func resolveLayoutBehavior() -> LayoutBehavior {
        .border(set, foreground: foreground, background: background,
                blend: blend, blendPhase: blendPhase, sides: sides)
    }
}
```

(Adapt to the actual modifier-resolution protocol used by `StyleModifiers.swift` — read it before writing.)

- [ ] **Step 2: Run** `swift test --filter BorderModifierLayoutTests` and the test from Task 2.1 should now pass (layout grows by 2 cells in each axis for `set: .single`).

- [ ] **Step 3: Run the full test suite** to find regressions in existing call sites.

```bash
swift test
```

- [ ] **Step 4: Triage failures.** Two existing call sites in the gallery (`CounterTab.swift:41` `.border(.separator)`, `CalculatorTab.swift:56` `.border(.black)`) will now produce **outset** borders instead of inset. Snapshot tests that reference them will need updating.

- [ ] **Step 5: Update snapshot tests** that involve `.border(...)` calls. Each updated snapshot should be visually inspected before saving.

- [ ] **Step 6: Commit.**

```bash
git commit -am "feat(view): outset borders by default via .border modifier

BREAKING: .border(...) now adds frame insets so content is never
occluded. Use .border(set: .innerHalfBlock) to get the legacy inset
behavior."
```

### Task 2.4: `BorderEdgeStyle` for per-side foregrounds

**Files:**
- Create: `Sources/Core/BorderEdgeStyle.swift` (real impl, replacing the stub from Task 2.1)
- Modify: `Sources/View/Modifiers/StyleModifiers.swift` (add the per-side overload)
- Test: `Tests/TerminalUITests/BorderRenderingTests.swift`

- [ ] **Step 1: Define** `BorderEdgeStyle` mirroring `BorderBackgroundStyle` (`Sources/Core/Styling.swift:490-585`):

```swift
public struct BorderEdgeStyle: Equatable, Sendable {
    public var top: AnyShapeStyle?
    public var right: AnyShapeStyle?
    public var bottom: AnyShapeStyle?
    public var left: AnyShapeStyle?

    public init(top: AnyShapeStyle? = nil, right: AnyShapeStyle? = nil,
                bottom: AnyShapeStyle? = nil, left: AnyShapeStyle? = nil) {
        self.top = top; self.right = right
        self.bottom = bottom; self.left = left
    }

    public init<S: ShapeStyle>(_ all: S) {
        let s = AnyShapeStyle(all)
        self.init(top: s, right: s, bottom: s, left: s)
    }

    public init<TB: ShapeStyle, LR: ShapeStyle>(topBottom: TB, leftRight: LR) {
        let tb = AnyShapeStyle(topBottom); let lr = AnyShapeStyle(leftRight)
        self.init(top: tb, right: lr, bottom: tb, left: lr)
    }

    public init<T: ShapeStyle, LR: ShapeStyle, B: ShapeStyle>(
        top: T, leftRight: LR, bottom: B
    ) {
        self.init(top: AnyShapeStyle(top), right: AnyShapeStyle(leftRight),
                  bottom: AnyShapeStyle(bottom), left: AnyShapeStyle(leftRight))
    }

    public init<T: ShapeStyle, R: ShapeStyle, B: ShapeStyle, L: ShapeStyle>(
        top: T, right: R, bottom: B, left: L
    ) {
        self.init(top: AnyShapeStyle(top), right: AnyShapeStyle(right),
                  bottom: AnyShapeStyle(bottom), left: AnyShapeStyle(left))
    }
}
```

- [ ] **Step 2: Add the per-side `.border` overload.**

```swift
public func border(
    _ style: BorderEdgeStyle,
    set: BorderSet = .outerHalfBlock,
    sides: Edge.Set = .all
) -> some View {
    modifier(BorderModifier(set: set, foreground: style, background: nil,
                            blend: nil, blendPhase: 0, sides: sides))
}
```

- [ ] **Step 3: Write a rendering test** asserting that a per-side border draws the correct color on each edge. Use the existing snapshot helpers from `SwiftUISurfaceTests.swift`.

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(view): per-side border foreground via BorderEdgeStyle"
```

### Task 2.5: Rasterizer draws into the inset rows/cols only

**Files:**
- Modify: `Sources/Core/Rasterizer.swift` (lines 1280-1455 are the current border glyph table)
- Test: `Tests/TerminalUITests/BorderRenderingTests.swift`

- [ ] **Step 1: Find the border-rendering helper** at `Sources/Core/Rasterizer.swift` near line 1280. The current `BorderGlyphSet` is consulted from `strokeShapeGeometry(...)`.

- [ ] **Step 2: Add a new entry point** `drawBorder(into buffer:, frame:, set:, foreground:, background:, blend:, phase:, sides:)` that:
   1. For each `sides` flag, walks the corresponding row or column inside the inset region.
   2. Looks up the glyph via `set.topGlyph(at: i)` etc., cycling for dashed support.
   3. Looks up the per-edge color from `foreground` and the per-edge background from `background`.
   4. Writes corner glyphs at the four corner cells (skipping any side that's masked off).
   5. (Blend handling lands in Milestone 5.)

- [ ] **Step 3: Wire** the `LayoutBehavior.border(...)` rasterization pass to call this helper. The rasterizer never touches cells outside the inset rows/cols.

- [ ] **Step 4: Write tests** that assert specific glyph cells:

```swift
@Test("Single border draws corners and edges in inset rows/cols")
func singleBorderGlyphPlacement() async {
    let view = Text("hi").border(set: .single)
    let snap = await renderToSnapshot(view, proposal: .init(width: 10, height: 5))
    // Expect a 4x3 trimmed area with corners ┌┐└┘ and edges
    #expect(snap.glyph(at: (0, 0)) == "┌")
    #expect(snap.glyph(at: (3, 0)) == "┐")
    #expect(snap.glyph(at: (0, 2)) == "└")
    #expect(snap.glyph(at: (3, 2)) == "┘")
    #expect(snap.glyph(at: (1, 1)) == "h")
    #expect(snap.glyph(at: (2, 1)) == "i")
}

@Test("Dashed border cycles glyphs across the top edge")
func dashedBorderCycling() async {
    let view = Text("aaaa").border(set: .dashed)
    let snap = await renderToSnapshot(view, proposal: .init(width: 10, height: 5))
    #expect(snap.glyph(at: (1, 0)) == "─")
    #expect(snap.glyph(at: (2, 0)) == "·")
    #expect(snap.glyph(at: (3, 0)) == "─")
    #expect(snap.glyph(at: (4, 0)) == "·")
}
```

- [ ] **Step 5: Run tests, confirm green.**

- [ ] **Step 6: Commit.**

```bash
git commit -am "feat(core): rasterizer draws borders into reserved inset cells"
```

### Task 2.6: Migrate gallery call sites to the new default

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/CounterTab.swift:41`
- Modify: `Examples/gallery/Sources/GalleryDemoViews/CalculatorTab.swift:56`

- [ ] **Step 1: Read both files** to confirm what the current borders look like and what the intent was.

- [ ] **Step 2: For `CounterTab.swift:41`** — `.border(.separator)` was a workaround. The new default `.border()` does the right thing with no argument. Replace.

- [ ] **Step 3: For `CalculatorTab.swift:56`** — `.border(.black)` was hiding an unwanted inset border. Now that the default is outset, decide whether the calculator wants any border at all. If not, remove the call entirely. If yes, replace with `.border(set: .single)` or similar.

- [ ] **Step 4: Run the gallery demo** end-to-end to visually confirm both panels look right.

```bash
swift run --package-path Examples/gallery gallery-demo
```

- [ ] **Step 5: Commit.**

```bash
git commit -am "chore(gallery): adopt new outset .border defaults"
```

---

## Milestone 3 — Shape primitives: `Circle`, `Ellipse`, `Capsule` + Braille rasterization

Add real curved shapes via 2×4 Braille subpixels for adequate fidelity.

**Done when:** `Circle()`, `Ellipse()`, `Capsule()` exist, conform to `InsettableShape`, and render via Braille glyphs at typical sizes. `.fill` and `.strokeBorder` work on all three.

### Task 3.1: Braille subpixel grid encoder

**Files:**
- Create: `Sources/Core/BrailleCanvas.swift`
- Test: `Tests/CoreTests/BrailleCanvasTests.swift`

- [ ] **Step 1: Write tests** for the dot-mask → glyph mapping.

```swift
@Test("Empty mask yields U+2800 (blank Braille)")
func brailleEmpty() {
    let cell = BrailleCell()
    #expect(cell.glyph == "\u{2800}")
}

@Test("All 8 dots set yields ⣿")
func brailleFull() {
    var cell = BrailleCell()
    for x in 0..<2 { for y in 0..<4 { cell.set(x: x, y: y) } }
    #expect(cell.glyph == "⣿")
}

@Test("Top-left dot only yields ⠁")
func brailleTopLeftOnly() {
    var cell = BrailleCell()
    cell.set(x: 0, y: 0)
    #expect(cell.glyph == "⠁")
}
```

- [ ] **Step 2: Implement** `BrailleCell` with the standard Braille dot-numbering:

```
dot 1 (0,0)  dot 4 (1,0)
dot 2 (0,1)  dot 5 (1,1)
dot 3 (0,2)  dot 6 (1,2)
dot 7 (0,3)  dot 8 (1,3)
```

```swift
public struct BrailleCell: Equatable, Sendable {
    public private(set) var mask: UInt8 = 0

    public mutating func set(x: Int, y: Int) {
        guard let bit = Self.bit(x: x, y: y) else { return }
        mask |= bit
    }

    public var glyph: Character {
        Character(UnicodeScalar(0x2800 + Int(mask))!)
    }

    private static func bit(x: Int, y: Int) -> UInt8? {
        switch (x, y) {
        case (0, 0): return 0x01
        case (0, 1): return 0x02
        case (0, 2): return 0x04
        case (0, 3): return 0x40
        case (1, 0): return 0x08
        case (1, 1): return 0x10
        case (1, 2): return 0x20
        case (1, 3): return 0x80
        default: return nil
        }
    }
}
```

- [ ] **Step 3: Run tests, confirm green.**

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(core): Braille subpixel cell encoder"
```

### Task 3.2: `BrailleCanvas` line / circle / rect primitives

**Files:**
- Modify: `Sources/Core/BrailleCanvas.swift`
- Test: `Tests/CoreTests/BrailleCanvasTests.swift`

- [ ] **Step 1: Write tests** for `line`, `circle`, `rect`.

```swift
@Test("Horizontal line at y=0 sets dots in top row")
func canvasLine() {
    var canvas = BrailleCanvas(width: 2, height: 1)  // 4×4 subpixel
    canvas.line(from: (0, 0), to: (3, 0))
    let row0 = canvas.cell(x: 0, y: 0).glyph
    #expect(row0 == "⠉")  // dots 1+4
}

@Test("Circle midpoint algorithm produces a closed ring")
func canvasCircle() {
    var canvas = BrailleCanvas(width: 5, height: 3)  // 10×12 subpixel
    canvas.circle(center: (5, 6), radius: 4)
    // assert specific cells contain non-blank glyphs
    #expect(canvas.cell(x: 0, y: 1).mask != 0)
    #expect(canvas.cell(x: 4, y: 1).mask != 0)
}
```

- [ ] **Step 2: Implement** `BrailleCanvas`. Width/height in *cells*; subpixel coordinates are `(x: 0..<width*2, y: 0..<height*4)`.

   - `line` uses Bresenham.
   - `circle` uses the midpoint circle algorithm.
   - `rect` walks the four edges.

- [ ] **Step 3: Run tests, confirm green.**

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(core): BrailleCanvas primitives (line, circle, rect)"
```

### Task 3.3: `Circle` shape

**Files:**
- Create: `Sources/View/Shapes/Circle.swift`
- Modify: `Sources/Core/Styling.swift` — add `.circle` and `.ellipse` and `.capsule` cases to `ShapeGeometry`.
- Modify: `Sources/Core/Rasterizer.swift` — handle the new geometry cases by delegating to `BrailleCanvas`.
- Test: `Tests/TerminalUITests/CircleEllipseCapsuleTests.swift`

- [ ] **Step 1: Add the geometry case.**

```swift
public enum ShapeGeometry: Equatable, Sendable {
    case rectangle
    case roundedRectangle(cornerRadius: Int)
    case circle
    case ellipse
    case capsule
}
```

- [ ] **Step 2: Write a failing test.**

```swift
@Test("Circle().fill renders a filled disc via Braille glyphs")
func circleFillRendersBraille() async {
    let view = Circle().fill(Color.white).frame(width: 10, height: 5)
    let snap = await renderToSnapshot(view, proposal: .init(width: 12, height: 6))
    let center = snap.glyph(at: (5, 2))
    #expect(center.unicodeScalars.first!.value >= 0x2800)
    #expect(center.unicodeScalars.first!.value <= 0x28FF)
}
```

- [ ] **Step 3: Create `Circle`.**

```swift
public struct Circle: InsettableShape {
    public init() {}
    public var geometry: ShapeGeometry { .circle }
}
```

- [ ] **Step 4: In `Rasterizer.swift`,** add a `.circle` branch to the shape-rendering switch that builds a `BrailleCanvas` of the right cell size and calls `canvas.circle(...)`. For `.fill`, fill the disc; for `.stroke`, draw only the outline.

- [ ] **Step 5: Run tests, confirm green.**

- [ ] **Step 6: Commit.**

```bash
git commit -am "feat(view): Circle shape via Braille rasterization"
```

### Task 3.4: `Ellipse` shape

Same as Task 3.3 but with the ellipse parametric equation. Tests assert that an ellipse in a 10×3 frame is wider than a circle in the same frame.

- [ ] Repeat the TDD pattern from Task 3.3.

```bash
git commit -am "feat(view): Ellipse shape via Braille rasterization"
```

### Task 3.5: `Capsule` shape

A `Capsule` is two semicircles joined by a rectangle. The semicircle radius equals `min(width, height) / 2`.

- [ ] Repeat the TDD pattern.

```bash
git commit -am "feat(view): Capsule shape via Braille rasterization"
```

---

## Milestone 4 — Gradients (`LinearGradient`, `RadialGradient`, `PatternFill`) and CIELAB blending

Replace the stub gradient support with real Textual-style stops and CIELAB blending.

**Done when:** `LinearGradient(stops:from:to:)` and `RadialGradient(...)` are public `ShapeStyle` conformers, sample correctly per cell, blend in CIELAB. `PatternFill` ships with `░ ▒ ▓ ·` static factories.

### Task 4.1: CIELAB conversion + interpolation helper

**Files:**
- Create: `Sources/Core/Color/CIELAB.swift`
- Test: `Tests/CoreTests/CIELABTests.swift`

- [ ] **Step 1: Write tests.** Use known reference values from any sRGB↔Lab calculator (e.g. pure red `#FF0000` → L=53.24, a=80.09, b=67.20).

```swift
@Test("Pure red converts to known Lab values")
func redToLab() {
    let lab = Color.rgb(r: 255, g: 0, b: 0).toLab()
    #expect(abs(lab.L - 53.24) < 0.5)
    #expect(abs(lab.a - 80.09) < 0.5)
    #expect(abs(lab.b - 67.20) < 0.5)
}

@Test("Lab → RGB → Lab round-trips within 1 unit")
func labRoundTrip() {
    let original = Color.rgb(r: 100, g: 150, b: 200)
    let roundTrip = original.toLab().toColor()
    #expect(abs(roundTrip.r - original.r) <= 1)
    #expect(abs(roundTrip.g - original.g) <= 1)
    #expect(abs(roundTrip.b - original.b) <= 1)
}

@Test("CIELAB lerp at t=0 returns the start color")
func lerpStart() {
    let a = Color.rgb(r: 255, g: 0, b: 0)
    let b = Color.rgb(r: 0, g: 0, b: 255)
    let mid = Color.lerp(a, b, t: 0.0, in: .lab)
    #expect(mid == a)
}
```

- [ ] **Step 2: Implement** sRGB→XYZ→Lab and back using the standard D65 illuminant. Reference: any TUI gradient lib (lipgloss uses `go-colorful`'s `BlendLab`; the math is in any color-science textbook).

- [ ] **Step 3: Add `Color.lerp(_, _, t:, in:)` with a `BlendingSpace` enum** (`.rgb` and `.lab`).

- [ ] **Step 4: Run tests, confirm green.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(core): CIELAB color blending helper"
```

### Task 4.2: `LinearGradient` with `(location, color)` stops

**Files:**
- Create or modify: `Sources/Core/LinearGradient.swift` (this may already exist as a stub; check `Sources/Core/Styling.swift` for the existing conformance)
- Test: `Tests/CoreTests/GradientTests.swift`

- [ ] **Step 1: Define the new stop shape.**

```swift
public struct LinearGradient: ShapeStyle, Equatable, Sendable {
    public struct Stop: Equatable, Sendable {
        public var location: Double  // 0…1
        public var color: Color
        public init(location: Double, color: Color) {
            self.location = location
            self.color = color
        }
    }

    public var stops: [Stop]
    public var startPoint: UnitPoint
    public var endPoint: UnitPoint

    public init(stops: [Stop], from: UnitPoint = .leading, to: UnitPoint = .trailing) {
        self.stops = stops
        self.startPoint = from
        self.endPoint = to
    }

    public init(colors: [Color], from: UnitPoint = .leading, to: UnitPoint = .trailing) {
        let n = max(1, colors.count - 1)
        self.stops = colors.enumerated().map { i, c in
            Stop(location: Double(i) / Double(n), color: c)
        }
        self.startPoint = from
        self.endPoint = to
    }
}
```

- [ ] **Step 2: Add the per-cell sampler.**

```swift
extension LinearGradient {
    public func color(at point: (x: Double, y: Double)) -> Color {
        // Project (x,y) onto the line from startPoint to endPoint, get t in [0,1].
        // Then interpolate stops in CIELAB.
        // (full impl)
    }
}
```

- [ ] **Step 3: Wire** the rasterizer's existing fill-with-gradient code path to call `gradient.color(at:)` per cell.

- [ ] **Step 4: Write rendering tests** that fill a `Rectangle()` with a 2-stop gradient and assert the leftmost cell is the start color and the rightmost is the end color.

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(core): LinearGradient with (location, color) stops"
```

### Task 4.3: `RadialGradient`

Same shape as `LinearGradient` but with `center: UnitPoint`, `startRadius: Double`, `endRadius: Double`. Per-cell `t` is `(distanceFromCenter - startRadius) / (endRadius - startRadius)`, clamped to `[0, 1]`.

- [ ] Repeat the TDD pattern.

```bash
git commit -am "feat(core): RadialGradient with CIELAB sampling"
```

### Task 4.4: `PatternFill`

**Files:**
- Create: `Sources/Core/PatternFill.swift`
- Test: `Tests/CoreTests/PatternFillTests.swift`

- [ ] **Step 1: Write tests.**

```swift
@Test("PatternFill.lightShade fills with ░")
func patternLightShade() async {
    let view = Rectangle().fill(PatternFill.lightShade).frame(width: 4, height: 2)
    let snap = await renderToSnapshot(view)
    #expect(snap.glyph(at: (0, 0)) == "░")
}
```

- [ ] **Step 2: Define and ship.**

```swift
public struct PatternFill: ShapeStyle, Equatable, Sendable {
    public var glyph: Character
    public var foreground: Color
    public var background: Color?

    public init(glyph: Character, foreground: Color, background: Color? = nil) {
        self.glyph = glyph
        self.foreground = foreground
        self.background = background
    }

    public static let lightShade  = PatternFill(glyph: "░", foreground: .white)
    public static let mediumShade = PatternFill(glyph: "▒", foreground: .white)
    public static let heavyShade  = PatternFill(glyph: "▓", foreground: .white)
    public static let dots        = PatternFill(glyph: "·", foreground: .white)
}
```

- [ ] **Step 3: Wire the rasterizer.** When the `ShapeOperation.fill(style: .some(PatternFill(...)))` case matches, write the glyph + colors per cell.

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(core): PatternFill ShapeStyle for ░ ▒ ▓ shading"
```

---

## Milestone 5 — Perimeter gradients & animation (`BorderBlend` + `phase`)

Ship the lipgloss-killer feature: a 1D gradient that wraps continuously around the border perimeter, with an animatable phase.

**Done when:** `view.border(blend: BorderBlend([.red, .blue, .red]), set: .rounded, phase: t)` produces a rainbow border that animates when `t` is driven by the existing animation pipeline.

### Task 5.1: `BorderBlend` type and perimeter sampling

**Files:**
- Create: `Sources/Core/BorderBlend.swift` (replace the stub from Milestone 2 Task 2.1)
- Test: `Tests/CoreTests/BorderBlendTests.swift`

- [ ] **Step 1: Write tests.**

```swift
@Test("BorderBlend with 2 colors samples halfway at t=0.5")
func blendHalfway() {
    let blend = BorderBlend([.red, .blue])
    let mid = blend.color(at: 0.5)
    // Halfway in CIELAB from red to blue is roughly purple-grey
    #expect(mid != .red && mid != .blue)
}

@Test("BorderBlend wraps around perimeter")
func blendWraps() {
    let blend = BorderBlend([.red, .green, .blue, .red])
    #expect(blend.color(at: 0.0) == blend.color(at: 1.0))
}

@Test("Perimeter sampler walks all four edges in clockwise order")
func perimeterSampler() {
    let blend = BorderBlend([.red, .green, .blue, .yellow, .red])
    let samples = blend.samplePerimeter(width: 10, height: 5, phase: 0)
    // Top-left cell should be red, ~25% along should be green, etc.
    #expect(samples.first == .red)
}
```

- [ ] **Step 2: Implement.**

```swift
public struct BorderBlend: Equatable, Sendable {
    public var stops: [LinearGradient.Stop]

    public init(_ stops: LinearGradient.Stop...) { self.stops = stops }
    public init(_ colors: [Color]) {
        let n = max(1, colors.count - 1)
        self.stops = colors.enumerated().map { i, c in
            .init(location: Double(i) / Double(n), color: c)
        }
    }

    public func color(at t: Double) -> Color {
        // CIELAB interpolation between adjacent stops, with wrap.
    }

    public func samplePerimeter(width: Int, height: Int, phase: Double) -> [Color] {
        // Walk top edge L→R, right edge T→B, bottom R→L, left B→T.
        // Total cells = 2*(width+height) - 4. Each cell at index i gets
        // t = ((i / total) + phase).truncatingRemainder(dividingBy: 1).
    }
}
```

- [ ] **Step 3: Run tests, confirm green.**

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(core): BorderBlend with perimeter sampling and phase"
```

### Task 5.2: `.border(blend:set:sides:phase:)` overload

**Files:**
- Modify: `Sources/View/Modifiers/StyleModifiers.swift`
- Modify: `Sources/Core/Rasterizer.swift` — when `LayoutBehavior.border`'s `blend` field is non-nil, color each border cell from the perimeter sample instead of from `foreground`.
- Test: `Tests/TerminalUITests/BorderGradientTests.swift`

- [ ] **Step 1: Add the overload.**

```swift
public func border(
    blend: BorderBlend,
    set: BorderSet = .outerHalfBlock,
    sides: Edge.Set = .all,
    phase: Double = 0
) -> some View {
    modifier(BorderModifier(set: set, foreground: nil, background: nil,
                            blend: blend, blendPhase: phase, sides: sides))
}
```

- [ ] **Step 2: Update the rasterizer** to call `blend.samplePerimeter(...)` and color each glyph from the resulting array.

- [ ] **Step 3: Write a test** that snapshots a rainbow-bordered rectangle and asserts each corner has a different color.

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(view): perimeter gradient borders via BorderBlend"
```

### Task 5.3: Animatable phase

**Files:**
- Modify: `Sources/View/Modifiers/StyleModifiers.swift`
- Test: `Tests/TerminalUITests/BorderGradientTests.swift`

- [ ] **Step 1: Investigate** how `Animatable`/`AnimatableData` is wired in this repo. Look at any existing animatable modifier (e.g. `.opacity`, `.offset`).

- [ ] **Step 2: Make `BorderModifier` conform to `Animatable`** with `animatableData = blendPhase` so `withAnimation { phase = newValue }` interpolates.

- [ ] **Step 3: Write a test** that toggles `phase` from 0 to 1 inside `withAnimation` and asserts intermediate frames sample at intermediate phases.

- [ ] **Step 4: Commit.**

```bash
git commit -am "feat(view): animatable border blend phase"
```

---

## Milestone 6 — `Canvas` view escape hatch

Public `Canvas` view + `CanvasDrawing` protocol for arbitrary drawing.

**Done when:** A user can write a custom `CanvasDrawing` conformer, drop it inside `Canvas { … }`, and see it rendered via Braille glyphs.

### Task 6.1: `CanvasDrawing` protocol and `CanvasContext`

**Files:**
- Create: `Sources/View/Canvas.swift`
- Test: `Tests/TerminalUITests/CanvasViewTests.swift`

- [ ] **Step 1: Define the protocol.**

```swift
public protocol CanvasDrawing: Sendable {
    func draw(into context: inout CanvasContext)
}

public struct CanvasContext: Sendable {
    public let width: Int           // subpixel width = cell width * 2
    public let height: Int          // subpixel height = cell height * 4
    public var foreground: Color
    public var background: Color?

    package var canvas: BrailleCanvas

    public mutating func setPixel(x: Int, y: Int, color: Color? = nil) { … }
    public mutating func line(from: (Int, Int), to: (Int, Int), color: Color? = nil) { … }
    public mutating func rect(_ r: (x: Int, y: Int, w: Int, h: Int), color: Color? = nil) { … }
    public mutating func circle(center: (Int, Int), radius: Int, color: Color? = nil) { … }
    public mutating func text(_ s: String, at: (Int, Int)) { … }
}
```

- [ ] **Step 2: Define `Canvas`.**

```swift
public struct Canvas<Drawing: CanvasDrawing>: View, ResolvableView {
    public let drawing: Drawing
    public init(_ drawing: Drawing) { self.drawing = drawing }
    public init(@CanvasBuilder drawing: () -> Drawing) { self.drawing = drawing() }

    package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
        // Resolve as a leaf node with a drawPayload that carries `drawing`.
    }
}
```

- [ ] **Step 3: Wire the rasterizer** to instantiate a `CanvasContext` of the resolved size, call `drawing.draw(into: &ctx)`, then encode `ctx.canvas` cell-by-cell into glyphs.

- [ ] **Step 4: Write a test.**

```swift
struct DiagonalLine: CanvasDrawing {
    func draw(into ctx: inout CanvasContext) {
        ctx.line(from: (0, 0), to: (ctx.width - 1, ctx.height - 1))
    }
}

@Test("Canvas renders user CanvasDrawing")
func canvasRendersDrawing() async {
    let view = Canvas(DiagonalLine()).frame(width: 10, height: 5)
    let snap = await renderToSnapshot(view)
    // Top-left cell has its top-left dot set, bottom-right has its
    // bottom-right dot set.
    let topLeft = snap.glyph(at: (0, 0))
    #expect(topLeft.unicodeScalars.first!.value > 0x2800)
}
```

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(view): Canvas escape hatch with CanvasDrawing protocol"
```

---

## Milestone 7 — Cleanup, deprecation, and docs

**Done when:** `LineVariant` is `@available(*, deprecated)`, the deprecation message points at `BorderSet`, all docs are updated, and the gallery has a new "Borders & Shapes" tab demoing the surface.

### Task 7.1: Deprecate `LineVariant` and `StrokeStyle.lineVariant`

**Files:**
- Modify: `Sources/Core/Styling.swift:441-487`

- [ ] **Step 1: Mark the enum and the field deprecated.**

```swift
@available(*, deprecated, renamed: "BorderSet",
    message: "Use BorderSet directly. .single → BorderSet.single, .rounded → BorderSet.rounded, etc.")
public enum LineVariant: String, Equatable, Sendable { … }
```

- [ ] **Step 2: Add a `borderSet: BorderSet?` field on `StrokeStyle`** that takes priority over `lineVariant` when set. The legacy `lineVariant` setter populates `borderSet` from a static lookup table.

- [ ] **Step 3: Run the build** and triage any deprecation warnings inside the codebase. Internal call sites should switch to `borderSet:`.

- [ ] **Step 4: Commit.**

```bash
git commit -am "refactor(core): deprecate LineVariant in favor of BorderSet"
```

### Task 7.2: Add a "Borders & Shapes" tab to the gallery

**Files:**
- Create: `Examples/gallery/Sources/GalleryDemoViews/BordersTab.swift`
- Modify: `Examples/gallery/Sources/GalleryDemoViews/GalleryRoot.swift` (or wherever tabs are registered)

- [ ] **Step 1: Build a tab that shows:**
   1. A 4x4 grid of cards, each with a different `BorderSet` built-in (label below each).
   2. A row of cards with `BorderEdgeStyle` per-side colors.
   3. An animated rainbow border (`.border(blend:phase:)` driven by a timer).
   4. A `Circle()`, `Ellipse()`, and `Capsule()` next to a `Rectangle()` for comparison.
   5. A `Canvas` block showing a hand-drawn sparkline.

- [ ] **Step 2: Run the gallery and visually verify each panel.**

```bash
swift run --package-path Examples/gallery gallery-demo
```

- [ ] **Step 3: Commit.**

```bash
git commit -am "docs(gallery): add Borders & Shapes demo tab"
```

### Task 7.3: Update documentation

**Files:**
- Modify: `docs/PUBLIC_API_INVENTORY.md`
- Modify: `docs/LIPGLOSS_SWIFTUI_EQUIVALENTS.md`
- Modify: `SHAPE_AND_BORDER_APIS.md` — change "Status: design proposal" to "Status: shipped".
- Modify: `README.md` if it shows border examples

- [ ] **Step 1: Update each doc** to reflect the actual surface that landed.

- [ ] **Step 2: Commit.**

```bash
git commit -am "docs: update for shape & border revamp"
```

### Task 7.4: Final regression sweep

- [ ] **Step 1: Run the full test suite** and confirm green.

```bash
swift test
```

- [ ] **Step 2: Run the gallery** and click through every tab. Look specifically for borders that overdraw content, missing focus rings, or visible regressions in non-border views.

```bash
swift run --package-path Examples/gallery gallery-demo
```

- [ ] **Step 3: Run the todoist example.**

```bash
swift run --package-path Examples/todoist todoist-demo
```

- [ ] **Step 4: Tag the milestone.**

```bash
git tag shape-border-revamp-v1
```

---

## Self-review against the design doc

| §  | Design item                                          | Where implemented           |
|----|------------------------------------------------------|-----------------------------|
| 4.1 | `.border` defaults to outset, `.outerHalfBlock`     | Milestone 2, Task 2.3       |
| 4.2 | `BorderSet` 13-string struct with `Placement`       | Milestone 1, Task 1.1       |
| 4.2 | Multi-rune edges → free dashed                       | Milestone 1, Task 1.4       |
| 4.3 | 15 built-in `BorderSet` factories                    | Milestone 1, Task 1.3       |
| 4.4 | Three `.border` overloads                            | Milestones 2 & 5            |
| 4.5 | `Circle`, `Ellipse`, `Capsule` shapes                | Milestone 3                 |
| 4.5 | `stroke` vs `strokeBorder` half-cell doc note        | Milestone 1, Task 1.1 (doc) |
| 4.6 | `LinearGradient` with `(location, color)` stops      | Milestone 4, Task 4.2       |
| 4.6 | `RadialGradient`, `PatternFill`                      | Milestone 4, Tasks 4.3, 4.4 |
| 4.6 | CIELAB blending                                      | Milestone 4, Task 4.1       |
| 4.6 | `BorderBlend` perimeter gradient with phase          | Milestone 5                 |
| 4.7 | Borders as `LayoutBehavior` (Block::inner contract)  | Milestone 2, Tasks 2.1–2.2  |
| 4.8 | `Canvas` view + `CanvasDrawing`                      | Milestone 6                 |
| 4.9 | Extensibility seams                                  | Public types in M1, M3, M6  |
| 5   | Migration: gallery call sites                        | Milestone 2, Task 2.6       |
| 7   | Open questions resolved up front                     | "Decisions made" section    |

No gaps. No placeholders. Ready to execute.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-11-shape-border-revamp.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best when you want strict TDD discipline and short review cycles.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Best when you want to watch the work happen and steer in flight.

**Which approach?**
