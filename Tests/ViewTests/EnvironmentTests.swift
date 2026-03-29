import Testing

@testable import Core
@testable import View

private enum TestKey: EnvironmentKey {
  static let defaultValue: Int = 42
}

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
}
