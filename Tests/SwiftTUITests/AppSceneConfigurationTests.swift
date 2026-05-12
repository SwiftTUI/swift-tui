import SwiftTUICore
@_spi(Runners) import SwiftTUIRuntime
import Testing
import SwiftTUIViews

@MainActor
struct AppSceneConfigurationTests {
  @Test("Extracts multiple scene descriptors from App body")
  func extractsMultipleDescriptors() {
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
    let descriptors = collectWindowSceneDescriptors(from: app.body)
    #expect(descriptors.count == 2)
    #expect(descriptors[0].id == WindowIdentifier("dashboard"))
    #expect(descriptors[0].title == "Dashboard")
    #expect(descriptors[1].id == WindowIdentifier("controls"))
    #expect(descriptors[1].title == "Controls")
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
    let descriptors = collectWindowSceneDescriptors(from: app.body)
    #expect(descriptors.count == 1)
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

    var visitor = RootIdentityCollector()
    _ = traverseWindowScenes(
      TwoSceneApp().body,
      visitor: &visitor
    )
    #expect(visitor.rootIdentities.count == 2)
    #expect(visitor.rootIdentities[0] != visitor.rootIdentities[1])
  }
}

@MainActor
private struct RootIdentityCollector: WindowSceneVisitor {
  var rootIdentities: [Identity] = []

  mutating func visit<Content: View>(
    _ scene: WindowGroup<Content>,
    isDefault _: Bool
  ) -> SceneTraversalControl {
    rootIdentities.append(
      scene.windowSceneConfiguration().rootIdentity
    )
    return .continue
  }
}
