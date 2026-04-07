# Focus Style Consistency

## Problem

Focus treatments across controls are inconsistent. Some controls (Toggle, Stepper, List rows) use a visible left rail glyph (`▌`). Others (segmented Picker, TabView, TextField) rely solely on color changes (border tint, background fill) that are invisible in plain-text / low-color terminal modes. The segmented Picker is the worst case: same border characters, slightly different color — nearly invisible even in 256-color terminals.

## Design: Border Weight Escalation

A family of focus treatments that share a visual language — "heavier stroke = focused" — adapted to each control's geometry. All treatments are visible in plain text because they use different box-drawing characters, not just different colors.

### Focus Family

| Geometry | Unfocused | Focused | Mechanism |
|----------|-----------|---------|-----------|
| Box border (containers) | `╭─╮ │ │ ╰─╯` (single/rounded) | `┏━┓ ┃ ┃ ┗━┛` (heavy) | `StrokeStyle.thick` |
| Row / single-line | No rail | `▌` left rail | `controlFocusRow` (existing) |
| Tab strip | No top rule | Heavy `━` top rule spanning strip width | New top rule element |

### Controls by Category

**Container controls — promote border to heavy when focused:**
- Picker (segmented): container border `→ .thick`
- Picker (inline): container border `→ .thick`
- Picker (radio group): container border `→ .thick`
- TextField: container border `→ .thick`
- SecureField: container border `→ .thick`
- TextEditor: container border `→ .thick`
- Menu (expanded dropdown): container border `→ .thick`
- Button (bordered/borderedProminent): button border `→ .thick`

**Row controls — no change (already correct):**
- Toggle: `▌` rail via `controlFocusRow`
- Stepper: `▌` rail via `controlFocusRow`
- Slider: `▌` rail via `controlFocusRow`
- Picker (menu trigger row): `▌` rail via `controlFocusRow`
- Picker (inline/radio option rows): `▌` rail via `controlFocusRow`
- Menu (trigger row): `▌` rail via `controlFocusRow`
- DisclosureGroup: `▌` rail via `controlFocusRow`
- List rows: `▌` rail via `controlFocusRow`
- Table rows: `▌` rail via `controlFocusRow`

**Tab strip — add heavy top rule when focused:**
- TabView: add a `━` rule spanning the tab strip width above the tab labels when `focusActive`. Keep the existing color wash as color-mode reinforcement.

**Inline controls — add focus rail:**
- Button (plain style): `▌` rail via `controlFocusRow`
- Link: `▌` rail via `controlFocusRow`

### Implementation Approach

The existing `chromeStrokeBorder` already accepts a `style: StrokeStyle` parameter (defaults to `.init()` which is `.automatic`). Each container control passes a focused stroke style:

```swift
// Before:
RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
    containerChrome.borderStyle,
    backgroundStyle: containerChrome.borderBackgroundStyle
)

// After:
RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
    containerChrome.borderStyle,
    style: focusActive ? .thick : .init(),
    backgroundStyle: containerChrome.borderBackgroundStyle
)
```

For TabView, add a conditional heavy rule view above the tab labels HStack when `focusActive`:

```swift
if focusActive {
    Text(String(repeating: "━", count: stripWidth))
        .foregroundStyle(.terminalAccent(activeTone))
}
```

For plain-style Button and Link, wrap content in `controlFocusRow` (same pattern as Toggle).

### Color treatment

All existing color treatments (chrome border tint, background fills, foreground changes) remain. The heavy border is additive — it provides the plain-text signal while colors provide the rich-mode reinforcement.

### What changes for the user

- Focused containers get visibly heavier borders (both in color and plain text)
- Focused tab strip gets a top accent rule (visible in plain text)
- Focused plain buttons/links get the `▌` rail (visible in plain text)
- All other controls unchanged

### Files to modify

1. `Sources/View/Controls/PickerRendering.swift` — segmented, inline, radio group container overlays
2. `Sources/View/Controls/ValueControls.swift` — TextField container overlay
3. `Sources/View/Input/SecureField.swift` — container overlay
4. `Sources/View/Input/TextEditor.swift` — container overlay
5. `Sources/View/Controls/Button.swift` — plain button focus rail, bordered button border
6. `Sources/View/Controls/Link.swift` — focus rail
7. `Sources/View/Controls/Menu.swift` or `MenuRendering.swift` — expanded container overlay
8. `Sources/View/NavigationViews/TabView.swift` — top focus rule
9. `Tests/TerminalUITests/FocusTransitionTests.swift` — update/add tests
