import Observation

@Observable
public final class GalleryDemoModel: @unchecked Sendable {
  public var activeTab = "controls"
  public var isPalettePresented = false
  public var selectedControlDemo = "buttons"
  public var selectedCollectionDemo = "picker"
  public var selectedAppearanceDemo = "tokens"
  public var selectedChartDemo = "progress"
  public var primaryCount = 0
  public var toggleEnabled = true
  public var stepperValue = 2
  public var sliderValue = 7
  public var searchText = "release notes"
  public var secretText = "swordfish"
  public var editorText = """
    Dense defaults
    should feel native
    to the terminal.
    """
  public var pickerSelection = "inline"
  public var listSelection = "beta"
  public var tableSelection = "latency"

  public init() {}

  public func reset() {
    activeTab = "controls"
    isPalettePresented = false
    selectedControlDemo = "buttons"
    selectedCollectionDemo = "picker"
    selectedAppearanceDemo = "tokens"
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

  public func increment() {
    primaryCount += 1
  }

  public func advance() {
    stepperValue += 1
    sliderValue = min(10, sliderValue + 1)
  }
}
