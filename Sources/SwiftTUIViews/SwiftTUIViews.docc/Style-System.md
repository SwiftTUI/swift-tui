# The Style System

Restyle any control, container, or presentation: pick a built-in style, scope
it with one modifier, or conform to the family's open protocol.

## Overview

Every styleable surface in SwiftTUI belongs to a style family, and every
family is an open protocol. There are 28 of them, from ``ButtonStyle`` and
``ListStyle`` through ``TabViewStyle``, ``SheetStyle``, and ``PaletteStyle``,
including families SwiftUI keeps closed. Each family has the same four parts:

| Part | Example | Role |
| --- | --- | --- |
| A protocol | ``ButtonStyle`` | What you conform to. |
| A configuration | ``ButtonStyleConfiguration`` | What the framework hands your conformance: the authored subviews and the render state a style legitimately needs. |
| A type-erased value | ``AnyButtonStyle`` | What the environment carries, with a static for every built-in. |
| A modifier | `buttonStyle(_:)` | Scopes a style to one control, a subtree, or the whole app. |

The primitive keeps what makes the control a control: its focus stop,
bindings, keyboard commands, accessibility role, dismissal policy, and event
precedence. The style owns composition and appearance. That split is what lets
a restyled button still behave like a button, and it is enforced the same way
for SwiftTUI's own built-ins as for yours.

This guide is the map of the whole system. <doc:Styling-And-Theming> covers
colors, semantic roles, and the theme; <doc:Authoring-Styles> is the detailed
contract for conformances; <doc:Testing-Styles> shows how to unit-test a style.
The gallery example's Styles tab renders every family's built-ins next to a
custom conformance:

```sh
swift run --package-path gallery gallery-demo --tab styles
```

## Apply a built-in style

Each family's modifier stores a style in the environment for its subtree. The
nearest modifier wins, so a style set on a container reaches every descendant
until a closer modifier replaces it:

```swift
VStack(alignment: .leading, spacing: 1) {
  Button("Save") { save() }
  Button("Preview") { preview() }
  Button("Cancel", role: .cancel) { cancel() }
    .buttonStyle(.plain)
}
.buttonStyle(.bordered)
```

The first two buttons render bordered; the cancel button overrides the
inherited style. Every modifier accepts either a built-in static
(`.bordered`) or a concrete conformance (`MyButtonStyle()`); the generic
overload wraps the value in the family's `Any…Style` for you.

One family is deliberately not environment-scoped. A toast's tone is per-toast
data, so ``ToastStyle`` is passed to the individual declaration:

```swift
.toast("Saved", isPresented: $showSaved, style: .success)
```

## Restyle a whole subtree

Because every family reads the environment, one modifier chain restyles an
entire form. The form below is declared once; only the chain around it
changes:

```swift
struct DeployForm: View {
  enum Kit { case standard, boxed, custom }
  @State private var kit: Kit = .standard

  var body: some View {
    switch kit {
    case .standard:
      form
    case .boxed:
      form
        .buttonStyle(.bordered)
        .toggleStyle(.checkbox)
        .textFieldStyle(.roundedBorder)
        .stepperStyle(.compact)
        .progressViewStyle(.circular)
    case .custom:
      form
        .buttonStyle(BadgeButtonStyle())
        .toggleStyle(RailToggleStyle())
        .sliderStyle(BlockSliderStyle())
        .groupBoxStyle(TitledGroupBoxStyle())
    }
  }

  var form: some View {
    GroupBox("Deploy") {
      TextField("Name", text: $name)
      Toggle("Run tests", isOn: $runTests)
      Slider("Canary", value: $canary, in: 0...1)
      Stepper("Replicas", value: $replicas, in: 1...9)
      ProgressView("Rollout", value: rollout)
      Button("Save") { save() }
    }
  }
}
```

Switching the kit preserves every control's identity and state: the text
stays typed, the toggle stays set, focus stays where it was. Only the
composition changes.

## Two kinds of family

The kind decides what a conformance returns.

**Body-producing** families hand your style the captured authored subviews
and read-only render state, and your `makeBody(configuration:)` returns a
replacement body. Composition is the customization. Sixteen families work this
way: ``ButtonStyle``, ``TextFieldStyle``, ``PickerStyle``, ``ToggleStyle``,
``LabelStyle``, ``LabeledContentStyle``, ``GroupBoxStyle``,
``ControlGroupStyle``, ``MenuStyle``, ``DisclosureGroupStyle``,
``SliderStyle``, ``StepperStyle``, ``ProgressViewStyle``,
``TextEditorStyle``, ``TabViewStyle``, and ``PaletteStyle``.

**Presentation-value** families hand your style a configuration and your
`resolvePresentation(for:)` returns `Sendable` rendering data; the framework
keeps the composition because the primitive holds an invariant an arbitrary
body could break, such as table virtualization, spinner cadence, or sheet
modality. Eleven families work this way: ``ListStyle``, ``OutlineStyle``,
``TableStyle``, ``SpinnerStyle``, ``ScrollViewStyle``, ``LinkStyle``,
``SheetStyle``, ``PromptStyle``, ``FullScreenCoverStyle``, ``PopoverStyle``,
and ``ToastStyle``.

``ToolbarStyle`` is the one layout-supplying family: it provides the `Layout`
that arranges toolbar items and a placement, and has no configuration.

## Every family at a glance

`.automatic` is never adaptive: it does not read the environment and pick a
treatment. In most families it is a documented fixed alias of another
built-in, marked below as `= .other`. In the rest it is a treatment in its
own right: buttons and menus each render their own automatic body, and the
portal families return the declaring modifier's baseline unchanged. Route
wrappers are the pointer targets a style composes around; they are covered
below.

| Family | Styles | Modifier | Built-ins | Kind | Configuration highlights |
| --- | --- | --- | --- | --- | --- |
| ``ButtonStyle`` | ``Button`` | `buttonStyle(_:)` | `.automatic`, `.plain`, `.bordered`, `.borderedProminent`, `.link` | Body | `label`, `role`, `isPressed`, `focusActive`, prominence; `resolvedProminence(base:)` |
| ``TextFieldStyle`` | ``TextField`` | `textFieldStyle(_:)` | `.automatic` = `.roundedBorder`, `.plain` | Body | `label`, protected `fieldContent`, prompt state, `isEnabled`, `isFocused`, `focusActive` |
| ``PickerStyle`` | ``Picker`` | `pickerStyle(_:)` | `.automatic` = `.inline`, `.segmented`, `.radioGroup`, `.menu` | Body | `options` with `option.route`, `trigger`, `isActiveNavigation`, `focusActive`; `selectionDelta(for:)` |
| ``ToggleStyle`` | ``Toggle`` | `toggleStyle(_:)` | `.automatic`, `.checkbox`, `.button` | Body | `isOn` binding, `label`, `focusActive` |
| ``LinkStyle`` | ``Link`` and inline links in ``Text`` | `linkStyle(_:)` | `.automatic`, `.underlined`, `.plain` | Presentation | `isInline`, focus and press state; paints, emphasis, underline, opacity |
| ``LabelStyle`` | ``Label`` | `labelStyle(_:)` | `.automatic` = `.titleAndIcon`, `.titleOnly`, `.iconOnly` | Body | `title`, `icon` |
| ``LabeledContentStyle`` | ``LabeledContent`` | `labeledContentStyle(_:)` | `.automatic`, `.stacked` | Body | `label`, `content` |
| ``GroupBoxStyle`` | ``GroupBox`` | `groupBoxStyle(_:)` | `.automatic` = `.bordered`, `.plain` | Body | optional `label`, `content`, prominence |
| ``ControlGroupStyle`` | ``ControlGroup`` | `controlGroupStyle(_:)` | `.automatic` = `.horizontal`, `.vertical`, `.compactMenu` | Body | optional `label`, retained `content` |
| ``MenuStyle`` | ``Menu`` | `menuStyle(_:)` | `.automatic`, `.button`, `.borderlessButton`, `.inline` | Body | `label`, retained `content`, `isPresented`; `trigger`, `portal(presentation:content:)` |
| ``DisclosureGroupStyle`` | ``DisclosureGroup`` | `disclosureGroupStyle(_:)` | `.automatic`, `.compact` | Body | `label`, `content`, `isExpanded` binding, `focusActive`; `trigger` |
| ``SliderStyle`` | ``Slider`` | `sliderStyle(_:)` | `.automatic` = `.linear` | Body | `track`, `fractionCompleted`, `trackCellCount`, `valueLabel` |
| ``StepperStyle`` | ``Stepper`` | `stepperStyle(_:)` | `.automatic`, `.compact` | Body | `decrement`, `increment`, `valueLabel`, `canDecrement`, `canIncrement` |
| ``ProgressViewStyle`` | ``ProgressView`` | `progressViewStyle(_:)` | `.automatic` = `.linear`, `.circular` | Body | optional `fractionCompleted`, optional labels, `barWidth`, `indeterminatePhase` |
| ``SpinnerStyle`` | ``Spinner`` | `spinnerStyle(_:)` | `.automatic` and 37 glyph presets | Presentation | `stage`, `accessibilityReduceMotion`; frames and cadence |
| ``TextEditorStyle`` | ``TextEditor`` | `textEditorStyle(_:)` | `.automatic` = `.roundedBorder`, `.plain` | Body | protected `editorContent`, `focusActive` |
| ``ListStyle`` | ``List`` | `listStyle(_:)` | `.automatic` = `.insetGrouped`, `.plain` | Presentation | selection, focus, and enabled state; chrome, insets, separators |
| ``OutlineStyle`` | ``OutlineGroup`` | `outlineStyle(_:)` | `.automatic` = `.rounded`, `.plain` | Presentation | indenters and connectors |
| ``TableStyle`` | ``Table`` | `tableStyle(_:)` | `.automatic` = `.inset`, `.bordered` | Presentation | `columnCount`, `showsHeaders`, selection state; border glyphs and paints |
| ``ScrollViewStyle`` | ``ScrollView`` | `scrollViewStyle(_:)` | `.automatic`, `.minimal` | Presentation | axes, indicator axes, host capability; insets, indicator glyphs and paints |
| ``ToolbarStyle`` | the toolbar strip | `toolbarStyle(_:)` | `.defaultTop`, `.defaultBottom` | Layout | `itemLayout`, `placement` |
| ``TabViewStyle`` | ``TabView`` | `tabViewStyle(_:)` | `.automatic` = `.underline`, `.literalTabs`, `.powerline` | Body | `presentation(for:)` then `makeBody`; `item.route`, `item.overflowRoute`, `overflowTrigger.route` |
| ``SheetStyle`` | `sheet` | `sheetStyle(_:)` | `.automatic`, `.surface`, `.dropdown` | Presentation | `defaultPresentation`, `terminalSize`; container, widths, heights, paints |
| ``PromptStyle`` | `alert`, `confirmationDialog` | `promptStyle(_:)` | `.automatic` | Presentation | `hasMessage`, `hasActions`, `defaultPresentation` |
| ``FullScreenCoverStyle`` | `fullScreenCover` | `fullScreenCoverStyle(_:)` | `.automatic` | Presentation | `defaultPresentation`; insets and background |
| ``PopoverStyle`` | `popover` | `popoverStyle(_:)` | `.automatic` | Presentation | `defaultPresentation`; anchored surface bounds, paints, border |
| ``ToastStyle`` | `toast` | `toast(_:isPresented:style:)` | `.info`, `.success`, `.warning`, `.danger` | Presentation | `stackIndex`, `stackCount`; icon, paints, padding, size bounds |
| ``PaletteStyle`` | `paletteSheet` | `paletteStyle(_:)` | `.automatic` | Body | `title`, `commands` with `route` and `perform()`, `dismiss()` |

## Write a custom style

Conform to the family's protocol and hand the conformance to the family's
modifier. A body-producing style composes the captured subviews:

```swift
struct BadgeButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    let badge = configuration.isPressed ? "◆" : (configuration.focusActive ? "▶" : "·")
    return HStack(spacing: 1) {
      Text(badge)
        .foregroundStyle(theme.color(for: configuration.role == .destructive ? .danger : .tint))
      configuration.label
    }
  }
}

Button("Deploy") { deploy() }
  .buttonStyle(BadgeButtonStyle())
```

A presentation-value style returns data, usually by transforming the baseline
the declaring modifier hands it:

```swift
struct WideSheetStyle: SheetStyle {
  func resolvePresentation(
    for configuration: SheetStyleConfiguration
  ) -> SheetSurfaceStylePresentation {
    var presentation = configuration.defaultPresentation
    presentation.minimumWidth = max(
      presentation.minimumWidth,
      configuration.terminalSize.width * 3 / 4
    )
    presentation.headerTone = .success
    return presentation
  }
}
```

Styles are `Sendable` value types; a class cannot conform. Body-producing
styles may store dynamic properties (`@State`, `@Environment`, custom
wrappers), which are prepared before `makeBody` runs, and each styled control
owns its own copy of that state.

### Read the state you are given

Configurations expose render state as read-only values. Read `focusActive`
rather than combining `isFocused` with `showsFocusEffect` yourself: a control
under `focusEffectDisabled()` is still focused for keyboard purposes but must
not draw a focus treatment. Where a control models state on a binding
(`isOn`, `isExpanded`), the configuration exposes the projected binding; you
can pass it to child views but not replace it. Never infer state from colors.

### Compose around the routes

Interactive configurations expose a route wrapper for every synthetic pointer
target the primitive owns: `option.route` and `trigger` on pickers, `trigger`
on disclosure groups, `track` on sliders, `decrement` and `increment` on
steppers, `trigger` and `portal(presentation:content:)` on menus, `item.route`,
`item.overflowRoute`, and `overflowTrigger.route` on tab strips, and
`command.route` on palettes. Wrap the view you compose for that
target; the framework supplies the identities. The rules are the same
everywhere:

- Install each route once per configuration. A repeat reports
  `style.duplicateRoute` and the first installation stays the target.
- Omitting an optional route removes only the pointer target. Keyboard
  interaction belongs to the primitive and keeps working.
- Routes on a fixture-constructed configuration are inert, which is what
  makes styles unit-testable.

### Match the theme

`configuration.styleEnvironment` is a `StyleEnvironmentSnapshot`: the
detected terminal `appearance`, the active `theme`, the ambient foreground and
tint paints, the enabled state, and the terminal's cell pixel metrics. Built-in
styles derive every color from it, and the same helpers are public:
`theme.color(for:)` and `theme.style(for:)` for a semantic role,
`resolvedStyle(for:)` for a role honoring ambient overrides, and
`controlChrome(...)`, `rowChrome(...)`, and `groupBoxChrome(prominence:)` for
the paints and opacity a focused, pressed, selected, or disabled surface uses.
None of them install interaction.

### What a style may change

A style may change composition, spacing, glyphs, borders, fill, emphasis, and
animation cadence. It may not change the primitive's accessibility role, focus
stop, command scope, binding ownership, dismissal policy, or event precedence.
Those stay with the primitive for every built-in and custom style.

Controls derive their accessible names from the authored label slot, before
style chrome, shortcut hints, and displayed control values are added. A composed
label contributes its text in authored order; `Label` contributes its title,
not its icon. Hidden label content is excluded, and explicit
`accessibilityLabel(_:)` values replace inferred text, including empty overrides.
Repeating the label slot in a style does not repeat the control's name.

A literal `Text` title remains available when the style omits the slot, including
an icon-only `Label`. If a custom style omits a generic label whose name requires
evaluating its body, supply `accessibilityLabel(_:)` on the control. Accessibility
extraction does not instantiate omitted bodies or run a second copy of their
state, tasks, or handlers. These names are part of the shared semantic snapshot
used by terminal, browser, and native hosts.

## Diagnostics

Nothing in the style system traps on a bad style. Each problem reports a
runtime issue and falls back:

- `style.duplicateRoute`: a route installed twice in one body; the first wins.
- `style.duplicateContent`: retained Menu or ControlGroup content placed twice
  in one body; the first placement owns the content and later placements are
  omitted. Alternative candidates in `ViewThatFits` may each place it once.
- `style.missingRequiredRoute`: a presented menu style omitted both its
  content and its portal wrapper; the automatic body renders for that resolve.
- `style.invalidPresentation`: a presentation value the surface cannot honor,
  such as empty spinner frames, a non-positive cadence, an inset too large for
  the terminal, or a tab index outside the options. The surface renders the
  family's automatic presentation for that resolve. Spinner, scroll, link,
  menu portal, sheet, prompt, cover, popover, toast, tab-view, list, outline, and table presentations
  are validated; scroll and link validate per field and keep the valid fields.
  Toolbar has no presentation value; its closed placement enum and public
  `Layout` use the ordinary layout contract and diagnostics.

Every style reports a `snapshotLabel` (by default the reflected type name)
that names it in snapshot descriptions, debug bundles, and the issues above.
Built-ins pin theirs (`"ButtonStyle.bordered"`, `"SpinnerStyle.dotChase"`).
It is diagnostic text, not identity: do not branch on it.

Every `Any…Style` participates in retained reuse. SwiftTUI's stateless
built-ins compare equal by type; spinner presets compare by value. A custom
style with stored properties compares by value when it conforms to
`Equatable`, and otherwise invalidates the styled control whenever the style
value is replaced.

## Test a style

A test target opts into the fixture surface with one import attribute and
constructs configurations directly:

```swift
@_spi(StyleFixtures) import SwiftTUIViews
```

Every configuration, captured slot, and presentation value in the shipped
families is fixture-constructible, and fixture routes are inert.
<doc:Testing-Styles> walks through body-producing, presentation-value, and
route-bearing styles.

## See Also

- <doc:Styling-And-Theming>
- <doc:Authoring-Styles>
- <doc:Testing-Styles>
- <doc:Forms-And-Controls>
- <doc:Divergences-And-Gaps>
