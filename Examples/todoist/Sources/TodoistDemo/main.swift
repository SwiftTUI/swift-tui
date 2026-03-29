import TerminalUI
import TerminalUIScenes

struct TodoistDemoApp: App {
  private let launcher: TodoistDemoLauncher?
  private let launchError: String?

  init() {
    do {
      launcher = try TodoistDemoLauncher()
      launchError = nil
    } catch {
      launcher = nil
      launchError = error.localizedDescription
    }
  }

  var body: some Scene {
    WindowGroup("Todoist Demo") {
      if let launcher {
        TodoistDemoSceneView(launcher: launcher)
      } else {
        TodoistLaunchErrorView(
          message: launchError ?? "Unknown launch error"
        )
      }
    }
  }
}

// SwiftUI-style app authoring is main-actor isolated, so construct the app there.
let app = await MainActor.run { TodoistDemoApp() }
try await MultiSceneLauncher.run(app)
