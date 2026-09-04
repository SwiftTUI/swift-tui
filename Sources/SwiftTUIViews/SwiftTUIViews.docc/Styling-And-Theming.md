# Styling and Theming

Color views with `Color`, semantic roles, and gradients; apply built-in
control styles; and write your own styles against the open style protocols.

## Overview

Styling in SwiftTUI composes in three layers. Concrete `ShapeStyle` values —
`Color`, `LinearGradient`, `RadialGradient`, `MeshGradient` — color content
directly through modifiers such as `.foregroundStyle(_:)`, `.background(_:)`,
`.tint(_:)`, and `.border(_:set:placement:sides:)`. Semantic roles
(`.primary`, `.tint`, `.success`, …) are shape styles too, but resolve at
render time through the active `Theme`, so the same view adapts to light,
dark, and high-contrast terminals. Above both sit the control style
families: `ButtonStyle`, `TextFieldStyle`, `PickerStyle`, and their peers are
public, extensible protocols — including families SwiftUI keeps closed — so
an app can restyle whole control categories, not just individual views. For
the view-composition basics these examples build on, see
<doc:Authoring-Views>.

## Colors, foregrounds, and backgrounds

`Color` offers named values (`.red`, `.cyan`, `.gray`, `.white`, `.clear`, …)
plus hex and component initializers, and derived values via `opacity(_:)`:

```swift
struct Banner: View {
  static let plum = try! Color.hex("#B48EAD")

  var body: some View {
    Text(" SwiftTUI ")
      .foregroundStyle(.white)
      .background(Self.plum)
      .border(Self.plum.opacity(0.5), set: .rounded)
  }
}
```

Any `ShapeStyle` fits these modifier slots, so everything below — semantic
roles and gradients included — drops into the same positions.

## Semantic roles resolve through the theme

Prefer semantic roles over hard-coded colors: they are the intended currency.
Each role is a case of `SemanticStyleRole` (`foreground`, `background`,
`tint`, `separator`, `selection`, `placeholder`, `link`, `fill`,
`windowBackground`, `success`, `warning`, `danger`, `info`, `muted`), exposed
as `ShapeStyle` statics, with `.primary` and `.secondary` as SwiftUI-style
aliases for `foreground` and `muted`:

```swift
VStack(alignment: .leading) {
  Text("Build succeeded").foregroundStyle(.success)
  Text("2 warnings").foregroundStyle(.warning)
  Text("hint: run tests").foregroundStyle(.muted)
  Text("main.swift").foregroundStyle(.link)
}
.background(.windowBackground)
```

## Gradients

Gradients are ordinary shape styles. `LinearGradient` interpolates colors
between two `UnitPoint`s; `MeshGradient` interpolates a grid of control
points and colors, and both animate under `withAnimation`:

```swift
Rectangle()
  .fill(
    LinearGradient(
      colors: [.blue, .cyan, .green],
      startPoint: .leading,
      endPoint: .trailing
    )
  )
  .frame(width: 24, height: 3)

Rectangle()
  .fill(
    MeshGradient(
      width: 3, height: 3,
      points: [
        .init(0, 0), .init(0.5, 0), .init(1, 0),
        .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
        .init(0, 1), .init(0.5, 1), .init(1, 1),
      ],
      colors: [
        .blue, .cyan, .green,
        .magenta, .white, .yellow,
        .red, .magenta, .blue,
      ],
      colorSpace: .perceptual
    )
  )
  .frame(width: 18, height: 6)
  .border(set: .rounded)
```

## Applying built-in control styles

Every style family has a lower-camel-cased modifier that stores a
type-erased style in the environment, so a style set on a container applies
to the whole subtree. Buttons ship with `.automatic`, `.plain`, `.bordered`,
`.borderedProminent`, and `.link`; text fields with `.automatic`, `.plain`,
and `.roundedBorder`; pickers with `.automatic`, `.inline`, `.menu`,
`.radioGroup`, and `.segmented`. Lists (`.automatic`, `.plain`,
`.insetGrouped`), tables, tab views, sheets, toolbars, outlines, and spinners
(dozens of presets on `AnySpinnerStyle`) follow the same pattern:

```swift
VStack(alignment: .leading, spacing: 1) {
  Button("Save") { save() }
    .buttonStyle(.borderedProminent)
  Button("Preview") { preview() }
    .buttonStyle(.bordered)
  Button("Docs") { openDocs() }
    .buttonStyle(.link)
  TextField("Name", text: $name)
    .textFieldStyle(.roundedBorder)
}
```

## Writing a custom button style

The style protocols are open: conform, implement
`makeBody(configuration:)`, and pass the conformance to the same modifier.
``ButtonStyleConfiguration`` hands you the authored label as a view plus the
render state a style legitimately needs — `role`, `isEnabled`, `isPressed`,
`focusActive`, and the resolved style environment, whose `theme` supplies
semantic colors:

```swift
struct RoleBadgeButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    let theme = configuration.styleEnvironment.theme
    let badge: String
    switch configuration.role {
    case .destructive: badge = "[!]"
    case .cancel: badge = "[x]"
    default: badge = configuration.focusActive ? "[>]" : "[ ]"
    }
    return HStack(spacing: 1) {
      Text(badge)
        .foregroundStyle(
          configuration.role == .destructive
            ? theme.color(for: .danger)
            : theme.color(for: .tint)
        )
      configuration.label
    }
  }
}

Button("Delete", role: .destructive) { delete() }
  .buttonStyle(RoleBadgeButtonStyle())
```

Styles must be `Sendable`; `makeBody(configuration:)` runs on the main
actor. Conformances can also override `resolvedProminence(base:)` to raise
control prominence the way `.borderedProminent` does. The other families
mirror this shape — a protocol, a public configuration, an `Any*Style`
eraser, and a scoping modifier. <doc:Authoring-Styles> covers the contract
in full, including the presentation-value families and the route wrappers
interactive configurations expose; <doc:Testing-Styles> shows how a style
library unit-tests its styles without a live render; and
<doc:Divergences-And-Gaps> records how far the styling contract currently
extends.

## Themes are host-selected

`Theme` is the public bundle of semantic token colors behind the roles
above: one `Color` per `SemanticStyleRole`, `Codable` for transport, with
`Theme.default` and `color(for:)` / `style(for:)` accessors:

```swift
let nord = Theme(
  foreground: try! .hex("#ECEFF4"),
  background: try! .hex("#2E3440"),
  tint: .cyan,
  danger: try! .hex("#BF616A")
)
```

Which theme is *active*, however, is the host's decision, not the view
tree's: the environment slot that carries the theme is internal, and there
is no public modifier or environment key that sets it from app views — do
not hunt for one. In a terminal app the runtime synthesizes a theme from the
detected terminal appearance; embedding hosts pass one explicitly (for
example `HostedRasterSurface(surfaceSize:appearance:theme:…)` in
`SwiftTUIRuntime`, or a `TerminalRenderStyle` payload over wrapper
transport). Views consume the active theme through semantic styles, and
custom styles read it through `configuration.styleEnvironment.theme`. To
override colors locally, use `.foregroundStyle(_:)`, `.tint(_:)`, and
`.background(_:)`; for an app-defined palette beyond the semantic roles,
carry your own value through a custom environment key.

## Terminal appearance and contrast

Two public environment values describe the surface the theme was derived
from. `\.terminalAppearance` is the detected `TerminalAppearance` —
foreground, background, and tint colors, the 16-color palette, and how the
values were determined. `\.colorSchemeContrast` is derived from it:
`.standard` or `.increased` when foreground and background are far enough
apart that high-contrast rendering is in effect:

```swift
struct StatusRule: View {
  @Environment(\.terminalAppearance) private var appearance
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    Text("ready")
      .foregroundStyle(
        contrast == .increased
          ? appearance.foregroundColor
          : Color.gray
      )
  }
}
```

Prefer semantic roles for everyday styling and reach for these values when a
view must react to contrast itself — for the wider assistive-rendering
story, see <doc:Accessibility>.
