import Observation

@Observable
final class GalleryDemoModel: @unchecked Sendable {
  var activeTab = "controls"
  var isPalettePresented = false
  var paletteQuery = ""
  var selectedControlDemo = "buttons"
  var selectedCollectionDemo = "picker"
  var selectedAppearanceDemo = "light"
  var selectedChartDemo = "progress"
  var primaryCount = 0
  var toggleEnabled = true
  var stepperValue = 2
  var sliderValue = 7
  var searchText = "release notes"
  var secretText = "swordfish"
  var editorText = """
    Dense defaults
    should feel native
    to the terminal.
    """
  var pickerSelection = "inline"
  var listSelection = "beta"
  var tableSelection = "latency"

  func reset() {
    activeTab = "controls"
    isPalettePresented = false
    paletteQuery = ""
    selectedControlDemo = "buttons"
    selectedCollectionDemo = "picker"
    selectedAppearanceDemo = "light"
    selectedChartDemo = "progress"
    primaryCount = 0
    toggleEnabled = true
    stepperValue = 2
    sliderValue = 7
    searchText = "release notes"
    secretText = "swordfish"
    editorText = """
      Dense defaults
      should feel native
      to the terminal.
      """
    pickerSelection = "inline"
    listSelection = "beta"
    tableSelection = "latency"
  }

  func increment() {
    primaryCount += 1
  }

  func advance() {
    stepperValue += 1
    sliderValue = min(10, sliderValue + 1)
  }
}
