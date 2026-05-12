import SwiftTUI
import Testing

@testable import SwiftUIHost

private struct MultiSceneApp: SwiftTUIRuntime.App {
  init() {}

  var body: some Scene {
    WindowGroup("Dashboard", id: "dashboard") {
      Text("Dashboard")
    }

    WindowGroup("Controls", id: "controls") {
      Text("Controls")
    }
  }
}

@MainActor
@Test
func scene_hosts_are_retained_while_switching_scenes() throws {
  let state = try SwiftUIHostAppState(app: MultiSceneApp())
  let dashboardHost = try #require(state.sceneHost(for: "dashboard"))
  let controlsHost = try #require(state.sceneHost(for: "controls"))

  #expect(state.scenes.map(\.id) == ["dashboard", "controls"])
  #expect(state.selectedSceneID == "dashboard")

  state.selectScene("controls")
  #expect(state.selectedSceneID == "controls")

  state.selectScene("dashboard")
  #expect(state.selectedSceneID == "dashboard")
  #expect(state.sceneHost(for: "dashboard") === dashboardHost)
  #expect(state.sceneHost(for: "controls") === controlsHost)
}
