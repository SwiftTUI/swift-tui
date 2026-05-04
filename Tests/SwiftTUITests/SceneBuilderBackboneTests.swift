import Testing
import SwiftTUIViews

@_spi(Runners) @testable import SwiftTUI

@MainActor
@Suite
struct SceneBuilderBackboneTests {
  @Test("SceneBuilder preserves authored order across multiple scenes")
  func sceneBuilderPreservesAuthoredOrderAcrossMultipleScenes() {
    struct OrderedApp: App {
      var body: some Scene {
        WindowGroup("First") {
          Text("One")
        }
        WindowGroup("Second") {
          Text("Two")
        }
        WindowGroup("Third") {
          Text("Three")
        }
      }
    }

    let descriptors = collectWindowSceneDescriptors(from: OrderedApp().body)
    #expect(
      descriptors.map(\.id)
        == [
          WindowIdentifier("First"),
          WindowIdentifier("Second"),
          WindowIdentifier("Third"),
        ]
    )
  }

  @Test("ConditionalScene preserves the active branch")
  func conditionalScenePreservesActiveBranch() {
    @SceneBuilder
    func makeScene(
      _ flag: Bool
    ) -> some Scene {
      if flag {
        WindowGroup("True Branch") {
          Text("True")
        }
      } else {
        WindowGroup("False Branch") {
          Text("False")
        }
      }
    }

    #expect(
      collectWindowSceneDescriptors(from: makeScene(true)).map(\.id)
        == [WindowIdentifier("True-Branch")]
    )
    #expect(
      collectWindowSceneDescriptors(from: makeScene(false)).map(\.id)
        == [WindowIdentifier("False-Branch")]
    )
  }

  @Test("EmptyScene collapses implicit empty false branches")
  func emptySceneCollapsesImplicitFalseBranches() {
    @SceneBuilder
    func makeScene(
      _ includeWindow: Bool
    ) -> some Scene {
      if includeWindow {
        WindowGroup("Only Window") {
          Text("One")
        }
      }
    }

    #expect(collectWindowSceneDescriptors(from: makeScene(false)).isEmpty)
    #expect(
      collectWindowSceneDescriptors(from: makeScene(true)).map(\.id)
        == [WindowIdentifier("Only-Window")]
    )
  }

  @Test("VariadicScene preserves order across array-built scenes")
  func variadicScenePreservesArrayOrder() {
    let scene = SceneBuilder.buildArray(
      [
        WindowGroup("Alpha") {
          Text("A")
        },
        WindowGroup("Beta") {
          Text("B")
        },
      ]
    )

    let descriptors = collectWindowSceneDescriptors(from: scene)
    #expect(descriptors.map(\.id) == [WindowIdentifier("Alpha"), WindowIdentifier("Beta")])
  }

  @Test("SceneBuilder buildLimitedAvailability routes through AnyScene")
  func buildLimitedAvailabilityRoutesThroughAnyScene() {
    let scene: AnyScene = SceneBuilder.buildLimitedAvailability(
      WindowGroup("Available") {
        Text("Value")
      }
    )

    let descriptors = collectWindowSceneDescriptors(from: scene)
    #expect(descriptors.map(\.id) == [WindowIdentifier("Available")])
  }
}
