import SwiftTUI
import Testing

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

  @Test("TerminalRunner rejects web mode when WebHost is not linked")
  func rejectsWebModeWhenWebHostNotLinked() async {
    do {
      try await TerminalRunner.run(NeverApp(), configuration: .init(web: .init()))
      Issue.record("Expected TerminalRunner to reject web mode.")
    } catch let error as TerminalRunnerError {
      let expected =
        "--web requires the opt-in WebHost runner, but this executable was built with "
        + "terminal-only SwiftTUICLI. Link the SwiftTUI" + "WebHostCLI product and call "
        + "WebHostCLIRunner.run(...), or remove --web."
      #expect(error == .webHostNotLinked)
      #expect(error.description == expected)
    } catch {
      Issue.record("Expected TerminalRunnerError.webHostNotLinked, got \(error).")
    }
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
