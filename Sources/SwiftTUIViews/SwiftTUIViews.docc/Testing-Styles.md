# Testing Styles

Unit-test a custom style without a live render: opt a test target into the
style-fixture SPI, construct a configuration with fixture state, and assert
on the resolved body or presentation value.

## Overview

The framework constructs style configurations while it resolves a control,
which is the right contract for application code — a style reads what it is
handed and never fabricates render state. It is the wrong contract for a
style library's test suite, which wants to hand its style a focused,
disabled, or pressed configuration directly and check the result.

SwiftTUI keeps both by exposing the construction surface as system
programming interface. A test target opts in with one import attribute:

```swift
@_spi(StyleFixtures) import SwiftTUIViews
```

Behind that import every configuration, captured-slot type, and
presentation value in the shipped families has a public initializer.
Application code that authors or applies styles never sees it, so the
framework-constructs-configurations invariant holds everywhere outside
explicitly opted-in test code. Use the attribute in test targets only.

## Resolving a body-producing style

Build the configuration, hand it to your style, and render the body with a
renderer from `SwiftTUIRuntime`. The captured slots take a view builder:

```swift
import SwiftTUIRuntime
import Testing

@_spi(StyleFixtures) import SwiftTUIViews

@MainActor
@Suite
struct BadgeButtonStyleTests {
  @Test("a focused, enabled button shows the badge")
  func focusedButtonShowsBadge() {
    let configuration = ButtonStyleConfiguration(
      label: .init { Text("Save") },
      role: nil,
      isEnabled: true,
      isFocused: true,
      showsFocusEffect: true,
      isPressed: false,
      controlProminence: .standard,
      buttonBorderShape: .automatic,
      styleEnvironment: StyleEnvironmentSnapshot()
    )

    let artifacts = DefaultRenderer().render(
      BadgeButtonStyle().makeBody(configuration: configuration),
      proposal: .init(width: 16, height: 1)
    )

    #expect(artifacts.rasterSurface.lines[0].hasPrefix("▶ Save"))
  }
}
```

``StyleEnvironmentSnapshot`` has a public initializer whose defaults are the
fallback terminal appearance and the theme synthesized from it; pass an
explicit `theme:` to test a palette. The text-field configuration's
`FieldContent` slot and the tab-view body configuration's `Content` slot
have fixture initializers too — the former from a display string, the
latter from a view builder or empty.

## Resolving a presentation-value style

Presentation-value families need no renderer at all. Construct the
configuration and compare the returned value:

```swift
@Test("reduced motion collapses the spinner to one frame")
func reducedMotionUsesOneFrame() {
  let presentation = DotsSpinnerStyle().resolvePresentation(
    for: SpinnerStyleConfiguration(
      stage: .active,
      accessibilityReduceMotion: true,
      styleEnvironment: StyleEnvironmentSnapshot()
    )
  )
  #expect(presentation.activeFrames == ["•"])
}
```

Portal families take their modifier-owned baseline as a field, so a test
passes the baseline it wants to see transformed:

```swift
let presentation = WideSheetStyle().resolvePresentation(
  for: SheetStyleConfiguration(
    defaultPresentation: SheetSurfaceStylePresentation(minimumWidth: 20),
    terminalSize: CellSize(width: 100, height: 30),
    controlProminence: .standard,
    styleEnvironment: StyleEnvironmentSnapshot()
  )
)
#expect(presentation.minimumWidth == 75)
```

## Routes on fixtures are inert

A fixture-constructed configuration carries no control identity, so its
route wrappers render their content and install no pointer target. That is
what lets a tab-view style body resolve in a test with no `TabView`,
presentation coordinator, or input pipeline behind it:

```swift
let items = ["Home", "Logs"].enumerated().map { index, title in
  TabViewStyleItemConfiguration(
    index: index,
    label: TabItemLabel(title),
    isSelected: index == 0,
    isFocused: false
  )
}
let styleConfiguration = TabViewStyleConfiguration(
  options: items.map { TabViewStyleOption(label: $0.label) },
  selectedIndex: 0,
  focusedIndex: nil,
  isFocused: false,
  showsFocusEffect: true,
  styleEnvironment: StyleEnvironmentSnapshot(),
  availableWidth: 40,
  isOverflowMenuExpanded: false
)
let configuration = TabViewStyleBodyConfiguration(
  styleConfiguration: styleConfiguration,
  presentation: PillTabViewStyle().presentation(for: styleConfiguration),
  items: items,
  overflowTrigger: nil,
  content: .init { Text("Home content") }
)

let artifacts = DefaultRenderer().render(
  PillTabViewStyle().makeBody(configuration: configuration),
  proposal: .init(width: 40, height: 2)
)
#expect(artifacts.rasterSurface.lines[0].hasPrefix("(Home) Logs"))
#expect(artifacts.rasterSurface.lines[1].hasPrefix("Home content"))
```

The tab-view item and overflow-trigger configurations predate the SPI and
keep ordinary public initializers as their fixture path; the body
configuration is SPI-gated like the other families.

## What the fixture surface covers

| Family | Fixture-constructible |
| --- | --- |
| ``ButtonStyle`` | ``ButtonStyleConfiguration`` and its `Label` slot |
| ``LabelStyle`` | ``LabelStyleConfiguration`` and its `Title` and `Icon` slots |
| ``LabeledContentStyle`` | ``LabeledContentStyleConfiguration`` and its `Label` and `Content` slots |
| ``GroupBoxStyle`` | ``GroupBoxStyleConfiguration`` and its `Label` and `Content` slots; pass `nil` for an absent label |
| ``ToggleStyle`` | ``ToggleStyleConfiguration`` and its `Label` slot; supply a constant or write-counted binding |
| ``DisclosureGroupStyle`` | ``DisclosureGroupStyleConfiguration`` and its `Label` and `Content` slots |
| ``TextEditorStyle`` | ``TextEditorStyleConfiguration`` and `EditorContent(displayText:)`; the editor fixture is inert |
| ``ProgressViewStyle`` | ``ProgressViewStyleConfiguration`` and optional `Label` and `CurrentValueLabel` slots; `indeterminatePhase` defaults to zero |
| ``SliderStyle`` | ``SliderStyleConfiguration`` and `Label`/`ValueLabel` slots; the track route is inert |
| ``StepperStyle`` | ``StepperStyleConfiguration`` and `Label`/`ValueLabel` slots; both action routes are inert |
| ``MenuStyle`` | ``MenuStyleConfiguration`` and `Label`/`Content` slots; trigger and portal wrappers are inert |
| ``ControlGroupStyle`` | ``ControlGroupStyleConfiguration`` and optional `Label` plus `Content` slots |
| ``PaletteStyle`` | ``PaletteStyleConfiguration`` and `Command(id:name:description:isEnabled:)`; command routes, activation, and dismissal are inert |
| ``TextFieldStyle`` | ``TextFieldStyleConfiguration``, its `Label` slot, and `FieldContent` |
| ``PickerStyle`` | ``PickerStyleConfiguration``, its `Label` slot, and `Option` fixtures; option and trigger routes are inert |
| ``ListStyle`` | ``ListStyleConfiguration`` |
| ``OutlineStyle`` | ``OutlineStyleConfiguration`` |
| ``TableStyle`` | ``TableStyleConfiguration`` |
| ``SpinnerStyle`` | ``SpinnerStyleConfiguration`` |
| ``SheetStyle`` | ``SheetStyleConfiguration`` |
| ``PromptStyle`` | ``PromptStyleConfiguration`` with message/action presence and the declaration's baseline |
| ``FullScreenCoverStyle`` | ``FullScreenCoverStyleConfiguration`` |
| ``PopoverStyle`` | ``PopoverStyleConfiguration`` |
| ``ScrollViewStyle`` | ``ScrollViewStyleConfiguration`` with axes, permitted indicators, host capability, and focus state |
| ``LinkStyle`` | ``LinkStyleConfiguration`` with inline, enabled, focused, and pressed state |
| ``ToastStyle`` | ``ToastStyleConfiguration`` |
| ``TabViewStyle`` | ``TabViewStyleBodyConfiguration`` and its `Content` slot; the item, trigger, and strip configurations through their public initializers |

Presentation values (``AnchoredSurfaceStylePresentation``, ``SpinnerStylePresentation``,
``SheetSurfaceStylePresentation``, ``PromptSurfaceStylePresentation``,
``FullScreenSurfaceStylePresentation``, ``ToastStylePresentation``,
``TabViewStylePresentation``, ``ScrollViewStylePresentation``,
``LinkStylePresentation``, and the collection presentations) have public
initializers because styles construct them. SPI symbols do not appear in the
reference documentation; the initializers mirror the configuration's
documented stored properties in declaration order.

Picker fixtures can omit `controlIdentity`. The older initializer spelling
with an explicit identity remains available, but neither form enables
routes. The parent configuration derives option indices, selection, and
enabled state from its option order and control state. To test one option
independently, the SPI also provides
`PickerStyleConfiguration.Option(index:label:isSelected:isEnabled:)`.

## Keeping the seam honest

For example, a label-style test supplies both authored slots without a live
control:

```swift
let configuration = LabelStyleConfiguration(
  title: .init { Text("Save") },
  icon: .init { Text("*") },
  styleEnvironment: StyleEnvironmentSnapshot()
)
let body = TitleOnlyLabelStyle().makeBody(configuration: configuration)
let artifacts = DefaultRenderer().render(body, proposal: .init(width: 12, height: 1))
#expect(artifacts.rasterSurface.lines[0].contains("Save"))
#expect(!artifacts.rasterSurface.lines[0].contains("*"))
```

Assert on what the style resolved, not on framework internals: raster
lines, presentation fields, and the presence or absence of your own
composed text. A style test that passes identically with and without the
behaviour it means to check is measuring nothing — verify a control arm
fails before trusting the green.
