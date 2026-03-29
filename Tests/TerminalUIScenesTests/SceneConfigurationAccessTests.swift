import TerminalUI
import Testing

@testable import TerminalUIScenes

@MainActor
struct SceneConfigurationAccessTests {
  @Test("collectWindowSceneConfigurations extracts multiple scenes")
  func collectsMultipleScenes() {
    let group = SceneGroup(scenes: [
      AnyScene(WindowGroup("Alpha", id: "alpha") { EmptyView() }),
      AnyScene(WindowGroup("Beta", id: "beta") { EmptyView() }),
    ])
    let configs = collectWindowSceneConfigurations(from: group)
    #expect(configs.count == 2)
    #expect(configs[0].identifier == "alpha")
    #expect(configs[1].identifier == "beta")
  }
}
