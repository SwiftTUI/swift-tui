#if !os(Windows)
  import SwiftTUIRuntime
  import Testing

  @testable import SwiftTUICLIAttach
  @testable import SwiftTUITerminalCLI

  @Suite
  @MainActor
  struct TerminalRunnerRoutingTests {
    private struct CollidingSceneApp: App {
      var body: some Scene {
        WindowGroup("Duplicate", id: WindowIdentifier("duplicate")) { EmptyView() }
        WindowGroup("Duplicate", id: WindowIdentifier("duplicate")) { EmptyView() }
      }
    }

    @Test("Instance discovery does not validate the local app's scene identifiers")
    func instancesWithCollidingScenes() async throws {
      try await TerminalRunner.launch(
        CollidingSceneApp(), configuration: .default, arguments: ["app", "instances"])
    }

    @Test(
      "Remote scene verbs reach instance discovery despite local scene collisions",
      arguments: [["app", "scenes"], ["app", "attach", "duplicate"]])
    func remoteVerbsWithCollidingScenes(arguments: [String]) async {
      await #expect {
        try await TerminalRunner.launch(
          CollidingSceneApp(), configuration: .default, arguments: arguments)
      } throws: { error in
        guard let error = error as? SocketClientError else { return false }
        if case .noRunningInstances = error { return true }
        return false
      }
    }

    @Test("Launching an app still rejects colliding scene identifiers")
    func launchRejectsCollidingScenes() async {
      await #expect(throws: AppLaunchError.duplicateSceneIdentifier(WindowIdentifier("duplicate")))
      {
        try await TerminalRunner.launch(
          CollidingSceneApp(), configuration: .default, arguments: ["app"])
      }
    }
  }
#endif
