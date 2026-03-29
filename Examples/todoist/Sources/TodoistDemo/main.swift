import TerminalUI
import TerminalUIScenes

struct TodoistDemoApp: App {
  private let model: TodoistAppModel?
  private let launchError: String?

  init() {
    do {
      model = try TodoistAppModel.live()
      launchError = nil
    } catch {
      model = nil
      launchError = error.localizedDescription
    }
  }

  var body: some Scene {
    WindowGroup("Todoist Demo") {
      if let model {
        TodoistDemoRootView(model: model)
      } else {
        TodoistLaunchErrorView(
          message: launchError ?? "Unknown launch error"
        )
      }
    }
  }
}

let app = await MainActor.run { TodoistDemoApp() }
try await MultiSceneLauncher.run(app)
