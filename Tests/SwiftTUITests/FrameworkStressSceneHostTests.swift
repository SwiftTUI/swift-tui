@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI scene and host stress behavior", .serialized)
struct FrameworkStressSceneHostTests {}

// MARK: - Attempt 001: default scene through builder churn

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 001 nested builder churn keeps the first live window default")
  func sceneHost001NestedBuilderChurnKeepsFirstLiveWindowDefault() {
    // Hypothesis: the traversal default marker can be consumed by an empty
    // optional or conditional branch before the first live WindowGroup appears.
    for generation in 0..<24 {
      let descriptors = collectWindowSceneDescriptors(
        from: sceneHost001Scene(generation: generation)
      )
      let expectedFirstID =
        generation.isMultiple(of: 3)
        ? WindowIdentifier("loop-0")
        : WindowIdentifier("conditional-\(generation % 2)")

      #expect(descriptors.count == (generation.isMultiple(of: 3) ? 2 : 3))
      #expect(descriptors.first?.id == expectedFirstID)
      #expect(
        descriptors.map(\.isDefault) == [true]
          + Array(repeating: false, count: descriptors.count - 1))
    }
  }
}

@MainActor
@SceneBuilder
private func sceneHost001Scene(generation: Int) -> some Scene {
  if !generation.isMultiple(of: 3) {
    if generation.isMultiple(of: 2) {
      WindowGroup("Conditional Even", id: "conditional-0") {
        Text("even")
      }
    } else {
      WindowGroup("Conditional Odd", id: "conditional-1") {
        Text("odd")
      }
    }
  }

  for index in 0..<2 {
    WindowGroup("Loop \(index)", id: WindowIdentifier("loop-\(index)")) {
      Text("loop \(index)")
    }
  }
}
