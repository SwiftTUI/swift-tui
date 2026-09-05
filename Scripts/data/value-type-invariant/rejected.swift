// Rejected shapes under the value-type authoring invariant (plan
// 2026-08-29-001). Every declaration here MUST fail to compile with the
// protocol's own unavailable-witness diagnostic;
// `Scripts/check_value_type_invariant.sh` asserts one such diagnostic per
// authoring protocol and fails the lane if any goes missing — a silent loss
// of enforcement (a toolchain that stops treating an unavailable witness as
// an error) shows up as a red lane instead of as nothing at all.
//
// This file is never compiled by SwiftPM: it lives under Scripts/data/ and is
// typechecked out of tree against the built modules.

import SwiftTUIRuntime
import SwiftTUIViews

final class RejectedSliderStyle: SliderStyle {
  func makeBody(configuration: SliderStyleConfiguration) -> some View { Text("test") }
}

final class RejectedStepperStyle: StepperStyle {
  func makeBody(configuration: StepperStyleConfiguration) -> some View { Text("test") }
}

final class RejectedToggleStyle: ToggleStyle {
  func makeBody(configuration: ToggleStyleConfiguration) -> some View { Text("test") }
}

final class RejectedDisclosureGroupStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View { Text("test") }
}

final class RejectedTextEditorStyle: TextEditorStyle {
  func makeBody(configuration: TextEditorStyleConfiguration) -> some View { Text("test") }
}

final class RejectedProgressViewStyle: ProgressViewStyle {
  func makeBody(configuration: ProgressViewStyleConfiguration) -> some View { Text("test") }
}

final class RejectedLabelStyle: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    configuration.title
  }
}

final class RejectedLabeledContentStyle: LabeledContentStyle {
  func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    configuration.content
  }
}

final class RejectedMenuStyle: MenuStyle {
  func makeBody(configuration: MenuStyleConfiguration) -> some View { configuration.label }
}

final class RejectedPaletteStyle: PaletteStyle {
  func makeBody(configuration: PaletteStyleConfiguration) -> some View { Text(configuration.title) }
}

final class RejectedControlGroupStyle: ControlGroupStyle {
  func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    configuration.content
  }
}

final class RejectedGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    configuration.content
  }
}

@MainActor
final class RejectedView: View {
  var body: some View { Text("no") }
}

// A retroactive conformance is rejected on the same terms.
@MainActor
final class RejectedRetroactively {}

extension RejectedRetroactively: View {
  var body: some View { Text("no") }
}

// So is a generic class.
@MainActor
final class RejectedGenericView<Payload>: View {
  var body: some View { Text("no") }
}

@MainActor
final class RejectedModifier: ViewModifier {
  func body(content: Content) -> some View { content }
}

@MainActor
final class RejectedProperty: DynamicProperty {
  var stored = 0
}

final class RejectedButtonStyle: ButtonStyle, @unchecked Sendable {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}

final class RejectedPickerStyle: PickerStyle, @unchecked Sendable {
  func makeBody(configuration: PickerStyleConfiguration) -> some View {
    Text("no")
  }
}

final class RejectedTextFieldStyle: TextFieldStyle, @unchecked Sendable {
  func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
    Text("no")
  }
}

final class RejectedTabViewStyle: TabViewStyle, @unchecked Sendable {
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
    Text("no")
  }
}

@MainActor
final class RejectedScene: Scene {
  var body: some Scene {
    WindowGroup { Text("no") }
  }
}

@MainActor
final class RejectedApp: App {
  nonisolated init() {}

  var body: some Scene {
    WindowGroup { Text("no") }
  }
}
