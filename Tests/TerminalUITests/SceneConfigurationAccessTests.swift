@_spi(Runners) import TerminalUI
import Testing

@MainActor
struct SceneConfigurationAccessTests {
  @Test("collectWindowSceneConfigurations extracts multiple scenes")
  func collectsMultipleScenes() {
    struct TwoSceneApp: App {
      var body: some Scene {
        WindowGroup("Alpha", id: WindowIdentifier("alpha")) {
          EmptyView()
        }
        WindowGroup("Beta", id: WindowIdentifier("beta")) {
          EmptyView()
        }
      }
    }
    let configs = collectWindowSceneConfigurations(from: TwoSceneApp().body)
    #expect(configs.count == 2)
    #expect(configs[0].identifier == WindowIdentifier("alpha"))
    #expect(configs[1].identifier == WindowIdentifier("beta"))
  }
}
