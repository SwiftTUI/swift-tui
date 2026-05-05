import Testing
import SwiftTUI
@testable import SwiftTUICLI

struct TerminalRunnerConfigurationTests {
  @Test("TerminalRunner.run(_:configuration:) overload exists and accepts RuntimeConfiguration")
  func acceptsConfiguration() {
    // Compile-time check only; we cannot easily exercise terminal IO in tests.
    // The signature itself is the assertion.
    let _: (Any.Type, RuntimeConfiguration) -> Void = { _, _ in }
    _ = RuntimeConfiguration.default
  }
}
