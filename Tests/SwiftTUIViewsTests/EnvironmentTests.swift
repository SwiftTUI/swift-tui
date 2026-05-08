import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private enum TestKey: EnvironmentKey {
  static let defaultValue: Int = 42
}

@MainActor
@Suite
struct EnvironmentTests {
  @Test("environment key returns default value when not set")
  func defaultEnvironmentValue() {
    let values = EnvironmentValues()
    #expect(values[TestKey.self] == 42)
  }

  @Test("environment key returns custom value when set")
  func customEnvironmentValue() {
    var values = EnvironmentValues()
    values[TestKey.self] = 99
    #expect(values[TestKey.self] == 99)
  }

  @Test("environment values are equatable")
  func environmentValuesEquatable() {
    let a = EnvironmentValues()
    let b = EnvironmentValues()
    #expect(a == b)
  }

  @Test("accessibilityReduceMotion defaults to false and can be overridden")
  func accessibilityReduceMotion() {
    var values = EnvironmentValues()

    #expect(!values.accessibilityReduceMotion)

    values.accessibilityReduceMotion = true
    #expect(values.accessibilityReduceMotion)
  }
}
