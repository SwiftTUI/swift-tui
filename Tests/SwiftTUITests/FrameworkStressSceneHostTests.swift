import Foundation
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

// MARK: - Attempt 006: manifest JSON replacement and escaping

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 006 manifest JSON stays current through escaped metadata churn")
  func sceneHost006ManifestJSONStaysCurrentThroughEscapedMetadataChurn() throws {
    // Hypothesis: repeated hand-rolled manifest serialization can retain an
    // earlier escaped title or default identifier when metadata shapes match.
    for generation in 0..<24 {
      let title = "Title \"\(generation)\"\npath\\tail"
      let identifier = WindowIdentifier(" scene/\(generation) \"quoted\" ")
      let descriptors = collectWindowSceneDescriptors(
        from: WindowGroup(title, id: identifier) {
          Text("generation \(generation)")
        }
      )
      let manifest = sceneManifest(from: descriptors)
      let object = try #require(
        JSONSerialization.jsonObject(with: Data(manifest.jsonString.utf8))
          as? [String: Any]
      )
      let scenes = try #require(object["scenes"] as? [[String: Any]])
      let first = try #require(scenes.first)

      #expect(object["defaultSceneID"] as? String == identifier.rawValue)
      #expect(first["id"] as? String == identifier.rawValue)
      #expect(first["title"] as? String == title)
      #expect(first["isDefault"] as? Bool == true)
    }
  }
}

// MARK: - Attempt 007: descriptor and executable selection lockstep

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 007 descriptors and selections stay lockstep through topology churn")
  func sceneHost007DescriptorsAndSelectionsStayLockstepThroughTopologyChurn() {
    // Hypothesis: the descriptor and executable-selection visitors can diverge
    // when optional, erased, and array-built scene nodes change cardinality.
    for generation in 0..<24 {
      let scene = sceneHost007Scene(generation: generation)
      let descriptors = collectWindowSceneDescriptors(from: scene)
      let selections = collectWindowSceneSelections(from: scene)

      #expect(selections.map(\.descriptor) == descriptors)
      #expect(selections.map(\.identifier) == descriptors.map(\.id))
      #expect(selections.map(\.title) == descriptors.map(\.title))
      #expect(selections.map(\.isDefault) == descriptors.map(\.isDefault))
      #expect(Set(selections.map(\.rootIdentity)).count == selections.count)
    }
  }
}

@MainActor
@SceneBuilder
private func sceneHost007Scene(generation: Int) -> some Scene {
  if generation.isMultiple(of: 2) {
    AnyScene(
      WindowGroup("Prefix \(generation)", id: WindowIdentifier("prefix-\(generation)")) {
        Text("prefix")
      })
  }
  for index in 0...(generation % 4) {
    WindowGroup("Array \(index)", id: WindowIdentifier("array-\(generation)-\(index)")) {
      Text("array \(index)")
    }
  }
  if generation.isMultiple(of: 5) {
    AnyScene(
      AnyScene(
        WindowGroup("Suffix \(generation)", id: WindowIdentifier("suffix-\(generation)")) {
          Text("suffix")
        }
      )
    )
  }
}

// MARK: - Attempt 008: dynamic custom Scene body reevaluation

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 008 custom scene body traversal follows every current branch")
  func sceneHost008CustomSceneBodyTraversalFollowsEveryCurrentBranch() {
    // Hypothesis: recursive traversal through a non-primitive Scene can cache
    // its first body shape and ignore later values of the same scene type.
    for generation in 0..<24 {
      let descriptors = collectWindowSceneDescriptors(
        from: SceneHost008DynamicScene(generation: generation)
      )
      let expectedIDs =
        generation.isMultiple(of: 2)
        ? ["even-primary", "even-secondary"]
        : ["odd-only"]

      #expect(descriptors.map(\.id.rawValue) == expectedIDs)
      #expect(
        descriptors.map(\.isDefault) == [true]
          + Array(repeating: false, count: expectedIDs.count - 1))
    }
  }
}

@MainActor
private struct SceneHost008DynamicScene: Scene {
  let generation: Int

  @SceneBuilder
  var body: some Scene {
    if generation.isMultiple(of: 2) {
      WindowGroup(id: "even-primary") { Text("even primary \(generation)") }
      WindowGroup(id: "even-secondary") { Text("even secondary \(generation)") }
    } else {
      WindowGroup(id: "odd-only") { Text("odd \(generation)") }
    }
  }
}

// MARK: - Attempt 009: explicit and generated host-frame sequence interleave

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 009 mixed surface submissions preserve generated sequence monotonicity")
  func sceneHost009MixedSurfaceSubmissionsPreserveGeneratedSequenceMonotonicity() throws {
    // Hypothesis: an explicit semantic-frame submission can advance frame
    // history without advancing the sequence used by later raster submissions.
    var observedSequences: [UInt64] = []
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 8, height: 1),
      appearance: .fallback,
      frameDelivery: .assumedMainActor,
      onFrame: { frame in observedSequences.append(frame.sequence) }
    )

    _ = try surface.present(sceneHostRaster(marker: "initial"))
    #expect(observedSequences == [0])

    for generation in 0..<16 {
      let explicitSequence = UInt64(100 + generation * 3)
      _ = try surface.present(
        SemanticHostFrame(
          sequence: explicitSequence,
          raster: sceneHostRaster(marker: "explicit \(generation)"),
          semantics: .init(),
          focusedIdentity: nil
        )
      )
      _ = try surface.present(sceneHostRaster(marker: "generated \(generation)"))

      #expect(observedSequences.suffix(2) == [explicitSequence, explicitSequence + 1])
    }
  }
}

private func sceneHostRaster(marker: String, size: CellSize = .init(width: 8, height: 1))
  -> RasterSurface
{
  RasterSurface(size: size, lines: [String(marker.prefix(max(0, size.width)))])
}

// MARK: - Attempt 010: asynchronous host callback ordering

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 010 rapid asynchronous delivery preserves submission order")
  func sceneHost010RapidAsynchronousDeliveryPreservesSubmissionOrder() async throws {
    // Hypothesis: one Task hop per frame can let asynchronous host callbacks
    // overtake each other even though surface history records submission order.
    let recorder = SceneHostFrameRecorder()
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 8, height: 1),
      appearance: .fallback,
      onFrame: { frame in recorder.record(frame) }
    )

    for sequence in 0..<64 {
      _ = try surface.present(
        SemanticHostFrame(
          sequence: UInt64(sequence),
          raster: sceneHostRaster(marker: "frame \(sequence)"),
          semantics: .init(),
          focusedIdentity: nil
        )
      )
    }

    await recorder.updates.wait { recorder.frames.count == 64 }
    #expect(recorder.frames.map(\.sequence) == (0..<64).map(UInt64.init))
  }
}

@MainActor
private final class SceneHostFrameRecorder {
  private(set) var frames: [SemanticHostFrame] = []
  let updates = MainActorConditionSignal()

  func record(_ frame: SemanticHostFrame) {
    frames.append(frame)
    updates.notify()
  }
}

// MARK: - Attempt 011: bounded hosted frame history

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 011 frame history retains exactly the newest bounded window")
  func sceneHost011FrameHistoryRetainsExactlyNewestBoundedWindow() async throws {
    // Hypothesis: repeated truncation can remove too many frames, preserve an
    // evicted prefix, or drift beyond the documented 256-frame history bound.
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 8, height: 1),
      appearance: .fallback,
      frameDelivery: .assumedMainActor,
      onFrame: { _ in }
    )

    for sequence in 0..<300 {
      _ = try surface.present(
        SemanticHostFrame(
          sequence: UInt64(sequence),
          raster: sceneHostRaster(marker: "frame \(sequence)"),
          semantics: .init(),
          focusedIdentity: nil
        )
      )
    }

    let frames = await surface.waitForFrames { $0.count == 256 }
    #expect(frames.count == 256)
    #expect(frames.first?.sequence == 44)
    #expect(frames.last?.sequence == 299)
    #expect(frames.map(\.sequence) == (44..<300).map(UInt64.init))
  }
}
