import Testing
import SwiftTUI
@testable import SwiftTUICLI

struct TerminalRunnerConfigurationTests {
  @Test("TerminalRunner.run(_:configuration:) overload exists and accepts RuntimeConfiguration")
  func acceptsConfiguration() async {
    // Reference the overload via its metatype. Compile-time anchor only;
    // never executed.
    if false {
      let app = NeverApp()
      try? await TerminalRunner.run(app, configuration: .default)
      try? await TerminalRunner.run(NeverApp.self, configuration: .default)
    }
    _ = RuntimeConfiguration.default
  }
}

@MainActor
private struct NeverApp: App {
  var body: some Scene {
    // Tests never construct or run this app; the references inside `if false`
    // exist purely to make the overload's signature a compile-time anchor.
    WindowGroup { EmptyView() }
  }
}
