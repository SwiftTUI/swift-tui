import Core
import TerminalUI
import Testing
import View

@testable import TerminalUIScenes

@MainActor
struct MultiSceneLauncherTests {
  @Test("Extracts multiple scene configurations from App body")
  func extractsMultipleConfigurations() {
    struct TwoSceneApp: App {
      var body: some Scene {
        WindowGroup("Dashboard", id: WindowIdentifier("dashboard")) {
          Text("A")
        }
        WindowGroup("Controls", id: WindowIdentifier("controls")) {
          Text("B")
        }
      }
    }

    let app = TwoSceneApp()
    let configs = collectWindowSceneConfigurations(from: app.body)
    #expect(configs.count == 2)
    #expect(configs[0].identifier == WindowIdentifier("dashboard"))
    #expect(configs[0].title == "Dashboard")
    #expect(configs[1].identifier == WindowIdentifier("controls"))
    #expect(configs[1].title == "Controls")
  }

  @Test("Single scene falls through without error")
  func singleSceneNoError() {
    struct SingleSceneApp: App {
      var body: some Scene {
        WindowGroup("Main") {
          Text("Hello")
        }
      }
    }

    let app = SingleSceneApp()
    let configs = collectWindowSceneConfigurations(from: app.body)
    #expect(configs.count == 1)
  }

  @Test("Scene identities are distinct")
  func sceneIdentitiesDistinct() {
    struct TwoSceneApp: App {
      var body: some Scene {
        WindowGroup("Alpha", id: WindowIdentifier("alpha")) {
          Text("A")
        }
        WindowGroup("Beta", id: WindowIdentifier("beta")) {
          Text("B")
        }
      }
    }

    let app = TwoSceneApp()
    let configs = collectWindowSceneConfigurations(from: app.body)
    #expect(configs[0].rootIdentity != configs[1].rootIdentity)
  }
}
