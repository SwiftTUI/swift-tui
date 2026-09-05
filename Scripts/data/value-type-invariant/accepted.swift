// Accepted shapes under the value-type authoring invariant (plan
// 2026-08-29-001). This file must typecheck CLEAN against the built modules;
// `Scripts/check_value_type_invariant.sh` fails the lane if it does not.
//
// It is a *downstream consumer's* file on purpose: it imports the public
// products only, so it also pins that the witness requirement stays
// satisfiable from outside the package.

import SwiftTUIRuntime
import SwiftTUIViews

struct AcceptedPaletteStyle: PaletteStyle {
  func makeBody(configuration: PaletteStyleConfiguration) -> some View { Text(configuration.title) }
}

struct AcceptedMenuStyle: MenuStyle {
  func makeBody(configuration: MenuStyleConfiguration) -> some View { configuration.label }
}

struct AcceptedControlGroupStyle: ControlGroupStyle {
  func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    configuration.content
  }
}

struct AcceptedSliderStyle: SliderStyle {
  func makeBody(configuration: SliderStyleConfiguration) -> some View { Text("test") }
}

struct AcceptedStepperStyle: StepperStyle {
  func makeBody(configuration: StepperStyleConfiguration) -> some View { Text("test") }
}

struct AcceptedToggleStyle: ToggleStyle {
  func makeBody(configuration: ToggleStyleConfiguration) -> some View { Text("test") }
}

struct AcceptedDisclosureGroupStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View { Text("test") }
}

struct AcceptedTextEditorStyle: TextEditorStyle {
  func makeBody(configuration: TextEditorStyleConfiguration) -> some View { Text("test") }
}

struct AcceptedProgressViewStyle: ProgressViewStyle {
  func makeBody(configuration: ProgressViewStyleConfiguration) -> some View { Text("test") }
}

struct AcceptedLabelStyle: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    configuration.title
  }
}

struct AcceptedLabeledContentStyle: LabeledContentStyle {
  func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    configuration.content
  }
}

struct AcceptedGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    configuration.content
  }
}

// A plain struct view.
struct AcceptedStruct: View {
  var body: some View { Text("ok") }
}

// An enum view — enums stay allowed (OpenSwiftUI parity).
enum AcceptedEnum: View {
  case only

  var body: some View { Text("ok") }
}

// A generic struct view.
struct AcceptedGeneric<Payload>: View {
  let payload: Payload

  var body: some View { Text("ok") }
}

// A DOWNSTREAM conditional conformance — the shape spike A′ (a shared marker
// protocol) broke. It must keep working.
struct AcceptedConditional<Wrapped> {
  let wrapped: Wrapped
}

extension AcceptedConditional: View where Wrapped: View {
  var body: some View { wrapped }
}

// Class-typed FIELDS stay unrestricted: only the container is constrained.
final class AcceptedModel {
  var count = 0
}

struct AcceptedHoldingAClass: View {
  let model = AcceptedModel()
  let log: @MainActor () -> Void = {}

  var body: some View { Text("ok") }
}

// A struct view holding state, the shape the bind pass copies per mount.
struct AcceptedStateful: View {
  @State private var value = "seed"

  var body: some View { Text(value) }
}

// Existentials still work.
@MainActor
func acceptsExistential(_ view: any View) -> any View { view }

// The remaining authoring protocols, as value types.
struct AcceptedModifier: ViewModifier {
  func body(content: Content) -> some View { content }
}

struct AcceptedProperty: DynamicProperty {
  var stored = 0
}

struct AcceptedButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}

struct AcceptedPickerStyle: PickerStyle {
  func makeBody(configuration: PickerStyleConfiguration) -> some View {
    Text("ok")
  }
}

struct AcceptedTextFieldStyle: TextFieldStyle {
  func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
    Text("ok")
  }
}

struct AcceptedTabViewStyle: TabViewStyle {
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    TabViewStylePresentation(
      stripHeight: 1,
      visibleOptionIndices: [],
      overflowMenu: nil
    )
  }

  func makeBody(configuration: TabViewStyleBodyConfiguration) -> some View {
    Text("ok")
  }
}

struct AcceptedScene: Scene {
  var body: some Scene {
    WindowGroup { Text("ok") }
  }
}

struct AcceptedApp: App {
  var body: some Scene {
    WindowGroup { Text("ok") }
  }
}
