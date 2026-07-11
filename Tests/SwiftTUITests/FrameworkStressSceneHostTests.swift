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

// MARK: - Attempt 002: erased scene order through empty prefixes

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 002 nested scene erasure preserves current descriptor order")
  func sceneHost002NestedSceneErasurePreservesCurrentDescriptorOrder() {
    // Hypothesis: nested AnyScene boxes can snapshot a variadic child's first
    // traversal and replay that order after empty-prefix and reversal churn.
    for generation in 0..<24 {
      let scene = AnyScene(AnyScene(sceneHost002Scene(generation: generation)))
      let descriptors = collectWindowSceneDescriptors(from: scene)
      let expected =
        generation.isMultiple(of: 2)
        ? ["alpha", "beta", "gamma"]
        : ["gamma", "beta", "alpha"]

      #expect(descriptors.map(\.id.rawValue) == expected)
      #expect(descriptors.map(\.isDefault) == [true, false, false])
    }
  }
}

@MainActor
@SceneBuilder
private func sceneHost002Scene(generation: Int) -> some Scene {
  if generation.isMultiple(of: 3) {
    ()
  }

  for id in generation.isMultiple(of: 2)
    ? ["alpha", "beta", "gamma"]
    : ["gamma", "beta", "alpha"]
  {
    AnyScene(
      WindowGroup(id: WindowIdentifier(id)) {
        Text(id)
      }
    )
  }
}

// MARK: - Attempt 003: duplicate scene identifier occurrence order

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 003 duplicate scene identifiers retain authored occurrences")
  func sceneHost003DuplicateSceneIdentifiersRetainAuthoredOccurrences() {
    // Hypothesis: selection collection can deduplicate WindowGroups by their
    // normalized identifier and silently retain only one current occurrence.
    for generation in 0..<24 {
      let scene = sceneHost003Scene(generation: generation)
      let descriptors = collectWindowSceneDescriptors(from: scene)
      let selections = collectWindowSceneSelections(from: scene)
      let expectedTitles =
        generation.isMultiple(of: 2)
        ? ["First", "Second", "Third"]
        : ["Third", "Second", "First"]

      #expect(descriptors.map(\.id.rawValue) == ["shared", "shared", "shared"])
      #expect(descriptors.map(\.title) == expectedTitles.map(Optional.some))
      #expect(selections.map(\.title) == expectedTitles.map(Optional.some))
      #expect(selections.map(\.isDefault) == [true, false, false])
    }
  }
}

@MainActor
@SceneBuilder
private func sceneHost003Scene(generation: Int) -> some Scene {
  if generation.isMultiple(of: 2) {
    WindowGroup("First", id: "shared") { Text("first") }
    WindowGroup("Second", id: "shared") { Text("second") }
    WindowGroup("Third", id: "shared") { Text("third") }
  } else {
    WindowGroup("Third", id: "shared") { Text("third") }
    WindowGroup("Second", id: "shared") { Text("second") }
    WindowGroup("First", id: "shared") { Text("first") }
  }
}

// MARK: - Attempt 004: retained scene content builder capture

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 004 repeated root construction preserves one authored capture")
  func sceneHost004RepeatedRootConstructionPreservesOneAuthoredCapture() {
    // Hypothesis: repeated host calls to makeScopedRootView can reexecute a
    // WindowGroup content closure and multiply its authoring-time side effects.
    let model = SceneHost004Model()
    let group = WindowGroup("Captured", id: "captured") {
      let build = model.nextBuild()
      Text("scene build \(build)")
    }
    let configuration = group.windowSceneConfiguration()
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))

    for current in 0..<24 {
      let frame = renderer.render(
        WindowHostView(content: configuration.makeScopedRootView()),
        context: .init(
          identity: configuration.rootIdentity,
          invalidatedIdentities: current == 0 ? [] : [configuration.rootIdentity]
        ),
        proposal: .init(width: 32, height: 4)
      )

      #expect(frame.rasterSurface.lines.joined(separator: "\n").contains("scene build 1"))
      #expect(model.buildCount == 1)
    }
  }
}

@MainActor
private final class SceneHost004Model {
  private(set) var buildCount = 0

  func nextBuild() -> Int {
    buildCount += 1
    return buildCount
  }
}

// MARK: - Attempt 005: selected scene exit-binding replacement

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 005 selected exit bindings never revive earlier keys")
  func sceneHost005SelectedExitBindingsNeverReviveEarlierKeys() throws {
    // Hypothesis: repeated scene traversal can select a stale pre-chain
    // WindowGroup copy whose earlier exit binding survived replacement.
    for generation in 0..<24 {
      let currentKeys = [
        KeyPress(.character("x"), modifiers: generation.isMultiple(of: 2) ? .ctrl : .shift),
        KeyPress(.escape),
      ]
      var visitor = SceneHostExitBindingsVisitor()
      let bindings = withWindowSceneConfiguration(
        in: sceneHost005Scene(generation: generation, currentKeys: currentKeys),
        matching: "target",
        visitor: &visitor
      )

      #expect(try #require(bindings).keys == currentKeys)
      #expect(bindings?.contains(KeyPress(.character("a"), modifiers: .ctrl)) == false)
      #expect(bindings?.contains(KeyPress(.character("d"), modifiers: .ctrl)) == false)
    }
  }
}

@MainActor
@SceneBuilder
private func sceneHost005Scene(generation: Int, currentKeys: [KeyPress]) -> some Scene {
  if generation.isMultiple(of: 2) {
    WindowGroup(id: "other") { Text("other") }
  }
  WindowGroup(id: "target") { Text("target") }
    .exitOnKey(.character("a"), modifiers: .ctrl)
    .exitOnKeys(currentKeys)
  if !generation.isMultiple(of: 2) {
    WindowGroup(id: "other") { Text("other") }
  }
}

@MainActor
private struct SceneHostExitBindingsVisitor: WindowSceneConfigurationVisitor {
  mutating func visit<Content: View>(
    descriptor _: SceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<ExitKeyBindings> {
    .finish(configuration.exitKeyBindings)
  }
}
