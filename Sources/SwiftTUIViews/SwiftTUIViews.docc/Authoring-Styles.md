# Authoring Styles

Restyle a whole control family by conforming to its open style protocol:
compose the authored subviews, or return rendering data, and scope the
result with the family's modifier.

## Overview

Every style family in SwiftTUI has the same four parts. A public protocol
(``ButtonStyle``, ``ListStyle``, and their peers) is what you conform to. A
public configuration (``ButtonStyleConfiguration``, ``ListStyleConfiguration``,
and so on) hands your conformance the authored subviews, or the framework-owned
surface data, plus the render state a style legitimately needs; ``ToolbarStyle``
alone has no configuration, because it supplies a layout and a placement rather
than reading state. A type-erased `Any*Style` value (``AnyButtonStyle``,
``AnyListStyle``, and so on) is what the environment stores. And a
lower-camel-cased modifier (`buttonStyle(_:)`, `listStyle(_:)`, and so on)
scopes a style to one control, a subtree, or the whole app. ``ToastStyle``
instead takes its value on the individual `toast(..., style:)` declaration. For
environment-scoped families, the nearest modifier wins, so a style set on a
container applies to every descendant unless a closer modifier overrides it:

```swift
VStack {
  Button("Save") { save() }
  Button("Cancel", role: .cancel) { cancel() }
    .buttonStyle(.plain)
}
.buttonStyle(.bordered)
```

Families come in two kinds, and the kind decides what your conformance
returns. <doc:Style-System> is the map of all 28 families with every built-in
and configuration in one table; <doc:Styling-And-Theming> introduces colors,
the theme, and walks through one custom button style; this article covers the
contract every family shares. <doc:Testing-Styles> shows how to unit-test a
style without a live render.

## Body-producing styles

A body-producing style receives captured child views and returns a
replacement body, because composition is the customization. Sixteen families
work this way: ``ButtonStyle``, ``TextFieldStyle``, ``PickerStyle``,
``ToggleStyle``, ``LabelStyle``, ``LabeledContentStyle``, ``GroupBoxStyle``,
``ControlGroupStyle``, ``MenuStyle``, ``DisclosureGroupStyle``, ``SliderStyle``,
``StepperStyle``, ``ProgressViewStyle``, ``TextEditorStyle``, ``TabViewStyle``,
and ``PaletteStyle``.

```swift
struct BadgeButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    return HStack(spacing: 1) {
      Text(configuration.focusActive ? "▶" : " ")
      configuration.label
    }
    .foregroundStyle(theme.color(for: configuration.isEnabled ? .foreground : .muted))
  }
}
```

The configuration exposes the authored subviews as nested public views
(``ButtonStyleConfiguration/Label`` here) and read-only render state:
`isEnabled`, `isFocused`, `isPressed`, `showsFocusEffect`, `role`, the
control prominence, and a `StyleEnvironmentSnapshot` whose `theme`
supplies the semantic palette built-in styles use. Every interactive
configuration exposes `focusActive`; read it rather than combining
`isFocused` and `showsFocusEffect` yourself, because a control under
`focusEffectDisabled()` is still focused for keyboard purposes but must not
draw a focus treatment. Never infer focus from colors.

Where a control models state on a binding, the configuration exposes the
projected binding SwiftUI-style: ``ToggleStyleConfiguration/isOn``,
``DisclosureGroupStyleConfiguration/isExpanded``, and
``MenuStyleConfiguration/isPresented``. A style reads and writes through it and
can pass it to child views, but cannot replace it. Slider and stepper
configurations expose no binding at all: they hand the style a normalized
`fractionCompleted`, `canDecrement` and `canIncrement`, and a `valueLabel`
already formatted for the primitive's `Int` or `Double` storage.

`makeBody(configuration:)` runs on the main actor. Body-producing styles are
`Sendable` value types: a class cannot conform. A style may store dynamic
properties (`@State`, `@Environment`, custom wrappers); they are prepared before
`makeBody` runs, and each styled control owns its own copy of that state even
when several controls inherit the same environment style value.

### Menus, groups, and palettes

``MenuStyle`` receives both `trigger { ... }` and
`portal(presentation:content:)`. The portal's closure is the inline anchor;
the configuration's captured `content` becomes its floating body. A style that
chooses inline presentation includes that content when `isPresented` is true.
If a presented style omits both content and the portal wrapper, Menu reports
`style.missingRequiredRoute` and renders its automatic body for that resolve.
``AnchoredSurfaceStylePresentation`` bounds the outer width and the content
viewport height before insets; an unbounded height preserves intrinsic layout.
A disabled menu keeps its expansion: disabling one while it is presented
leaves the content visible with its commands and trigger disabled, and its
Escape dismissal handler stays installed for inline and floating styles alike.
Closing removes that exception; modal suppression and sealed focus hosts still
apply. Keyboard bubbling follows the focused control's scope. The menu
declaration owns its captured content across inline and floating hosts: a
same-frame move preserves state and running tasks, closing the menu retains
persistent state and cancels tasks, and reopening restarts them.

``ControlGroupStyle`` composes the optional label and captured content in any
layout. Its compact built-in composes a public ``Menu`` whose trigger title is
the group's label, or the fixed text "Controls" when the group has none. The
declaring group owns retained child state across inline and compact hosts, and
omitted content has no live focus targets or control actions. Value-only
retained archives also survive dormancy of an enclosing lazy tab; reference-
valued archives obey the tab's existing rejection-and-restart rule. Placing
retained content twice in one body emits `style.duplicateContent`: the first
placement owns the content and later placements are omitted. `ViewThatFits`
candidates may each place it once. The diagnostic has the same per-resolve
scope as route diagnostics; selective evaluator reruns and depth-cut resolves
outside that scope cannot diagnose every repeated placement.

``PaletteStyle`` creates views from command data instead of captured content.
Its configuration supplies the declaration title, commands, terminal size,
prominence, and source style environment. Each command has an opaque
contribution ID: duplicate labels stay distinct, and changing a name or
description preserves identity. Use `command.route { ... }` for a pointer
target and `command.perform()` for a keyboard affordance. Both invoke the
enabled contribution and dismiss the palette; modifying displayed command data
cannot enable a disabled contribution. `configuration.dismiss()` supports
Cancel buttons. The declaration continues to own dropdown placement, focus
gating, Escape, stacking, and lifetime. ``DefaultPaletteStyle`` implements
`.automatic`: fuzzy subsequence filtering, selection by command identity, and
a window of at most twelve rows. A custom style may implement a different
filter, row layout, or sizing. Apply `.paletteStyle(...)` outside
`.paletteSheet(...)` to style that declaration; the constrained modifier
overload also preserves `ActionScope` for later scope declarations.

### Labels and grouping

``LabelStyle``, ``LabeledContentStyle``, and ``GroupBoxStyle`` receive captured
authored slots and a `StyleEnvironmentSnapshot`. The slots keep their
authoring scope when the style places them in its body. Styling introduces no
focus stop or action of its own; controls inside the slots retain their normal
behavior. Unlike ``ControlGroupStyle``, these families do not retain a slot's
child state when a style hosts the slot elsewhere or omits it, so keep a slot
in the body when its content owns state.

| Family | Built-ins | Configuration slots |
| --- | --- | --- |
| ``LabelStyle`` | `.automatic` is a fixed alias of `.titleAndIcon`, with the icon first and one cell of spacing; `.titleOnly` and `.iconOnly` omit the other slot | `title`, `icon` |
| ``LabeledContentStyle`` | `.automatic` places a label in the separator role and trailing content on one baseline with a flexible spacer; `.stacked` puts the content below the label | `label`, `content` |
| ``GroupBoxStyle`` | `.automatic` is a fixed alias of `.bordered`, with rounded chrome and one cell of interior padding; `.plain` renders the label and content without border or padding | optional `label`, `content` |

The group-box configuration also carries `ControlProminence`. A missing
label is `nil`; an explicitly authored `EmptyView` label is a present slot.
The bordered style takes its foreground and border paints from the snapshot's
`groupBoxChrome(prominence:)`, a neutral border at standard prominence and the
accent tone at increased prominence, and a custom style can call the same
helper to match it.

```swift
struct CaptionLabelStyle: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.icon
      configuration.title.foregroundStyle(.muted)
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

### Bound controls and protected editing content

``ToggleStyleConfiguration/isOn`` and
``DisclosureGroupStyleConfiguration/isExpanded`` write through to the original
binding. The owning primitive retains keyboard activation, disabled handling,
and its semantic role. A disclosure group's pointer activation is a route:
wrap the label row in ``DisclosureGroupStyleConfiguration/trigger(content:)``
once, and a press on the expanded content leaves the expansion alone; a style
that omits the wrapper keeps keyboard toggling only. A collapsed disclosure
supplies empty content.
`ToggleStyleConfiguration.isMixed` is reserved for a mixed state the primitive
does not yet produce; it is always `false` today.

``TextEditorStyle`` surrounds `configuration.editorContent`. The protected slot
retains text editing, selection, scrolling, and input behavior. Its measured
viewport drives wrapped caret navigation, including when a custom style adds
padding. The built-in `.automatic` style aliases `.roundedBorder`; `.plain`
removes the surrounding chrome. The rounded built-in sizes its chrome with a
package-only layout hint; a public style that approximates it with
`.frame(minHeight:)` grows to fill a finite proposal, which is a documented
difference rather than a bug.

``TextFieldStyle`` likewise surrounds the protected `fieldContent` slot, which
keeps editing, the caret, and paste; the configuration reports `showsLabel`,
`isShowingPrompt`, the placeholder paint, and the focus and enabled state.
`.automatic` is a fixed alias of `.roundedBorder`.

``ProgressViewStyleConfiguration/fractionCompleted`` is `nil` for indeterminate
progress. Its optional label slots are `nil` for an absent label and for an
explicitly authored `EmptyView`, because the unlabeled initializers author
one; the group-box rule that an authored `EmptyView` is a present slot does
not apply here. Its `indeterminatePhase` is a live phase the primitive advances
on a cadence for moving tracks. `.automatic` aliases `.linear`. `.circular`
renders determinate progress as a ring and composes ``Spinner`` for
indeterminate progress, inheriting the nearest spinner style. Reduced motion
and stable output use static status labels and schedule no spinner task; the
configuration's `accessibilityReduceMotion` is `true` under either policy.

### Value-control routes

``SliderStyleConfiguration/track(content:)`` installs the bounds used for
pointer mapping and keeps a drag captured when it leaves those bounds. The
configuration supplies a normalized fraction and `trackCellCount`, the cell
count the primitive prefers for its track (currently a constant eight; a style
may draw any width inside the route). The primitive keeps clamping, step
rounding, arrow keys, wheel input, and Space activation. `.automatic` is a
fixed alias of `.linear`.

``StepperStyleConfiguration/decrement(content:)`` and
``StepperStyleConfiguration/increment(content:)`` install the independent
action targets. Their content receives the appropriate disabled state. At a
numeric bound the route still claims its press and release, so a disabled
decrement cannot fall through to the primitive's increment action. The automatic
treatment uses triangle controls with a focus rail; `.compact` uses minus and
plus without the rail.

### Picker options and menu triggers

``PickerStyleConfiguration/Option`` exposes `index`, `label`, `isSelected`,
and `isEnabled`. Wrap an option's composed row in `option.route { … }` to
select it by occurrence, including when two labels have the same text.
The picker owns selection tags, bounds, disabled handling, and the binding;
`viewportLineCount` and `lineWidth` are supplied by the framework for the
menu treatment and cannot be set from app code. `.automatic` is a fixed alias
of `.inline`.

```swift
struct CompactPickerStyle: PickerStyle {
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

### Tab strips

``TabViewStyle`` runs in two steps: `presentation(for:)` returns the strip
height and which options are visible or overflow, then `makeBody` composes the
strip and the selected content. `.automatic` is a fixed alias of `.underline`;
`.literalTabs` brackets each title and `.powerline` draws powerline
separators. The item configuration ships these route wrappers:
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
            Text(item.isSelected ? "(\(item.label.title))" : item.label.title)
          }
        }
      }
      configuration.content
    }
  }
}
```

## Presentation-value styles

A presentation-value style returns `Sendable` rendering data and leaves the
composition to the framework. ``ListStyle``, ``OutlineStyle``,
``TableStyle``, ``SpinnerStyle``, ``SheetStyle``, ``PromptStyle``,
``FullScreenCoverStyle``, ``PopoverStyle``, ``ToastStyle``, ``ScrollViewStyle``,
and ``LinkStyle`` take this form because the primitive must keep an invariant
an arbitrary replacement body could break: table virtualization, spinner
cadence, sheet modality. ``ToolbarStyle`` is the same idea for a strip: it
supplies the `Layout` that arranges toolbar items and a placement, and its
`snapshotLabel` keys the strip cache, so two toolbar styles with one label must
render one strip.

These presentation-value protocols require `Sendable`; the authored-container
value-type witness applies to body-producing styles.

```swift
struct DotsSpinnerStyle: SpinnerStyle {
  func resolvePresentation(
    for configuration: SpinnerStyleConfiguration
  ) -> SpinnerStylePresentation {
    SpinnerStylePresentation(
      activeFrames: configuration.accessibilityReduceMotion
        ? ["•  "]
        : ["•  ", " • ", "  •"],
      interval: .milliseconds(120)
    )
  }
}

Spinner().spinnerStyle(DotsSpinnerStyle())
```

The primitive already collapses spinner animation to the first active frame
under reduced motion or stable output before it consults the style, so a style
need not branch on `accessibilityReduceMotion`, but may return fewer frames.

Presentation fields follow one naming rule: a field typed `AnyShapeStyle`
is a paint and is named `…Style`; a field typed `StrokeStyle` is stroke
geometry and is named `…Stroke`. Where a border is styleable the
presentation carries both, with two exceptions that predate the rule:
``ToastStylePresentation`` carries `borderStyle` only, and the collection
container chrome's `strokeStyle` is stroke geometry. Sheet and prompt paints
are optional, and a `nil` paint means theme-derived; cover and popover
surfaces carry a concrete background paint whose default is the theme's
surface background.

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

The sheet's `.surface` built-in is the centered, bordered `.standard`
container, which honors every field of its presentation. The `.dropdown`
built-in is a full-width strip without header chrome: it honors the scroll
heights, `contentInsets` (applied inside its scroll body), `backdropOpacity`,
`backgroundStyle`, and `borderStyle` (as its bottom rule), and ignores
`minimumWidth`, `maximumWidth`, `headerTone`, and `borderStroke`.

``PromptStyle`` serves both alerts and confirmation dialogs. Its configuration
reports whether message and action content is present and supplies that
declaration's baseline. The style does not select alignment, accessibility
role, action order, or dismissal behavior. ``FullScreenCoverStyle`` exposes
only insets and background paint because a cover always fills the terminal
and has no framework header. ``PopoverStyle`` resolves
``AnchoredSurfaceStylePresentation``; popovers retain their rounded border
baseline and their own modal policy. Boolean and item declarations read the
same style, including while closed, so a later opening uses the current value.
``ToastStyle`` has no baseline: its configuration carries the toast's stack
position and the terminal size, and its presentation supplies the icon, paints,
padding, and size bounds outright.

An invalid presentation value — empty spinner frames, a non-positive
cadence, active frames of mixed cell width, an inset or extent too large to
add to a terminal extent, a tab strip whose visible or overflow indices fall
outside the options, repeat, or overlap, a toast whose width or height bounds
are out of order or whose padding leaves no room in the terminal — never
traps. The surface emits one `style.invalidPresentation` runtime issue naming
the family and the style, and renders the family's automatic presentation for
that resolve: a tab view keeps the style's body and replaces only the
presentation value, and a toast renders the info presentation. Two
families whose values carry independent fields fall back per field instead:
scroll styling validates each indicator glyph (one grapheme in one terminal
cell), the insets, and the opacity on their own, and link styling validates
its optional opacity, so an invalid field uses its automatic value while the
valid fields are kept; an invalid link opacity uses the automatic opacity for
the same control state, including disabled dimming. A closed portal declaration reads its style, so a
later opening uses the current value, but does not call it: nothing that
never renders falls back or reports. A spinner reports once per invalid style
value, not once per animated frame. List, outline, table, and toolbar
presentations are not validated: an out-of-range value there degrades
silently.

### Collections

``ListStyle``, ``OutlineStyle``, and ``TableStyle`` return the chrome, insets,
separators, glyphs, and paints their primitives draw around authored rows;
the primitives keep selection, focus, virtualization, and row content.
`.automatic` is a fixed alias of `.insetGrouped` for lists, `.rounded` for
outlines, and `.inset` for tables. Their erasers stamp the style's own
`snapshotLabel` onto the returned presentation; the scroll eraser passes the
presentation's label through.

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
label-level removal. `.automatic` and `.underlined` render identically for an
enabled link (the theme's link color with a solid underline) and differ only
when disabled, where `.underlined` keeps the link color; `.plain` inherits the
foreground and removes the underline. Focus, activation, disabled behavior, and
accessibility stay with the link primitive. Only unmodified Link values create
inline links in `Text.RichContent`. A modified Link cannot interpolate into
that rich type; an unconstrained string expression may instead use ordinary
String formatting. Apply `.linkStyle(...)` to the containing Text to retain
link semantics.

## Route wrappers

Interactive configurations expose a public routing wrapper for every
synthetic pointer hit target the primitive owns. A route wrapper takes the
view you compose for that target and installs the pointer route around it;
the framework populates the identities, so a style never handles raw
identities, selection tags, or handler closures. Built-in styles use the
same wrappers as third-party styles. The wrappers are `option.route` and
`trigger` on pickers, `trigger` on disclosure groups, `track` on sliders,
`decrement` and `increment` on steppers, `trigger` and
`portal(presentation:content:)` on menus, `item.route`, `item.overflowRoute`,
and `overflowTrigger.route` on tab strips, and `command.route` on palettes.

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
- **A route offered in several candidates of a `ViewThatFits` is one
  installation per placed candidate.** Every candidate resolves and layout
  places one, so each candidate claims its routes on its own ledger: no
  duplicate is reported across candidates, and the placed candidate keeps
  its pointer target. A duplicate inside one candidate still reports.

## Matching the theme

For theme-consistent custom composition, the style-environment snapshot
exposes `theme.color(for:)` and `theme.style(for:)` for a semantic role,
`resolvedStyle(for:)` for a role honoring the ambient foreground and tint
overrides, `controlChrome(isEnabled:isFocused:isPressed:isSelected:prominence:role:)`
and `rowChrome(isEnabled:isFocused:isPressed:isSelected:role:)` for the paints
and opacity of a focused, pressed, selected, or disabled surface, and
`groupBoxChrome(prominence:)` for container chrome. These return semantic
paints and opacity; they do not install interaction. The snapshot also carries
the terminal's `cellPixelMetrics`, resolved from the live environment.

## What a style may change

A style may change composition, spacing, glyphs, borders, fill, emphasis,
and animation cadence. It may not change the primitive's accessibility
role, focus stop, command scope, binding ownership, dismissal policy, or
event precedence. Those stay with the primitive for every built-in and
custom style, which is what keeps a restyled control behaving like the
control it is.

## Reuse and diagnostics

Every `Any*Style` participates in retained reuse. SwiftTUI's stateless
built-ins compare equal by type; the spinner presets are values of one glyph
style and compare by value. A custom style with stored properties compares by
value when it can (conform to `Equatable` and the reuse gate compares your
stored fields) and otherwise invalidates the styled control conservatively
whenever the style value is replaced.

Each protocol provides a `snapshotLabel`, defaulting to the type's
reflected name, that names the style in snapshot descriptions, debug
bundles, and the misuse issues above. Built-ins pin theirs
(`"ButtonStyle.bordered"`, `"AnyTabViewStyle.underline"`). It is diagnostic
text, not identity: do not branch on it. The one place it is load-bearing is
the toolbar strip cache noted above.

## Families

At `HEAD` the environment-scoped families are ``ButtonStyle``,
``TextFieldStyle``, ``PickerStyle``, ``ListStyle``, ``OutlineStyle``,
``TableStyle``, ``SpinnerStyle``, ``SheetStyle``, ``ToolbarStyle``,
``TabViewStyle``, ``LabelStyle``, ``LabeledContentStyle``, ``GroupBoxStyle``,
``ToggleStyle``, ``DisclosureGroupStyle``, ``TextEditorStyle``,
``ProgressViewStyle``, ``SliderStyle``, ``StepperStyle``, ``MenuStyle``,
``ControlGroupStyle``, ``PromptStyle``, ``FullScreenCoverStyle``,
``PopoverStyle``, ``PaletteStyle``, ``ScrollViewStyle``, and ``LinkStyle``.
``ToastStyle`` is deliberately declaration-scoped: a toast's tone is per-toast
data, so `.toast(..., style:)` keeps its parameter and no toast environment
key exists. Each modifier accepts either a concrete style or an `Any…Style`
value, and the nearest modifier wins, including a modifier on a single
descendant of a styled container. Style authoring uses an ordinary
`import SwiftTUIViews`; only fixture construction opts into the testing SPI.
The remaining styleable surfaces, and the order they gain families, are
recorded in <doc:Divergences-And-Gaps>.

## See Also

- <doc:Style-System>
- <doc:Styling-And-Theming>
- <doc:Testing-Styles>
