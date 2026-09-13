import SwiftTUIViews

// Documentation-hidden modifier names remain source-compatible public types.
func consumerModifierTypes(
  _: ToastModifier<Text>.Type,
  _: BuiltinPromptPresentationModifier<EmptyView, EmptyView>.Type,
  _: BuiltinSheetPresentationModifier<Text>.Type,
  _: BuiltinPaletteSheetPresentationModifier.Type
) {}

// This file is also typechecked outside the package to certify ordinary public
// authoring without @testable, SPI, or package access.
struct ConsumerRoundedEditorStyle: TextEditorStyle {
  func makeBody(configuration: TextEditorStyleConfiguration) -> some View {
    let content = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: false)
    let focus = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive)
    configuration.editorContent
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(content.backgroundStyle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(
          focus.borderStyle, style: configuration.focusActive ? .heavy : .init())
      }
      .minimumIntrinsicSize(height: 3)
  }
}

struct ConsumerExpandingSliderStyle: SliderStyle {
  func makeBody(configuration: SliderStyleConfiguration) -> some View {
    configuration.track {
      Rectangle().fill(.foreground).frame(maxWidth: .infinity).frame(height: 1)
    }
  }
}

struct ConsumerPickerHintsStyle: PickerStyle {
  func makeBody(configuration: PickerStyleConfiguration) -> some View {
    Text("hints=\(configuration.viewportLineCount ?? -1),\(configuration.lineWidth ?? -1)")
  }
}

struct ConsumerPickerOptions: View {
  var body: some View {
    Picker("Mode", selection: .constant(1)) {
      PickerOption("One", value: 1)
      PickerOption("Two", value: 2)
    }.pickerViewportLineCount(5).pickerLineWidth(12)
  }
}

struct ConsumerToastFactories: View {
  var body: some View {
    Text("Base")
      .toast("Info", isPresented: .constant(false), style: .info)
      .toast("Success", isPresented: .constant(false), style: .success)
      .toast("Warning", isPresented: .constant(false), style: .warning)
      .toast("Danger", isPresented: .constant(false), style: .danger)
      .toast(isPresented: .constant(false), style: .info) { Text("Info") }
      .toast(isPresented: .constant(false), style: .success) { Text("Success") }
      .toast(isPresented: .constant(false), style: .warning) { Text("Warning") }
      .toast(isPresented: .constant(false), style: .danger) { Text("Danger") }
  }
}
