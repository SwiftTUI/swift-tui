import Observation

@MainActor
@Observable
public final class GalleryDemoModel {
  public var activeTab = "controls"
  public var isPalettePresented = false
  public var selectedControlDemo = "buttons"
  public var selectedCollectionDemo = "picker"
  public var selectedLayoutDemo = "containers"
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
  public var pickerOptionSelection = "one"
  public var listSelection = "beta"
  public var tableSelection = "latency"
  public var isActionDisclosureExpanded = true
  public var lastOpenedLink = "none"
  public var sectionListSelection = "terminal"
  public var navigationSidebarSelection = "examples"
  public var navigationContentSelection = "gallery"

  public init() {}

  public func reset() {
    activeTab = "controls"
    isPalettePresented = false
    selectedControlDemo = "buttons"
    selectedCollectionDemo = "picker"
    selectedLayoutDemo = "containers"
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
    pickerOptionSelection = "one"
    listSelection = "beta"
    tableSelection = "latency"
    isActionDisclosureExpanded = true
    lastOpenedLink = "none"
    sectionListSelection = "terminal"
    navigationSidebarSelection = "examples"
    navigationContentSelection = "gallery"
  }

  public func increment() {
    primaryCount += 1
  }

  public func advance() {
    stepperValue += 1
    sliderValue = min(10, sliderValue + 1)
  }
}
