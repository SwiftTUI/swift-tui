@_spi(Runners) import TerminalUI
import Testing

@MainActor
struct SceneConfigurationAccessTests {
  @Test("collectWindowSceneDescriptors extracts multiple scenes")
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
    let descriptors = collectWindowSceneDescriptors(from: TwoSceneApp().body)
    #expect(descriptors.count == 2)
    #expect(descriptors[0].id == WindowIdentifier("alpha"))
    #expect(descriptors[1].id == WindowIdentifier("beta"))
  }
}
