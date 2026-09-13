import Testing

@testable import SwiftTUIViews

@MainActor
@Suite("Style environment defaults")
struct StyleEnvironmentDefaultsTests {
  @Test("all 27 style slots retain their documented default labels")
  func defaults() {
    let environment = EnvironmentValues()
    let labels: [(String, String)] = [
      (environment.buttonStyle.description, "AnyButtonStyle.automatic"),
      (environment.toggleStyle.description, "AnyToggleStyle.automatic"),
      (environment.disclosureGroupStyle.description, "AnyDisclosureGroupStyle.automatic"),
      (environment.textEditorStyle.description, "AnyTextEditorStyle.automatic"),
      (environment.progressViewStyle.description, "AnyProgressViewStyle.automatic"),
      (environment.labelStyle.description, "AnyLabelStyle.automatic"),
      (environment.labeledContentStyle.description, "AnyLabeledContentStyle.automatic"),
      (environment.controlGroupStyle.description, "AnyControlGroupStyle.automatic"),
      (environment.menuStyle.description, "AnyMenuStyle.automatic"),
      (environment.paletteStyle.description, "AnyPaletteStyle.automatic"),
      (environment.groupBoxStyle.description, "AnyGroupBoxStyle.automatic"),
      (environment.textFieldStyle.description, "AnyTextFieldStyle.automatic"),
      (environment.pickerStyle.description, "AnyPickerStyle.automatic"),
      (environment.sliderStyle.description, "AnySliderStyle.automatic"),
      (environment.stepperStyle.description, "AnyStepperStyle.automatic"),
      (environment.tabViewStyle.description, "AnyTabViewStyle.automatic"),
      (environment.linkStyle.description, "LinkStyle.automatic"),
      (environment.scrollViewStyle.description, "ScrollViewStyle.automatic"),
      (environment.listStyle.description, "ListStyle.automatic"),
      (environment.tableStyle.description, "TableStyle.automatic"),
      (environment.outlineStyle.description, "OutlineStyle.automatic"),
      (environment.promptStyle.description, "PromptStyle.automatic"),
      (environment.fullScreenCoverStyle.description, "FullScreenCoverStyle.automatic"),
      (environment.popoverStyle.description, "PopoverStyle.automatic"),
      (environment.toolbarStyle.snapshotLabel, "ToolbarStyle.defaultTop"),
      (environment.spinnerStyle.description, "SpinnerStyle.automatic"),
      (environment.sheetStyle.description, "SheetStyle.surface"),
    ]
    #expect(labels.count == 27)
    for (actual, expected) in labels {
      #expect(actual == expected)
    }
  }
}
