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
app. ``ToastStyle`` instead takes its value on the individual
`toast(..., style:)` declaration. For environment-scoped families, the nearest
modifier wins, so a style set on a container applies to
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
replaced. `makeBody(configuration:)` runs on the main actor. Body-producing styles are
`Sendable` value types: a class cannot conform.

``MenuStyle`` receives both `trigger { ... }` and
`portal(presentation:content:)`. The portal's closure is the inline anchor;
the configuration's captured `content` becomes its floating body. A style that
chooses inline presentation includes that content when `isPresented` is true.
If a presented style omits both content and the portal wrapper, Menu reports
`style.missingRequiredRoute` and renders its automatic body for that resolve.
``AnchoredSurfaceStylePresentation`` bounds the outer width and the content
viewport height before insets; an unbounded height preserves intrinsic layout.

``ControlGroupStyle`` composes the optional label and captured content in any
layout. Its compact built-in composes a public ``Menu``. The declaring group
owns retained child state across inline and compact hosts. Omitted content
has no live focus targets or control actions.

``PaletteStyle`` creates views from command data instead of captured content.
Its configuration supplies the declaration title, commands, terminal size,
prominence, and source style environment. Each command has an opaque contribution
ID: duplicate labels stay distinct, and changing a name or description preserves
identity. Use `command.route { ... }` for a pointer target and `command.perform()`
for a keyboard affordance. Both invoke the enabled contribution and dismiss the
palette; modifying displayed command data cannot enable a disabled contribution.
`configuration.dismiss()` supports Cancel buttons. The declaration continues to
own dropdown placement, focus gating, Escape, stacking, and lifetime.

``DefaultPaletteStyle`` implements `.automatic`: fuzzy subsequence filtering,
selection by command identity, and a window of at most twelve rows. A custom
style may implement a different filter, row layout, or sizing. Apply
`.paletteStyle(...)` outside `.paletteSheet(...)` to style that declaration.
The constrained modifier overload also preserves `ActionScope` for later scope
declarations.

## Presentation-value styles

A presentation-value style returns `Sendable` rendering data and leaves the
composition to the framework. ``ListStyle``, ``OutlineStyle``,
``TableStyle``, ``SpinnerStyle``, ``SheetStyle``, ``PromptStyle``,
``FullScreenCoverStyle``, ``PopoverStyle``, ``ToastStyle``, ``ScrollViewStyle``,
and ``LinkStyle`` take
this form because the primitive must keep an invariant an arbitrary
replacement body could break — table virtualization, spinner cadence, sheet
modality. ``ToolbarStyle`` is the same idea for a strip: it supplies the
`Layout` that arranges toolbar items and a placement.

These presentation-value protocols require `Sendable`; the authored-container
value-type witness applies to body-producing styles.

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

``PromptStyle`` serves both alerts and confirmation dialogs. Its configuration
reports whether message and action content is present and supplies that
declaration's baseline. The style does not select alignment, accessibility
role, action order, or dismissal behavior. ``FullScreenCoverStyle`` exposes
only insets and background paint because a cover always fills the terminal
and has no framework header. ``PopoverStyle`` resolves
``AnchoredSurfaceStylePresentation``; popovers retain their rounded border
baseline and their own modal policy. Boolean and item declarations read the
same style, including while closed, so a later opening uses the current value.

An invalid presentation value — empty spinner frames, a non-positive
cadence, active frames of mixed cell width — never traps. The surface emits
one `style.invalidPresentation` runtime issue naming the family and the
style, and renders the family's automatic presentation for that resolve.
Scroll styling validates each indicator glyph independently: each must be one
grapheme occupying one terminal cell. Invalid glyphs, insets, or opacity fall
back to their automatic field values while retaining other valid fields.

### Scroll and link appearance

``ScrollViewStyle`` controls content insets, indicator glyphs and paint,
background, opacity, and whether indicators reserve a track. `.automatic`
reserves tracks; `.minimal` overlays the thumb on content. Visibility still
follows `.scrollIndicators(...)`, and a style cannot enable panning unsupported
by the host. Configuration supplies the permitted and focused indicator axes,
host capability, enabled state, and `showsFocusEffect`, which distinguishes the
theme focus treatment from the semantic tint fallback. The primitive retains
clipping, offset bindings, wheel and key commands, and indicator dragging.

``LinkStyle`` applies to both standalone links and links interpolated into Text.
The renderer merges containing-text styling, then the link presentation, then
the link label's explicit styling. It stamps destination and identity last,
keeping one rich-text payload for rendering and semantic regions. Optional
foreground and background inherit when `nil`; emphasis accumulates; explicit
opacity multiplies the containing text's opacity. ``LinkUnderlineStyle``
distinguishes `.inherited`, `.hidden`, and `.visible(...)`, including an explicit
label-level removal. `.automatic` preserves theme treatment, `.underlined`
uses semantic link color, and `.plain` inherits foreground and removes the
underline. Focus, activation, disabled behavior, and accessibility stay with
the link primitive. Only unmodified Link values create inline links in
`Text.RichContent`. A modified Link cannot interpolate into that rich type;
an unconstrained string expression may instead use ordinary String formatting.
Apply `.linkStyle(...)` to the containing Text to retain link semantics.

## Route wrappers

Interactive configurations expose a public routing wrapper for every
synthetic pointer hit target the primitive owns. A route wrapper takes the
view you compose for that target and installs the pointer route around it;
the framework populates the identities, so a style never handles raw
identities, selection tags, or handler closures. Built-in styles use the
same wrappers as third-party styles. ``TabViewStyle`` ships these wrappers:
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

### Picker options and menu triggers

``PickerStyleConfiguration/Option`` exposes `index`, `label`, `isSelected`,
and `isEnabled`. Wrap an option's composed row in `option.route { … }` to
select it by occurrence, including when two labels have the same text.
The picker owns selection tags, bounds, disabled handling, and the binding.

```swift
struct CompactPickerStyle: PickerStyle {
  func selectionDelta(for event: KeyEvent) -> Int? {
    switch event {
    case .arrowUp: -1
    case .arrowDown: 1
    default: nil
    }
  }

  func makeBody(configuration: PickerStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.label
      ForEach(configuration.options, id: \.index) { option in
        option.route {
          Text(option.isSelected ? "[\(option.label)]" : option.label)
        }
      }
    }
  }
}
```

A menu style returns `true` from `wantsTriggerPointerRoute`, wraps its
trigger in ``PickerStyleConfiguration/trigger(content:)``, and shows its
options when `configuration.isActiveNavigation` is true. Pointer activation
toggles expansion; keyboard activation toggles it, Escape closes it, and
an arrow handled by `selectionDelta(for:)` reopens it while navigating.
Focus entry retains the default menu's expanded-on-focus behavior. Leaving
focus or disabling the picker resets the explicit expansion choice.
Omitting the trigger wrapper preserves all of those keyboard behaviors.

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
``TabViewStyle``, together with ``LabelStyle``, ``LabeledContentStyle``, and
``GroupBoxStyle``, ``ToggleStyle``, ``DisclosureGroupStyle``, ``TextEditorStyle``,
``ProgressViewStyle``, ``SliderStyle``, ``StepperStyle``, ``MenuStyle``,
``ControlGroupStyle``, ``PromptStyle``, ``FullScreenCoverStyle``, and ``PopoverStyle``.
``ToastStyle`` is deliberately declaration-scoped: a
toast's tone is per-toast data, so `.toast(..., style:)` keeps its
parameter and no toast environment key exists. The remaining styleable
surfaces, and the order they gain families, are recorded in
<doc:Divergences-And-Gaps>.

## Label and grouping composition

These three families receive captured authored slots and a
``StyleEnvironmentSnapshot``. The slots keep their authoring scope when the
style places them in its body. Styling introduces no focus stop or action of
its own; controls inside the slots retain their normal behavior.

| Family | Built-ins | Configuration slots |
| --- | --- | --- |
| ``LabelStyle`` | `.automatic` is a fixed alias of `.titleAndIcon`, with the icon first and one cell of spacing; `.titleOnly` and `.iconOnly` omit the other slot | `title`, `icon` |
| ``LabeledContentStyle`` | `.automatic` places a muted label and trailing content on one baseline with a flexible spacer; `.stacked` puts the content below the muted label | `label`, `content` |
| ``GroupBoxStyle`` | `.automatic` is a fixed alias of `.bordered`, with rounded chrome and one cell of interior padding; `.plain` renders the label and content without border or padding | optional `label`, `content` |

The group-box configuration also carries ``ControlProminence``. A missing
label is `nil`; an explicitly authored `EmptyView` label is a present slot.
The bordered style derives its foreground from the snapshot and uses a
neutral border, or an accent border for increased prominence.

```swift
struct CaptionLabelStyle: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.icon
      configuration.title.foregroundStyle(.secondary)
    }
  }
}

struct Details: View {
  var body: some View {
    GroupBox("Account") {
      LabeledContent("Name", value: "Ada")
    }
    .labeledContentStyle(.stacked)
    .groupBoxStyle(.plain)
  }
}
```

Each modifier accepts either a concrete style or an `Any…Style` value. The
nearest modifier wins, including a modifier on a single descendant of a
styled container. Style authoring uses an ordinary `import SwiftTUIViews`;
only fixture construction opts into the testing SPI.

## Bound controls and protected editing content

``ToggleStyleConfiguration/isOn`` and
``DisclosureGroupStyleConfiguration/isExpanded`` write through to the original
binding. Their projected bindings can be passed to child views but cannot be
replaced. The owning primitive retains keyboard and pointer activation, disabled
handling, and its semantic role. A collapsed disclosure supplies empty content.

``TextEditorStyle`` surrounds `configuration.editorContent`. The protected slot
retains text editing, selection, scrolling, and input behavior. Its measured
viewport drives wrapped caret navigation, including when a custom style adds
padding. The built-in `.automatic` style aliases `.roundedBorder`; `.plain`
removes the surrounding chrome.

``ProgressViewStyleConfiguration/fractionCompleted`` is `nil` for indeterminate
progress. Its `indeterminatePhase` is a deterministic rendering seed for moving
tracks. `.automatic` aliases `.linear`. `.circular` renders determinate progress
as a ring and composes ``Spinner`` for indeterminate progress, inheriting the
nearest spinner style. Reduced motion and stable output use static status
labels and schedule no spinner task.

For theme-consistent custom composition, the style-environment snapshot exposes
`controlChrome(isEnabled:isFocused:isPressed:isSelected:prominence:role:)` and
`rowChrome(isEnabled:isFocused:isPressed:isSelected:role:)`. These return semantic
paints and opacity; they do not install interaction.

## Value-control routes

``SliderStyleConfiguration/track(content:)`` installs the bounds used for
pointer mapping and keeps a drag captured when it leaves those bounds. The
configuration supplies a normalized fraction and the preferred track cell count;
`valueLabel` is already formatted for the primitive's Int or Double storage.
The primitive keeps clamping, step rounding, arrow keys, wheel input, and Space
activation. `.automatic` is a fixed alias of `.linear`.

``StepperStyleConfiguration/decrement(content:)`` and
``StepperStyleConfiguration/increment(content:)`` install the independent
action targets. Their content receives the appropriate disabled state. At a
numeric bound the route still claims its press and release, so a disabled
decrement cannot fall through to the primitive's increment action. The automatic
treatment uses triangle controls; `.compact` uses minus/plus without a focus rail.

Install each wrapper once. Omitting one removes that pointer target while
keyboard interaction remains available. Repeated wrappers emit
`style.duplicateRoute` and keep the first installation. Fixture-constructed
routes remain inert.
