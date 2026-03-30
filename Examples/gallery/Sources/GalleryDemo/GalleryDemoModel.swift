import Observation

@Observable
final class GalleryDemoModel: @unchecked Sendable {
  var primaryCount = 0
  var toggleEnabled = true
  var stepperValue = 2
  var sliderValue = 7
  var searchText = "release notes"
  var secretText = "swordfish"
  var pickerSelection = "inline"
  var listSelection = "beta"
  var tableSelection = "latency"

  func reset() {
    primaryCount = 0
    toggleEnabled = true
    stepperValue = 2
    sliderValue = 7
    searchText = "release notes"
    secretText = "swordfish"
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
