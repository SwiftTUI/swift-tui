# Authoring Styles

Restyle a whole control family by conforming to its open style protocol:
compose the authored subviews, or return rendering data, and scope the
result with the family's modifier.

## Overview

Every style family in SwiftTUI has the same four parts. A public protocol
(``ButtonStyle``, ``ListStyle``, …) is what you conform to. A public
configuration (``ButtonStyleConfiguration``, ``ListStyleConfiguration``, …)
hands your conformance the authored subviews, or the framework-owned surface
data, plus the render state a style legitimately needs. A type-erased
`Any*Style` value (``AnyButtonStyle``, ``AnyListStyle``, …) is what the
environment stores. And a lower-camel-cased modifier (`buttonStyle(_:)`,
`listStyle(_:)`, …) scopes a style to one control, a subtree, or the whole
app. The nearest modifier wins, so a style set on a container applies to
every descendant unless a closer modifier overrides it:

```swift
VStack {
  Button("Save") { save() }
  Button("Cancel", role: .cancel) { cancel() }
    .buttonStyle(.plain)
}
.buttonStyle(.bordered)
```

Families come in two kinds, and the kind decides what your conformance
returns. <doc:Styling-And-Theming> introduces the built-in styles and walks
through one custom button style; this article covers the contract every
family shares. <doc:Testing-Styles> shows how to unit-test a style without
a live render.

## Body-producing styles

A body-producing style receives captured child views and returns a
replacement body. ``ButtonStyle``, ``TextFieldStyle``, ``PickerStyle``, and
``TabViewStyle`` work this way, because composition is the customization:

```swift
struct BadgeButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(configuration.focusActive ? "▶" : " ")
      configuration.label
    }
    .foregroundStyle(configuration.isEnabled ? .primary : .muted)
  }
}
```

The configuration exposes the authored subviews as nested public views —
``ButtonStyleConfiguration/Label`` here — and read-only render state:
`isEnabled`, `isFocused`, `isPressed`, `showsFocusEffect`, `role`, the
control prominence, and a ``StyleEnvironmentSnapshot`` whose `theme`
supplies the semantic palette built-in styles use. Read
``ButtonStyleConfiguration/focusActive`` rather than combining `isFocused`
and `showsFocusEffect` yourself, and never infer focus from colors.

State that a control models on a binding is exposed SwiftUI-style, as a
projected binding a style reads and writes; the binding itself cannot be
replaced. `makeBody(configuration:)` runs on the main actor. Styles are
`Sendable` value types: a class cannot conform.

## Presentation-value styles

A presentation-value style returns `Sendable` rendering data and leaves the
composition to the framework. ``ListStyle``, ``OutlineStyle``,
``TableStyle``, ``SpinnerStyle``, ``SheetStyle``, and ``ToastStyle`` take
this form because the primitive must keep an invariant an arbitrary
replacement body could break — table virtualization, spinner cadence, sheet
modality. ``ToolbarStyle`` is the same idea for a strip: it supplies the
`Layout` that arranges toolbar items and a placement.

```swift
struct DotsSpinnerStyle: SpinnerStyle {
  func resolvePresentation(
    for configuration: SpinnerStyleConfiguration
  ) -> SpinnerStylePresentation {
    SpinnerStylePresentation(
      activeFrames: configuration.accessibilityReduceMotion
        ? ["•"]
        : ["•  ", " • ", "  •"],
      interval: .milliseconds(120)
    )
  }
}

Spinner().spinnerStyle(DotsSpinnerStyle())
```

Presentation fields follow one naming rule: a field typed `AnyShapeStyle`
is a paint and is named `…Style`; a field typed `StrokeStyle` is stroke
geometry and is named `…Stroke`. Where a border is styleable the
presentation carries both, and a `nil` paint means theme-derived.

Portal families give the style the declaring modifier's own baseline rather
than making it restate the constants: ``SheetStyleConfiguration`` carries
`defaultPresentation`, and the automatic style returns it unchanged. A
custom style transforms the baseline:

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
    return presentation
  }
}
```

An invalid presentation value — empty spinner frames, a non-positive
cadence, active frames of mixed cell width — never traps. The surface emits
one `style.invalidPresentation` runtime issue naming the family and the
style, and renders the family's automatic presentation for that resolve.

## Route wrappers

Interactive configurations expose a public routing wrapper for every
synthetic pointer hit target the primitive owns. A route wrapper takes the
view you compose for that target and installs the pointer route around it;
the framework populates the identities, so a style never handles raw
identities, selection tags, or handler closures. Built-in styles use the
same wrappers as third-party styles. Today ``TabViewStyle`` ships them:
``TabViewStyleItemConfiguration/route(content:)`` selects the item,
``TabViewStyleItemConfiguration/overflowRoute(content:)`` selects it from
the overflow menu, and
``TabViewOverflowTriggerConfiguration/route(content:)`` toggles the menu.

```swift
struct PillTabViewStyle: TabViewStyle {
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    TabViewStylePresentation(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  func makeBody(configuration: TabViewStyleBodyConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        ForEach(configuration.visibleItems, id: \.index) { item in
          item.route {
            Text(item.isSelected ? "(\(item.label.displayText))" : item.label.displayText)
          }
        }
      }
      configuration.content
    }
  }
}
```

Every route wrapper follows the same rules, and none of them traps:

- **Install each route once per configuration.** Installing the same route
  again within one style body emits a `style.duplicateRoute` runtime issue.
  The first installation stays the pointer target; the later one renders
  its content without a route.
- **Omitting an optional route removes only the pointer target.** Keyboard
  interaction belongs to the primitive, which registers its handlers
  independently of whatever the style body composes. A tab strip whose
  style never calls `item.route` still changes tabs with the arrow keys.
- **Routes on a fixture-constructed configuration are inert.** They render
  their content and install nothing, which is what lets a style body
  resolve in a test with no presentation coordinator or input pipeline (see
  <doc:Testing-Styles>).

## What a style may change

A style may change composition, spacing, glyphs, borders, fill, emphasis,
and animation cadence. It may not change the primitive's accessibility
role, focus stop, command scope, binding ownership, dismissal policy, or
event precedence — those stay with the primitive for every built-in and
custom style, which is what keeps a restyled control behaving like the
control it is.

## Reuse and diagnostics

Every `Any*Style` participates in retained reuse. SwiftTUI's own built-ins
are stateless, so two instances of one built-in compare equal by type. A
custom style with stored properties compares by value when it can — conform
to `Equatable` and the reuse gate compares your stored fields — and
otherwise invalidates the styled control conservatively whenever the style
value is replaced.

Each protocol provides a `snapshotLabel`, defaulting to the type's
reflected name, that names the style in snapshot descriptions, debug
bundles, and the misuse issues above. It is diagnostic text, not identity:
do not branch on it.

## Families

At `HEAD` the environment-scoped families are ``ButtonStyle``,
``TextFieldStyle``, ``PickerStyle``, ``ListStyle``, ``OutlineStyle``,
``TableStyle``, ``SpinnerStyle``, ``SheetStyle``, ``ToolbarStyle``, and
``TabViewStyle``. ``ToastStyle`` is deliberately declaration-scoped: a
toast's tone is per-toast data, so `.toast(..., style:)` keeps its
parameter and no toast environment key exists. The remaining styleable
surfaces, and the order they gain families, are recorded in
<doc:Divergences-And-Gaps>.
