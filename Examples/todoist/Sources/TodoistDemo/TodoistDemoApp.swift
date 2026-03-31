import TerminalUI
import TerminalUIScenes

@main
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
