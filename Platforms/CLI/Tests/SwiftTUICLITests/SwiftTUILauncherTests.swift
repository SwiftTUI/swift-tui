import SwiftTUIRuntime
import Synchronization
import Testing

@testable import SwiftTUITerminalCLI

/// Serialized: the launch registry is process-global by design (one launch
/// per process), so these tests install/clear it without racing each other.
@Suite(.serialized)
@MainActor
struct SwiftTUILauncherTests {
  @Test("web configuration without an installed web runner is rejected clearly")
  func webConfigurationWithoutRunnerIsRejected() async {
    SwiftTUILaunchRegistry.resetWebRunnerForTesting()
    defer { SwiftTUILaunchRegistry.resetWebRunnerForTesting() }

    do {
      try await SwiftTUILauncher.run(LauncherProbeApp(), configuration: .init(web: .init()))
      Issue.record("Expected the launcher to reject --web with no web runner installed.")
    } catch let error as TerminalRunnerError {
      #expect(error == .webHostNotLinked)
    } catch {
      Issue.record("Expected TerminalRunnerError.webHostNotLinked, got \(error).")
    }
  }

  @Test("web configuration routes through the installed web runner")
  func webConfigurationRoutesThroughInstalledRunner() async throws {
    SwiftTUILaunchRegistry.resetWebRunnerForTesting()
    defer { SwiftTUILaunchRegistry.resetWebRunnerForTesting() }

    let routed = Mutex<Bool>(false)
    SwiftTUILaunchRegistry.installWebRunner { _, configuration in
      #expect(configuration.web != nil)
      routed.withLock { $0 = true }
    }

    try await SwiftTUILauncher.run(LauncherProbeApp(), configuration: .init(web: .init()))
    #expect(routed.withLock { $0 })
  }
}

@MainActor
private struct LauncherProbeApp: App {
  var body: some Scene {
    WindowGroup { EmptyView() }
  }
}
