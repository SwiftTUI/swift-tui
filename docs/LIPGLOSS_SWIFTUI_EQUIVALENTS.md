# Lip Gloss to SwiftUI Equivalents

## Why This Document Exists

[Lip Gloss](https://github.com/charmbracelet/lipgloss) and
[Bubble Tea](https://github.com/charmbracelet/bubbletea) are used as aesthetic
guidance and as a signal for which components matter most in TUI applications.
We do not adopt their abstractions, but we read them as evidence: when Lip
Gloss ships a first-class `tree` package, that tells us hierarchical tree
display is important enough to treat seriously in TerminalUI.

The most important lesson is not "copy Lip Gloss styling." The stronger lesson
is that terminal styling should be composable, capability-aware, and applied
with restraint. Modern terminal-native apps usually treat the terminal
background as the canvas, keep borders structural rather than decorative, and
make focus, selection, help, and mode more prominent than ornamental chrome.

This document maps Lip Gloss concepts to their SwiftUI equivalents, which tells us:

1. Which Lip Gloss patterns are already handled by the SwiftUI model we're implementing
2. Which Lip Gloss patterns point to gaps or confirmed TUI deviations in TerminalUI
3. Where TUI-specific aesthetics (borders, box drawing, tree chrome) map to SwiftUI primitives

See [VISION.md](VISION.md) for the confirmed list of TUI deviations informed by this analysis.

## Reference Mapping

This survey covers the upstream Lip Gloss source, especially `README.md`, `style.go`, `set.go`, `get.go`, `unset.go`, `borders.go`, `position.go`, `ranges.go`, `whitespace.go`, `color.go`, `wrap.go`, `canvas.go`, `layer.go`, and the `list`, `table`, and `tree` subpackages. SwiftUI API names were sanity-checked against Apple SwiftUI docs via Context7.

## How to read this

- Lip Gloss renders terminal strings a cell at a time.
- SwiftUI builds a retained view tree.
- "Equivalent" here means the closest native SwiftUI API or pattern, not a byte-for-byte or cell-for-cell match.
- Exact terminal behavior usually requires a monospaced font, a custom `Layout`, `AttributedString`, `Canvas`, and a style value type that you own.

## Core Styles

### Style Lifecycle and Composition

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `NewStyle()` | A value-type style struct plus a `ViewModifier` | SwiftUI has modifiers and environment values, not a standalone mutable style object with full inspection APIs. |
| `SetString(...)` | Store content in state/model, then feed `Text` or `AttributedString` | SwiftUI keeps content and styling more separate than Lip Gloss. |
| `Value()` | Read the source `String` / `AttributedString` from your model | You read owned model data, not a rendered view. |
| `Render(...)` | `body` returning `Text` or `some View` | SwiftUI renders views, not styled console strings. |
| `String()` | A computed `Text` / `some View` | There is no direct string-rendering equivalent. |
| `Copy()` | Plain value assignment of your style struct | Matches Swift value semantics well. |
| `Inherit(...)` | Merge two style structs before applying modifiers | There is no built-in "inherit only unset fields"; implement `merged(with:)` yourself. |

### Inline Text, Color, and Text Transforms

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `Bold(true)` | `.bold()` or `.fontWeight(.bold)` | Direct equivalent for `Text`. |
| `Italic(true)` | `.italic()` | Direct equivalent for `Text`. |
| `Faint(true)` | `.opacity(...)`, `.foregroundStyle(.secondary)`, or a dimmer theme color | No true terminal "faint" SGR equivalent. |
| `Blink(true)` | Custom repeating animation on opacity/visibility | No native blink modifier; usually avoid for accessibility. |
| `Reverse(true)` | Swap configured foreground and background in your style model | SwiftUI has no single "reverse video" modifier. |
| `Underline(true)` | `.underline(true)` | Direct for simple underline. |
| `UnderlineStyle(...)` | `.underline(_:pattern:color:)` on `Text` | SwiftUI supports line patterns, but not every terminal underline variant maps perfectly. |
| `UnderlineColor(...)` | `.underline(_:color:)` or `.underline(_:pattern:color:)` | Direct on `Text`. |
| `UnderlineSpaces(true)` | `AttributedString` runs or custom drawing | SwiftUI does not expose padding/margin whitespace as separately stylable glyph space the way terminal rendering does. |
| `Strikethrough(true)` | `.strikethrough(true)` | Direct on `Text`. |
| `StrikethroughSpaces(true)` | `AttributedString` runs or custom drawing | Same caveat as `UnderlineSpaces(true)`. |
| `Foreground(...)` | `.foregroundStyle(...)` | Direct equivalent. |
| `Background(...)` | `.background(...)` | Close equivalent; modifier order matters if you want block-style background fill. |
| `Hyperlink(...)` | `Link`, or `Text(AttributedString)` with a `.link` attribute | `Link` is the simplest direct equivalent; `AttributedString` is better for inline links in mixed text. |
| `Transform(fn)` | Preprocess the string before building `Text`, or wrap in a custom modifier | SwiftUI has no generic content-string transform modifier. |

### Layout, Alignment, and Sizing

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `Width(...)` | `.frame(width: ...)` | Direct for fixed width. |
| `Height(...)` | `.frame(height: ...)` | Direct for fixed height. |
| `MaxWidth(...)` | `.frame(maxWidth: ...)` | Direct conceptually. |
| `MaxHeight(...)` | `.frame(maxHeight: ...)` | Direct conceptually. |
| `Align(...)` | `.frame(..., alignment: ...)` | Use combined alignment when you need both axes. |
| `AlignHorizontal(...)` | `.frame(maxWidth: ..., alignment: ...)` or stack alignment | Closest horizontal equivalent. |
| `AlignVertical(...)` | `.frame(maxHeight: ..., alignment: ...)`, `VStack`, or custom `Layout` | Vertical placement often needs a container. |
| `Inline(true)` | `Text(...).lineLimit(1).fixedSize(horizontal: true, vertical: false)` and omit outer chrome | Lip Gloss inline mode also ignores margin, padding, and borders, so the closest SwiftUI equivalent is a simplified text-only rendering path. |
| `TabWidth(...)` | Preprocess `\t` before building `Text` | SwiftUI does not expose a tab-expansion policy modifier. |

### Padding, Margins, and Whitespace Rules

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `Padding(...)`, `PaddingTop(...)`, `PaddingRight(...)`, `PaddingBottom(...)`, `PaddingLeft(...)` | `.padding(...)` / `.padding(.edge, ...)` | Direct conceptually. |
| `PaddingChar(...)` | Pattern overlay/background with repeated glyphs in a monospaced `Text`, `Canvas`, or custom `Layout` | No direct equivalent because SwiftUI padding is empty layout space, not filled characters. |
| `Margin(...)`, `MarginTop(...)`, `MarginRight(...)`, `MarginBottom(...)`, `MarginLeft(...)` | Outer wrapper view with `.padding(...)`, `Spacer`, or container spacing | SwiftUI has no dedicated margin modifier; margin is usually modeled by the parent. |
| `MarginBackground(...)` | Outer wrapper `.background(...)` | Apply the background on the outer wrapper, not the inner content. |
| `MarginChar(...)` | Custom outer wrapper that draws patterned space | No direct equivalent for glyph-filled margin cells. |
| `ColorWhitespace(...)` | Control modifier order so `.background(...)` is applied outside `.padding(...)` when desired | Lip Gloss styles terminal whitespace explicitly; in SwiftUI the closest control point is view hierarchy and modifier order. |

### Borders

> Updated for the Milestone 7 shape-and-border revamp. TerminalUI now
> ships a first-class `BorderSet` / `.border(...)` surface modeled directly
> on Lip Gloss's data shape, so most of these rows have a direct
> TerminalUI equivalent rather than a workaround.

| Lip Gloss API | TerminalUI / SwiftUI equivalent | Notes |
| --- | --- | --- |
| `Border(border, sides...)` | `.border(_:set:sides:)` | Direct. `sides: Edge.Set` maps to Lip Gloss's per-side toggle set. |
| `BorderStyle(...)` | `BorderSet` (public struct in `Core`) | `BorderSet` is the Lip Gloss `Border` struct, ported verbatim — flat record of per-edge and per-corner strings, multi-rune edges cycle per cell. |
| `BorderTop(...)`, `BorderRight(...)`, `BorderBottom(...)`, `BorderLeft(...)` | `.border(_:set:sides:)` with `Edge.Set` mask (`[.top]`, `[.top, .bottom]`, …) | Direct; composes better than four separate bools. |
| `BorderForeground(...)` | `.border(_ style:set:sides:)` with a uniform `ShapeStyle` | Direct. |
| `BorderTopForeground(...)`, `BorderRightForeground(...)`, `BorderBottomForeground(...)`, `BorderLeftForeground(...)` | `.border(_ edges:set:sides:)` taking a `BorderEdgeStyle` | `BorderEdgeStyle` has CSS-shorthand initializers (1 / 2 / 3 / 4 values) matching Lip Gloss's `BorderForeground(colors...)` overload. |
| `BorderForegroundBlend(...)` | `.border(blend:set:sides:phase:)` with a `BorderBlend` | Direct. `BorderBlend` is a 1D gradient sampled continuously around the perimeter using CIELAB interpolation, the way Lip Gloss does it. |
| `BorderForegroundBlendOffset(...)` | `.border(blend:set:sides:phase:)` animatable `phase: Double` | Direct — `phase` rotates the perimeter sample origin and drives chasing-light animations through the normal animation pipeline. |
| `BorderBackground(...)` | `BorderBackgroundStyle` passed via `.stroke(_:style:background:)` or the layout-aware border background slot | Direct per-side backgrounds for border glyph cells. |
| `BorderTopBackground(...)`, `BorderRightBackground(...)`, `BorderBottomBackground(...)`, `BorderLeftBackground(...)` | `BorderBackgroundStyle(top:right:bottom:left:)` or the CSS-shorthand initializers | Direct. |

### Border Presets, Positions, and Other Core Helpers

| Lip Gloss API | TerminalUI / SwiftUI equivalent | Notes |
| --- | --- | --- |
| `NormalBorder()`, `RoundedBorder()`, `BlockBorder()`, `OuterHalfBlockBorder()`, `InnerHalfBlockBorder()`, `ThickBorder()`, `DoubleBorder()`, `HiddenBorder()`, `MarkdownBorder()`, `ASCIIBorder()` | `BorderSet.single`, `.rounded`, `.block`, `.outerHalfBlock`, `.innerHalfBlock`, `.heavy`, `.double`, `.hidden`, `.markdown`, `.ascii` | Direct. TerminalUI also ships `.singleDouble`, `.doubleSingle`, `.dashed`, `.dashedHeavy`, `.none`, and `.presentationChrome` (internal chrome). Custom sets are just `BorderSet(top:…)` initializers. |
| `Top`, `Bottom`, `Left`, `Right`, `Center` | `Alignment` cases like `.top`, `.bottomTrailing`, `.leading`, `.center` | Conceptually direct. |
| `Place(...)`, `PlaceHorizontal(...)`, `PlaceVertical(...)` | `.frame(..., alignment: ...)`, `ZStack(alignment: ...)`, `.overlay(alignment: ...)` | `Place` is best thought of as alignment within a bounded box. |
| `JoinHorizontal(...)`, `JoinVertical(...)` | `HStack`, `VStack`, `Grid`, or a custom `Layout` | Use a custom `Layout` when you need Lip Gloss-style relative anchor alignment across differently sized blocks. |
| `Width(str)`, `Height(str)`, `Size(str)` | `GeometryReader`, `PreferenceKey`, or custom `Layout` measurement | SwiftUI measures views during layout, not by post-processing a rendered string. |
| `Wrap(...)` | `Text` wrapping by default, plus `.lineLimit(...)`, `.truncationMode(...)`, `.fixedSize(...)` | SwiftUI wraps styled text natively; Lip Gloss's ANSI-preserving wrap is string-renderer-specific. |
| `WithWhitespaceStyle(...)`, `WithWhitespaceChars(...)` | Patterned backgrounds, overlays, or `Canvas` | No direct "whitespace style" API because SwiftUI does not render padding as character cells. |
| `NewRange(...)`, `StyleRanges(...)`, `StyleRunes(...)` | `AttributedString` ranges and `Text(AttributedString)` | This is the closest native SwiftUI match for per-range styling. |
| `Color(...)`, ANSI color constants, `NoColor{}` | `Color`, asset-catalog colors, semantic colors, and optional style values | `NoColor` maps best to "omit the modifier" or reset to default system styling. |
| `LightDark(...)`, `HasDarkBackground(...)`, `BackgroundColor(...)` | `@Environment(\\.colorScheme)` and platform-specific color inspection when needed | SwiftUI exposes color scheme, not a terminal background probe. |
| `Complete(...)` | Asset-catalog variants or your own palette-selection logic | SwiftUI does not downsample based on terminal color profiles. |
| `Alpha(...)`, `Complementary(...)`, `Darken(...)`, `Lighten(...)` | Color helpers in your own theme layer, or UIKit/AppKit color math bridged into SwiftUI | These are utility-layer equivalents, not built-in SwiftUI modifiers. |
| `Blend1D(...)`, `Blend2D(...)` | `LinearGradient`, `RadialGradient`, `PatternFill`, or `Canvas` | TerminalUI now ships `LinearGradient` / `RadialGradient` with Textual-style `(location, color)` stops and CIELAB blending, plus `PatternFill` for `░ ▒ ▓` shading. `BorderBlend` handles perimeter gradients specifically. |

### Introspection and Reset APIs

Lip Gloss exposes getters and unsets because `Style` is a pure value object. SwiftUI views are opaque after composition: there is no supported way to ask a built `View` which modifiers it already has, and no supported way to partially "unset" modifiers in place. The practical SwiftUI equivalent is:

1. Keep your own `LipGlossStyle`-like value type.
2. Merge or clear fields on that value type.
3. Rebuild the view from the updated style data.

#### Getter Families

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `GetBold`, `GetItalic`, `GetUnderline`, `GetUnderlineStyle`, `GetUnderlineColor`, `GetStrikethrough`, `GetReverse`, `GetBlink`, `GetFaint`, `GetForeground`, `GetBackground` | Read the corresponding fields from your own style struct | No native `View` modifier introspection API. |
| `GetWidth`, `GetHeight`, `GetAlign`, `GetAlignHorizontal`, `GetAlignVertical`, `GetInline`, `GetMaxWidth`, `GetMaxHeight`, `GetTabWidth` | Read sizing/alignment fields from your own style struct | SwiftUI view values do not expose resolved modifier state. |
| `GetPadding`, `GetPaddingTop`, `GetPaddingRight`, `GetPaddingBottom`, `GetPaddingLeft`, `GetPaddingChar`, `GetHorizontalPadding`, `GetVerticalPadding`, `GetColorWhitespace` | Read spacing fields from your own style struct | Padding characters and whitespace coloring must also live in your own model. |
| `GetMargin`, `GetMarginTop`, `GetMarginRight`, `GetMarginBottom`, `GetMarginLeft`, `GetMarginChar`, `GetHorizontalMargins`, `GetVerticalMargins` | Read outer-spacing fields from your own style struct or container model | In SwiftUI, margin is usually parent-owned. |
| `GetBorder`, `GetBorderStyle`, `GetBorderTop`, `GetBorderRight`, `GetBorderBottom`, `GetBorderLeft`, `GetBorderTopForeground`, `GetBorderRightForeground`, `GetBorderBottomForeground`, `GetBorderLeftForeground`, `GetBorderForegroundBlend`, `GetBorderForegroundBlendOffset`, `GetBorderTopBackground`, `GetBorderRightBackground`, `GetBorderBottomBackground`, `GetBorderLeftBackground`, `GetBorderTopWidth`, `GetBorderTopSize`, `GetBorderLeftSize`, `GetBorderBottomSize`, `GetBorderRightSize`, `GetHorizontalBorderSize`, `GetVerticalBorderSize` | Read border configuration from your own `BorderSet` + `BorderEdgeStyle` + `BorderBackgroundStyle` + `BorderBlend` model | TerminalUI surfaces `BorderSet.topDisplayWidth` (and friends) for per-side frame sizes. SwiftUI itself does not expose a border inspection API. |
| `GetUnderlineSpaces`, `GetStrikethroughSpaces`, `GetHorizontalFrameSize`, `GetVerticalFrameSize`, `GetFrameSize`, `GetTransform`, `GetHyperlink` | Read behavior/derived values from your own style struct | Derived frame sizes are usually computed from your model plus layout policy. |

#### Reset Families

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `UnsetBold`, `UnsetItalic`, `UnsetUnderline`, `UnsetStrikethrough`, `UnsetReverse`, `UnsetBlink`, `UnsetFaint`, `UnsetForeground`, `UnsetBackground`, `UnsetHyperlink`, `UnsetTransform` | Clear those fields to `nil` / default in your own style struct, then rebuild the view | SwiftUI clearing is state-driven, not mutation of an existing view. |
| `UnsetWidth`, `UnsetHeight`, `UnsetAlign`, `UnsetAlignHorizontal`, `UnsetAlignVertical`, `UnsetInline`, `UnsetMaxWidth`, `UnsetMaxHeight`, `UnsetTabWidth`, `UnsetString` | Remove the corresponding layout/content fields from your own style or view-model state | Recomposition is the SwiftUI path. |
| `UnsetPadding`, `UnsetPaddingLeft`, `UnsetPaddingRight`, `UnsetPaddingTop`, `UnsetPaddingBottom`, `UnsetPaddingChar`, `UnsetColorWhitespace` | Clear spacing fields from your own style struct | Same pattern as above. |
| `UnsetMargins`, `UnsetMarginLeft`, `UnsetMarginRight`, `UnsetMarginTop`, `UnsetMarginBottom`, `UnsetMarginBackground` | Clear outer-spacing fields from the wrapper/container model | Margin is usually modeled one level up in SwiftUI. |
| `UnsetBorderStyle`, `UnsetBorderTop`, `UnsetBorderRight`, `UnsetBorderBottom`, `UnsetBorderLeft`, `UnsetBorderForeground`, `UnsetBorderTopForeground`, `UnsetBorderRightForeground`, `UnsetBorderBottomForeground`, `UnsetBorderLeftForeground`, `UnsetBorderForegroundBlend`, `UnsetBorderForegroundBlendOffset`, `UnsetBorderBackground`, `UnsetBorderTopBackground`, `UnsetBorderRightBackground`, `UnsetBorderBottomBackground`, `UnsetBorderLeftBackground`, `UnsetBorderTopBackgroundColor` | Clear border fields in your shape/border style model | `UnsetBorderTopBackgroundColor` appears in the mirror and maps to the same clearing behavior as `UnsetBorderTopBackground`. |
| `UnsetUnderlineSpaces`, `UnsetStrikethroughSpaces` | Clear those behavior flags in your own style model | No built-in modifier reset exists. |

## Recommended SwiftUI Translation Pattern

If the goal is Lip Gloss parity rather than loose visual similarity, the closest SwiftUI architecture is:

- A value-type `TerminalStyle` or `LipGlossStyle` that stores optional fields.
- A `merged(with:)` method that implements Lip Gloss-like inheritance.
- A `ViewModifier` or `Text` builder that applies only the fields that are set.
- A custom border abstraction for per-edge colors and gradient borders — **in TerminalUI this is `BorderSet` + `BorderEdgeStyle` + `BorderBlend`, ported directly from Lip Gloss.**
- A custom `Layout` when width, height, alignment, padding fill, and terminal-cell semantics must stay exact.
- `AttributedString` for range-level styling.
- `Canvas` for compositor-style or border-glyph-style drawing.

## Common Components

### Lists (`reference/lipgloss/list`)

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `list.New(...)` | `List`, `ForEach`, or a recursive `VStack` | If nesting matters, `OutlineGroup` or a recursive view is usually closer than a plain `List`. |
| `Item(...)`, `Items(...)` | Mutate the backing collection that drives `ForEach` | SwiftUI is data-first: update the model, not the rendered list view. |
| `Hide(...)`, `Hidden()` | `if !hidden { ... }` or `.hidden()` | Use `if` to remove from layout; `.hidden()` to preserve layout space. |
| `Offset(start, end)` | Slice the source collection before rendering | `dropFirst`, `prefix`, or a computed view-model slice. |
| `Enumerator(...)` | Custom leading marker view inside an `HStack` | No native list-marker API is as flexible as Lip Gloss enumerators. |
| `EnumeratorStyle(...)`, `EnumeratorStyleFunc(...)` | Style the marker `Text` or marker view directly | Use a row builder or style closure. |
| `Indenter(...)`, `IndenterStyle(...)`, `IndenterStyleFunc(...)` | Leading padding, recursive depth offsets, or a custom `Layout` | Needed when you want custom indentation guides rather than platform list chrome. |
| `ItemStyle(...)`, `ItemStyleFunc(...)` | Conditional row modifiers in `ForEach` | Map row index/data to a modifier pipeline. |
| `Value()`, `String()` | Model value / row view composition | SwiftUI does not render a list to a terminal string. |
| `Alphabet`, `Arabic`, `Roman`, `Bullet`, `Asterisk`, `Dash` | Format marker strings yourself | These become small marker-formatting helpers in SwiftUI. |

### Trees (`reference/lipgloss/tree`)

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `tree.New()`, `tree.Root(...)`, `Root(...)` | `OutlineGroup`, `List(..., children:)`, or a recursive tree view | `OutlineGroup` is the closest built-in hierarchical equivalent. |
| `Child(...)` | Append children in the backing tree model | Data-first, not renderer-first. |
| `Hide(...)`, `Hidden()`, `SetHidden(...)` | Conditional rendering or filtered tree data | Same general pattern as lists. |
| `Offset(start, end)` | Slice visible children before feeding them to `ForEach` / `OutlineGroup` | Usually done in the tree view model. |
| `Width(...)` | `.frame(width: ...)`, `.frame(maxWidth: ...)`, or a custom `Layout` | Use custom layout if node label width must pad to a shared tree width. |
| `Enumerator(...)` | Custom branch-prefix view or custom `Layout` | SwiftUI does not have a built-in tree-branch glyph API. |
| `Indenter(...)` | Recursive leading inset or custom `Layout` | Required for connector-line style trees. |
| `EnumeratorStyle(...)`, `EnumeratorStyleFunc(...)` | Style the branch prefix view | Usually a small helper view per node. |
| `IndenterStyle(...)`, `IndenterStyleFunc(...)` | Style custom connector/indent visuals | Often easier with `Canvas` or overlay lines. |
| `RootStyle(...)` | Apply a distinct modifier set to the root-node view | Direct conceptually. |
| `ItemStyle(...)`, `ItemStyleFunc(...)` | Apply node-level conditional modifiers | Direct conceptually. |
| `Children()` | Read child nodes from your model | Direct data-model equivalent. |
| `Value()`, `SetValue(...)`, `String()` | Node model property / rendered node view | Again, SwiftUI is view-tree based, not string-render based. |
| `DefaultEnumerator`, `RoundedEnumerator`, `DefaultIndenter` | Small helper views or custom drawing functions | Good candidates for reusable SwiftUI components. |

### Tables (`reference/lipgloss/table`)

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `table.New()` | `Grid`, platform `Table` where supported, or `ScrollView` + `LazyVStack` | `Grid` is the closest cross-platform primitive; `Table` is the richer native table when available. |
| `Headers(...)` | Header `GridRow`, `Section` header, or a separate header view | Direct conceptually. |
| `Row(...)`, `Rows(...)` | Backing collection of row models rendered with `ForEach` | Data-first. |
| `Data(...)`, `GetData()` | Custom row/column data source object | Direct conceptually. |
| `BaseStyle(...)` | Apply modifiers to the outer table container | Matches an outer wrapper view well. |
| `StyleFunc(row, col)` | Cell view builder or style closure keyed by row/column | This maps very naturally to SwiftUI view composition. |
| `Border(...)`, `BorderTop(...)`, `BorderBottom(...)`, `BorderLeft(...)`, `BorderRight(...)`, `BorderHeader(...)`, `BorderColumn(...)`, `BorderRow(...)` | `Divider`s, cell overlays, grid lines, or a custom table border renderer | No single built-in cross-platform grid-line API covers every table-border toggle. |
| `BorderStyle(...)` | Shared stroke/line style for table chrome | Usually a theme value consumed by overlays or `Canvas`. |
| `Width(...)`, `Height(...)` | `.frame(width: ..., height: ...)` on the table container | Direct conceptually. |
| `Wrap(...)` | Wrapped `Text` by default, or `.lineLimit(1).truncationMode(.tail)` when disabled | SwiftUI defaults to wrapping; Lip Gloss tables can explicitly disable it. |
| `YOffset(...)`, `GetYOffset()` | `ScrollViewReader`, scroll-position state, or visible-row slicing in the view model | This is a scroll/virtualization concern in SwiftUI. |
| `FirstVisibleRowIndex()`, `LastVisibleRowIndex()`, `VisibleRows()` | Derived state from your scroll/virtualization model | No built-in table exposes these exact metrics directly. |
| `Render()`, `String()` | The table view itself | No string-rendering equivalent in SwiftUI. |

### Canvas, Layers, and Composition (`canvas.go`, `layer.go`)

| Lip Gloss API | Closest SwiftUI equivalent | Notes |
| --- | --- | --- |
| `NewCanvas(width, height)` | `Canvas` or a custom drawing view with a fixed frame | Direct conceptually, but SwiftUI canvas is vector/graphics-context based rather than cell-buffer based. |
| `Canvas.Resize(...)` | Change the view's frame or drawing size from state | Size is state-driven in SwiftUI. |
| `Canvas.Clear()` | Clear the drawing state / redraw with an empty scene | Usually just render no content. |
| `Canvas.Compose(...)` | `ZStack`, `Canvas`, or a custom compositor model | `ZStack` is the simplest retained-mode equivalent; `Canvas` is closer for manual drawing. |
| `Canvas.SetCell(...)`, `Canvas.CellAt(...)` | Custom pixel/cell model consumed by `Canvas` | No built-in cell buffer exists in SwiftUI. |
| `Canvas.Render()` | The `Canvas` view's body | Again, no string output equivalent. |
| `NewLayer(content, ...)` | A child view in `ZStack` or an entry in a retained render graph | Closest mental model is a retained scene node. |
| `ID(...)`, `GetID()` | `.id(...)` or an `Identifiable` model property | Direct conceptually. |
| `X(...)`, `Y(...)`, `GetX()`, `GetY()` | `.offset(x:y:)`, `.position(x:y:)`, or layout coordinates | Direct conceptually. |
| `Z(...)`, `GetZ()`, `MaxZ()` | `.zIndex(...)` | Direct conceptually. |
| `AddLayers(...)`, `GetLayer(...)` | Nested child views / retained scene graph | Best modeled in your own composition tree. |
| `NewCompositor(...)`, `AddLayers(...)`, `Refresh()` | Scene graph object feeding `ZStack` or `Canvas` | SwiftUI itself is retained-mode, but explicit refresh is just state change. |
| `Bounds()` | Geometry from `GeometryReader` or a retained scene model | Direct conceptually. |
| `Draw(...)`, `Render()` | `Canvas { context, size in ... }` or `body` | `Canvas` is the closest imperative drawing surface. |
| `Hit(x, y)` | Gestures plus geometry-based hit testing, optionally with `contentShape(...)` | SwiftUI hit testing is view-based; custom scene-graph hit testing lives in your own model. |

## Commands, Help, and Toolbar Chrome

> Updated for the Milestone 8 Commands & Chrome landing. TerminalUI
> ships a unified `Command` data model that feeds three lenses
> (toolbar, help, command palette) so authors register a command once
> with an optional key and group, and every surface picks it up
> automatically. See
> [`docs/proposals/COMMAND_AND_CHROME_APIS.md`](proposals/COMMAND_AND_CHROME_APIS.md)
> for the design intent.

### Charm `bubbles` (Bubble Tea)

| Charm API | TerminalUI / SwiftUI equivalent | Notes |
| --- | --- | --- |
| `bubbles/key.Binding`, `key.NewBinding`, `key.WithKeys`, `key.WithHelp` | `.command(id:title:key:group:, action:)` (`View`) | Direct. The `.command(...)` modifier carries the action, the `KeyPress`, the `group` label, and the human-readable title — Charm splits these across `key.Binding` and a separate handler; TerminalUI keeps them on a single registration. |
| `bubbles/help.Model` + `help.KeyMap` + `ShortHelp()` / `FullHelp()` | `.help()` + `.helpSheet()` (`View`) | TerminalUI does not require the author to implement a `KeyMap` interface or split the model into a "short" and "full" view. The strip and sheet are both auto-derived from the same command preference value, so adding a new `.command(..., key:)` automatically updates both surfaces. This matches Textual more than Charm. |
| `bubbles/help.View()` rendered by the parent model | `.help()` modifier on the host view | TerminalUI composes the strip into a bottom row of an implicit toolbar host at any `WindowGroup` root, so authors do not need to thread a `help.Model` through their own `View()` function. |
| `lipgloss` glyph rendering of bracketed shortcuts in custom footers | `KeyGlyphView(keyPress)` (`View`) | The same display string used by the help strip, help sheet, and command-palette rows is exposed as a public renderer for ad-hoc placement (e.g. inside a status bar custom view). |

### Textual (Python)

| Textual API | TerminalUI / SwiftUI equivalent | Notes |
| --- | --- | --- |
| `App.BINDINGS = [Binding("ctrl+s", "save", "Save")]` | `Scene.commands { CommandItem(id: "save", title: "Save", key: .ctrl("s"), group: "File") { save() } }` (`TerminalUI`) | Direct. Scene-level commands are the primary registration site for always-on app actions (Quit, Save, Toggle Theme, Command Palette). |
| `Screen.BINDINGS = [Binding("escape", "back", "Back")]` | `.command(id: "back", title: "Back", key: .escape, group: "Navigation") { ... }` (`View`) | Direct. View-level `.command(...)` is the scoped escape hatch — the binding only dispatches while that subtree is in the tree. The innermost-wins dedup the help strip applies matches Textual's `Screen.BINDINGS` overrides. |
| `Footer` widget that auto-derives its rows from `screen.active_bindings` | `.help()` (`View`) | Direct. The Textual footer reads the union of `App.BINDINGS` and the focused screen's `BINDINGS`; TerminalUI's `.help()` does the same by reducing the `CommandPreferenceKey` plus the scene-commands environment channel. Auto-derived, no manual list to keep in sync. |
| `Footer` `show_command_palette` row (`ctrl+p`) | `.commandPalette(isPresented:)` (`View`) | TerminalUI's command palette already shipped before Milestone 8; under the unified model it auto-populates from the same `Command` records the help system reads. |
| Textual command palette (`ctrl+p`, fuzzy-searchable) | `.commandPalette(isPresented:)` (`View`) | Direct. The palette consumes the unified `Command` value — including its title, detail, keywords, kind, and key glyph — so a single `.command(...)` registration shows up in the help strip, the help sheet, and the palette without the author wiring three surfaces. |
| `Binding(key, action, description, show=False)` (palette-only / strip-hidden bindings) | `.command(...)` without a `key:` plus the existing `kind` / `isDisabled` parameters | TerminalUI's strip auto-omits commands without a `KeyPress` binding (no glyph to render), so a keyless registration is palette-and-sheet-only. A dedicated `helpHidden:` flag is a Stage-5.1 follow-up. |
| Textual cheatsheet popover triggered by `f1` | `.helpSheet(triggeredBy:)` (`View`) | Direct. The sheet groups commands by `Command.group`, mirroring the Textual cheatsheet layout with one section per non-nil group plus a trailing "Other" section for ungrouped entries. |

### SwiftUI

| SwiftUI API | TerminalUI equivalent | Notes |
| --- | --- | --- |
| `.toolbar { ToolbarItem(placement: .primaryAction) { Button("Save") { ... } } }` | `.toolbar { ToolbarItem(.primaryAction) { Text("Save") } }` (`View`) | Direct, with the same result-builder shape and the same `ToolbarItem` / `ToolbarItemGroup` / `ToolbarSpacer` types. The placement set is pruned to the cases that have a meaningful TUI interpretation; placements referring to chrome the framework does not render are dropped (proposal §4.7). |
| `.toolbar { ToolbarItem { ... } }` carrying its own `.keyboardShortcut(...)` | `.command(id:title:key:group:, action:)` registers the binding; `ToolbarItem(.primaryAction, command: "save")` references it by id | **Deliberate divergence.** TerminalUI does not let `ToolbarItem` carry a `key:` parameter. Keys are the command system's job; the toolbar is a placement system. A command-bound `ToolbarItem` pulls *only presentation data* (title, glyph, disabled state) from the registered command record. See proposal §4.3. |
| `.keyboardShortcut(_:modifiers:)` on a `Button` | `.command(id:title:key:group:, action:)` plus `KeyGlyphView` | **Deliberate divergence.** SwiftUI attaches shortcuts to individual button views; TerminalUI surfaces shortcuts as registrations on the unified command model. Authors get the help strip, help sheet, and palette discoverability for free; SwiftUI authors need additional menu/help-bar wiring to expose the same shortcuts to users. |
| `Toolbar` visibility via `.toolbar(_:for:)` | `.toolbar(_:for:)` (`View`, capture-only in v1) | API-shape match. The modifier writes the authored intent into a package-internal preference channel; the rendering consumer is a Stage-5 follow-up. |
| `.toolbarBackground(_:for:)` | `.toolbarBackground(_:for:)` (`View`, capture-only in v1) | API-shape match. Same capture-only caveat. |
| Scene-level `.commands { CommandMenu(...) }` (macOS) | `Scene.commands { CommandItem(...) }` (`TerminalUI`) | The shape echoes SwiftUI's `Scene.commands(_:)` slot but uses a flat `CommandItem` builder rather than a nested `Commands` / `CommandMenu` / `CommandGroup` hierarchy, since TerminalUI does not render a menu bar. |

### helix / vim "which-key"

| Pattern | TerminalUI equivalent | Notes |
| --- | --- | --- |
| `which-key` style popover that discloses the available next-key options after a prefix is pressed | Partially addressed via `.helpSheet(triggeredBy:)`; full prefix-tree disclosure deferred | The help sheet groups commands by `Command.group`, so authors can model "leader-key submenus" by giving related commands the same group label. A first-class prefix-tree disclosure surface (with a continuously-updated popover after the leader key) is a v1.1 follow-up. |

## Source Coverage

This document was derived from the upstream [Lip Gloss](https://github.com/charmbracelet/lipgloss) source files:

- `README.md`, `style.go`, `set.go`, `get.go`, `unset.go`, `borders.go`
- `position.go`, `ranges.go`, `whitespace.go`, `color.go`, `wrap.go`
- `canvas.go`, `layer.go`
- `list/list.go`, `list/enumerator.go`
- `table/table.go`
- `tree/tree.go`, `tree/enumerator.go`
