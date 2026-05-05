# Borders and Strokes

This framework has *two* systems for drawing rectangular borders:

1. **`BorderSet`** — a 13-slot glyph palette (top/bottom/sides + four
   corners + optional middle joins). Defined in
   `Sources/Core/BorderSet.swift`. Pure data; no behavior.
2. **`StrokeStyle`** — `lineWidth` + `BorderSet` + `Placement`. Defined
   in `Sources/Core/Styling.swift`. Configures *how* a `BorderSet` is
   drawn against a shape.

These two are deliberately the only sources of truth. Earlier
revisions had two additional implicit "systems" — distinct defaults
on the `View.border(...)` modifier vs. `Shape.stroke(...)`, and
hand-rolled glyph painting in tables, tabs, scrollbars, sliders,
progress, and charts. As of 2026-04 the modifier and stroke defaults
are aligned, and the hand-rolled widget glyphs are documented as
intentional widget-specific palettes (out of the
`BorderSet`/`StrokeStyle` story by design).

## The canonical default

`StrokeStyle()` and `View.border(...)` both default to:

- `borderSet: .rounded` — top/bottom `─`, sides `│`, corners
  `╭╮╰╯`. This is the framework-canonical container chrome.
- `placement: .outset` — the border lives in a cell on each side of the
  content; the layout engine reserves space for it.
- `lineWidth: 1` — currently the only supported value.

If you write `Rectangle().stroke(.red)` or `Rectangle().border(.red)`,
this is what you get.

## Opting into other chrome

For the legacy `─│┌┐└┘` look, pass `borderSet: .single` explicitly:

```swift
Rectangle()
  .stroke(.foreground, style: StrokeStyle(borderSet: .single))
```

For the previous half-block chrome, pass `borderSet: .outerHalfBlock`
explicitly:

```swift
Rectangle()
  .stroke(.foreground, style: StrokeStyle(borderSet: .outerHalfBlock))
```

There is **no** implicit transformation — the rasterizer draws exactly
the `BorderSet` you ask for. The historical "single → rounded
auto-upgrade" against radiused shapes was removed in 2026-04 along
with the canonical-default flip.

## Available palettes

See `BorderSet`'s static let declarations:

- `single` / `rounded` / `heavy` / `double` — line-drawing variants
- `outerHalfBlock` / `innerHalfBlock` — half-block variants
- `block` — solid `█` perimeter
- `singleDouble` / `doubleSingle` — mixed line/double
- `ascii` / `markdown` — fallback palettes for restricted terminals
- `dashed` / `dashedHeavy` — dashed variants
- `hidden` (reserves space, draws spaces) / `none` (zero contribution)

## Out of scope (intentional widget palettes)

The following draw their own glyphs and do not participate in
`BorderSet`/`StrokeStyle`:

- **Tables** (`Sources/Core/CollectionStylePresentations.swift`,
  `TableBorderGlyphs`) — fork of BorderSet shape with extra junction
  fields. Migration is feasible but defers junction synthesis for
  half-block palettes.
- **Tabs** (`Sources/View/NavigationViews/TabViewStyles.swift`) —
  three distinct hand-rolled chromes (underline, literal, labeled).
  The `LiteralTabsStripBackgroundView` Divider is explicitly pinned
  to `StrokeStyle(borderSet: .single)` for visual coherence with the
  surrounding hand-rolled `╭─╮│┘└` glyphs.
- **Scrollbars** (`Sources/Core/DrawExtractor+Lists.swift`) — `┃`/`━`/`█`.
- **Sliders, progress bars, charts, metric tracks** — thin-line
  interior glyph painting, not container chrome.

These are documented for inventory; their visual identity is
intentionally distinct from the canonical container border.

## See also

- The migration plan: `docs/plans/2026-04-26-003-border-stroke-simplification-plan.md`
- The post-migration commits: `git log --grep="border/stroke"`
