# Gallery Rewrite — Interactive Framework Basics Demo

**Date:** 2026-04-09
**Status:** Approved
**Scope:** `Examples/gallery`

## Goal

Replace the current `Examples/gallery` content (a figlet-font picker and color
swatch reference, ~200 lines in a single file) with an attractive interactive
demo of the basics of the `TerminalUI` framework.

The rewritten app should make it obvious, in under a minute of poking around,
how you author state-driven terminal UIs with TerminalUI. It should also double
as a smoke test for the core public surface by exercising it on every build.

## Non-Goals

- No new package targets, no changes to `Package.swift` dependencies beyond
  optionally dropping `swift-algorithms` if it becomes unused.
- No charts (`TerminalUICharts` is a separate module and a separate concern).
- No alerts, confirmation dialogs, toasts, or command palette (the three
  canonical demos cover enough of the surface on their own).
- No new framework features; this is an exercise of what already ships.
- No screenshots or golden-file tests for the gallery itself.

## User Experience

On launch, the user sees a `TabView` with three tabs:

1. **Counter** (default tab) — a hero with branding on top, a live counter
   underneath. Cheapest possible reactive demo, positioned first so the
   branding has room.
2. **Todo** — a task list with segmented filter, a modal sheet for intake,
   and a "clear completed" action.
3. **Calculator** — a basic four-function calculator with a button grid.

Each tab fits a single screen of content without scrolling at typical terminal
sizes (80x24 and up).

## Architecture

```
GalleryDemoViews/
├── GalleryView.swift        — root TabView
├── CounterTab.swift         — Counter tab view + branding header
├── TodoTab.swift            — Todo tab view, list, filter, sheet
├── TodoModels.swift         — TodoItem, Filter, Priority (value types)
└── CalculatorTab.swift      — Calculator tab view + Op state machine
```

Rationale for one-file-per-tab: each tab is self-contained with its own state
and layout, and keeping them as separate files keeps individual files in the
200-400 line sweet spot. Shared types for the todo tab live in `TodoModels.swift`
so the view file stays focused on layout.

`GalleryDemo/GalleryDemoApp.swift` is unchanged — it still hosts
`GalleryView()` inside a `WindowGroup`.

## Tab 1 — Counter

### Layout

```
┌──────────────────────────────────────────┐
│  ████╗ ████╗█████╗█╗  █╗█╗███╗ ████╗█╗   │  TextFigure "TerminalUI"
│  █╔══█╗█╔══█╗... etc                     │  (small figlet font)
│                                          │
│       A SwiftUI-shaped terminal UI       │  tagline, muted foreground
│  ─────────────────────────────────────   │  Divider
│                                          │
│                                          │
│                   42                     │  large count (Text or TextFigure)
│                                          │
│                                          │
│        [ − ]   [ Reset ]   [ + ]         │  Buttons, tint accents
│                                          │
│          Step: ◀══════●══════▶  5        │  Slider 1...10
│                                          │
└──────────────────────────────────────────┘
```

### State

```swift
@State private var count: Int = 0
@State private var step: Int = 1
```

### Framework features demonstrated

- `@State`
- `VStack`, `HStack`, `Spacer`, `.padding`, `.frame` alignment
- `Text` and `TextFigure` (TextFigure for branding; count is Text styled large, or TextFigure if numerals render cleanly in the chosen font)
- `Divider`
- `Button` (three buttons with semantic tints: minus=danger, reset=muted, plus=tint)
- `Slider` with `Int` binding for step size
- `withAnimation` on count change (count transitions with an ease curve)
- Semantic colors via `.foregroundStyle`

## Tab 2 — Todo

### Layout (base)

```
┌──────────────────────────────────────────┐
│  [ All ][ Active ][ Done ]   3 remaining │  segmented Picker + count
│  ──────────────────────────────────────  │
│  ☐  Write docs                      [×]  │
│  ☑  Ship release                    [×]  │  done rows strikethrough + muted
│  ☐  Water plants                    [×]  │
│  ☐  Call mum                        [×]  │
│                                          │
│  [ + New task ]              [ Clear ✓ ] │
└──────────────────────────────────────────┘
```

### Layout (sheet presented after `+ New task`)

```
    ┌──────────────────────────────┐
    │  New task                    │
    │  ──────────────────────────  │
    │  Title                       │
    │  [__________________________]│  TextField, @FocusState auto-focused
    │                              │
    │  Priority                    │
    │  ( ) Low ( ) Normal ( ) High │  Picker (non-segmented)
    │                              │
    │       [ Cancel ]   [ Add ]   │  Add is disabled when title is empty
    └──────────────────────────────┘
```

### State

```swift
// Main view
@State private var items: [TodoItem] = TodoItem.seeds
@State private var filter: TodoFilter = .all
@State private var isPresentingNew: Bool = false

// Sheet view
@State private var draftTitle: String = ""
@State private var draftPriority: TodoPriority = .normal
@FocusState private var titleFocused: Bool
```

### Models (in `TodoModels.swift`)

```swift
struct TodoItem: Identifiable, Hashable {
  let id: UUID
  var title: String
  var priority: TodoPriority
  var done: Bool

  static let seeds: [TodoItem] = [ /* 4 pre-populated items */ ]
}

enum TodoFilter: String, CaseIterable, Identifiable {
  case all, active, done
  var id: String { rawValue }
}

enum TodoPriority: String, CaseIterable, Identifiable {
  case low, normal, high
  var id: String { rawValue }
}
```

### Framework features demonstrated

- `@State` holding a collection, with additive/removal mutation
- `ForEach` over an `Identifiable` collection (filtered derived view)
- Segmented `Picker` for filter, regular `Picker` for priority
- `Toggle` styled as a checkbox for the done column
- `Button` (delete, add, clear)
- `.sheet(isPresented:)` for task intake
- `TextField` + `@FocusState` with auto-focus on sheet appear
- Commit-on-Enter via whatever TextField onSubmit hook the framework exposes, so pressing Enter in the title field equals pressing "Add"
- Conditional view modifiers (strikethrough + muted foreground when `done`)
- Derived `remaining` count shown in header

### Interaction details

- **+ New task** sets `isPresentingNew = true`. Sheet opens with empty draft,
  title field auto-focused via `@FocusState`.
- **Add button** is disabled while `draftTitle.trimmingCharacters(in: .whitespaces).isEmpty`.
- **Add / commit on Enter** appends a new `TodoItem` to `items`, resets draft,
  dismisses sheet.
- **Cancel** dismisses sheet without mutation.
- **Clear ✓** removes all items where `done == true`.
- **Row checkbox** toggles `done`.
- **Row ×** deletes a single item.
- **Filter** recomputes the rendered list without mutating `items`.

## Tab 3 — Calculator

### Layout

```
┌──────────────────────────────────────────┐
│                                          │
│                         1,234.56         │  right-aligned display
│                                          │
│   ┌────┬────┬────┬────┐                  │
│   │ AC │ +/-│  % │ ÷  │                  │
│   ├────┼────┼────┼────┤                  │
│   │ 7  │ 8  │ 9  │ ×  │                  │
│   ├────┼────┼────┼────┤                  │
│   │ 4  │ 5  │ 6  │ −  │                  │
│   ├────┼────┼────┼────┤                  │
│   │ 1  │ 2  │ 3  │ +  │                  │
│   ├────┴────┼────┼────┤                  │
│   │   0     │ .  │ =  │                  │
│   └─────────┴────┴────┘                  │
└──────────────────────────────────────────┘
```

### State

```swift
@State private var display: String = "0"
@State private var accumulator: Double? = nil
@State private var pendingOp: CalculatorOp? = nil
@State private var clearOnNextDigit: Bool = false
```

### Model

```swift
enum CalculatorOp {
  case add, sub, mul, div

  func apply(_ lhs: Double, _ rhs: Double) -> Double { ... }
}
```

### Framework features demonstrated

- Nested `HStack`/`VStack` to build a grid (the "0" key spans two columns)
- `.frame(width:height:)` for uniform button sizing
- `Button` with per-kind styling: operator buttons use an accent background,
  digits use the neutral tile background, AC/+/-/% use muted styling
- Right-aligned `Text` with a large font-style frame
- Local state machine for arithmetic evaluation

### Semantics

- Digits append to `display` (or replace it if `clearOnNextDigit` is set).
- Operators latch `accumulator = Double(display)` and set `pendingOp`.
- `=` resolves the pending op and shows the result.
- `AC` resets all state.
- `+/-` negates the current display.
- `%` divides display by 100.
- Division by zero shows `"Error"` and resets on next digit.

## Dependencies

- Drop `swift-algorithms` from the `GalleryDemoViews` target if no tab ends up
  needing it (the current gallery used it for `chunks(ofCount:)` in the color
  grid). Keep it if the calculator grid helper ends up using it, to avoid
  churn.
- No other package changes.

## File Churn Summary

| File | Change |
|---|---|
| `Sources/GalleryDemoViews/GalleryViews.swift` | Delete |
| `Sources/GalleryDemoViews/GalleryView.swift` | New — TabView root |
| `Sources/GalleryDemoViews/CounterTab.swift` | New |
| `Sources/GalleryDemoViews/TodoTab.swift` | New |
| `Sources/GalleryDemoViews/TodoModels.swift` | New |
| `Sources/GalleryDemoViews/CalculatorTab.swift` | New |
| `Sources/GalleryDemo/GalleryDemoApp.swift` | Unchanged |
| `Package.swift` | Maybe drop `swift-algorithms` |

## Testing

- The existing gallery has no tests and adding Swift Testing coverage for a
  demo app is not the goal. Verification is `swiftly run swift build` at the
  root and `swift run gallery-demo` from `Examples/gallery` — the demo must
  launch and be interactive without runtime errors.
- If the calculator state machine grows non-trivial, it can be unit-tested in
  isolation (pure value-type function on `CalculatorOp`), but this is optional
  and only if the implementation warrants it.

## Risks And Open Questions

- **Sheet sizing on narrow terminals.** At 80 columns the sheet needs to fit
  with chrome around it. If the default `.sheet` presentation is too wide at
  small sizes, fall back to a simpler inline reveal — but the plan is to try
  the sheet first.
- **TextFigure sizing in the counter header.** The branding figlet font needs
  to fit within ~5 rows at 80 columns. Pick a compact `EmbeddedFigletFont`
  case at implementation time rather than `.dosRebel`, which is too tall.
- **Button grid in calculator.** The zero-key spanning two columns is the only
  layout subtlety; if it fights the layout system, fall back to a uniform 4x5
  grid with a single-column zero.
