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

// MARK: - Attempt 012: concurrent late observers of retained frames

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 012 late observers recover disjoint retained frames")
  func sceneHost012LateObserversRecoverDisjointRetainedFrames() async throws {
    // Hypothesis: concurrent late observers can disagree about retained history
    // or recover a neighboring frame after the bounded window has rolled over.
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

    let retained = await surface.waitForFrames { $0.count == 256 }
    let targets: [UInt64] = [44, 45, 63, 127, 191, 255, 298, 299]
    #expect(targets.allSatisfy { target in retained.contains { $0.sequence == target } })

    let observers = targets.map { target in
      Task { await surface.waitForFrame { $0.sequence == target } }
    }
    var resumed: [UInt64] = []
    for observer in observers {
      resumed.append(await observer.value.sequence)
    }
    #expect(resumed == targets)
  }
}

// MARK: - Attempt 013: retained surface across session replacement

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 013 replacement sessions isolate producer sequences")
  func sceneHost013ReplacementSessionsIsolateProducerSequences() async throws {
    // Hypothesis: retaining one host surface can leak its prior sequence into a
    // replacement runtime or overwrite history at the producer boundary.
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 20, height: 4),
      appearance: .fallback,
      frameDelivery: .assumedMainActor,
      onFrame: { _ in }
    )
    var firstSequences: [UInt64] = []
    var retainedSequences: [UInt64] = []

    for _ in 0..<8 {
      let baselineCount = retainedSequences.count
      let session = try HostedSceneSession(
        for: SceneHostSessionApp(),
        sceneID: "primary",
        surface: surface
      )
      let runTask = Task { try await session.start() }
      _ = await surface.waitForFrames { $0.count > baselineCount }

      _ = try await session.stopAndWait()
      _ = try await runTask.value
      let frames = await surface.waitForFrames { _ in true }
      let produced = frames.dropFirst(baselineCount)
      let first = try #require(produced.first)

      #expect(Array(frames.prefix(baselineCount).map(\.sequence)) == retainedSequences)
      #expect(first.sequence == 0)
      #expect(
        zip(produced, produced.dropFirst()).allSatisfy { previous, current in
          current.sequence > previous.sequence
        }
      )
      firstSequences.append(first.sequence)
      retainedSequences = frames.map(\.sequence)
    }

    #expect(firstSequences == Array(repeating: 0, count: 8))
    #expect(retainedSequences.count >= 8)
  }
}

private struct SceneHostSessionApp: App {
  var body: some Scene {
    WindowGroup("Primary", id: "primary") {
      Text("session root")
    }
  }
}

// MARK: - Attempt 014: concurrent HostedSceneSession start callers

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 014 concurrent start callers share one session result")
  func sceneHost014ConcurrentStartCallersShareOneSessionResult() async throws {
    // Hypothesis: callers entering start before the first run completes can
    // launch duplicate run loops over one input reader and split the exit event.
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 20, height: 4),
      appearance: .fallback,
      frameDelivery: .assumedMainActor,
      onFrame: { _ in }
    )
    let session = try HostedSceneSession(
      for: SceneHostSessionApp(),
      sceneID: "primary",
      surface: surface
    )
    let callers = (0..<8).map { _ in
      Task { try await session.start() }
    }

    _ = await surface.waitForFrame()
    session.send(.key(KeyPress(.character("d"), modifiers: .ctrl)))

    var results: [RunLoopExitReason] = []
    for caller in callers {
      results.append(try await caller.value)
    }
    #expect(results.count == 8)
    let expected = RunLoopExitReason.userExit(KeyPress(.character("d"), modifiers: .ctrl))
    #expect(results.allSatisfy { $0 == expected })
  }
}

// MARK: - Attempt 015: repeated hosted-session stop and teardown

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 015 repeated stops clear focus once and emit no later frame")
  func sceneHost015RepeatedStopsClearFocusOnceAndEmitNoLaterFrame() async throws {
    // Hypothesis: overlapping stop paths can publish duplicate focus teardown
    // or leave a live signal path that renders again after shutdown completes.
    let frameRecorder = SceneHostFrameRecorder()
    let focusRecorder = SceneHostFocusRecorder()
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 20, height: 4),
      appearance: .fallback,
      onFrame: { frame in frameRecorder.record(frame) }
    )
    let session = try HostedSceneSession(
      for: SceneHostFocusApp(),
      sceneID: "primary",
      surface: surface,
      onFocusPresentationChange: { focusRecorder.record($0) }
    )
    let runTask = Task { try await session.start() }
    await focusRecorder.updates.wait { focusRecorder.values.contains { $0 != .none } }

    let stopWaiter = Task { try await session.stopAndWait() }
    await Task.yield()
    for _ in 0..<16 {
      session.stop()
    }
    #expect(try await stopWaiter.value == .inputEnded)
    #expect(try await runTask.value == .inputEnded)

    let stoppedFrameCount = frameRecorder.frames.count
    for generation in 0..<16 {
      surface.updateSurfaceSize(.init(width: 20 + generation, height: 4))
      session.requestSurfaceRefresh()
    }
    for _ in 0..<8 { await Task.yield() }

    #expect(focusRecorder.values.filter { $0 == .none }.count == 1)
    #expect(frameRecorder.frames.count == stoppedFrameCount)
    #expect(session.currentFocusPresentation == .none)
  }
}

private struct SceneHostFocusApp: App {
  var body: some Scene {
    WindowGroup("Primary", id: "primary") {
      Text("editable")
        .focusable(true, interactions: .edit)
    }
  }
}

@MainActor
private final class SceneHostFocusRecorder {
  private(set) var values: [FocusPresentation] = []
  let updates = MainActorConditionSignal()

  func record(_ value: FocusPresentation) {
    values.append(value)
    updates.notify()
  }
}

// MARK: - Attempt 016: hosted environment refresh storm

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 016 host metric storms converge on the latest environment")
  func sceneHost016HostMetricStormsConvergeOnLatestEnvironment() async throws {
    // Hypothesis: separately locked host size, style, and capability updates can
    // produce a retained frame that permanently mixes values from generations.
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 80, height: 4),
      appearance: .fallback,
      frameDelivery: .assumedMainActor,
      onFrame: { _ in }
    )
    let session = try HostedSceneSession(
      for: SceneHostEnvironmentApp(),
      sceneID: "primary",
      surface: surface
    )
    let runTask = Task { try await session.start() }
    _ = await surface.waitForFrame()

    for generation in 1...16 {
      let size = CellSize(width: 48 + generation, height: 3 + generation % 3)
      let pixels = PixelSize(width: 6 + generation, height: 12 + generation)
      let hover = generation.isMultiple(of: 2)
      let appearance = TerminalAppearance(
        foregroundColor: hover ? .green : .yellow,
        backgroundColor: .black,
        tintColor: .cyan,
        source: .override
      )
      let expected =
        "\(size.width)x\(size.height)|\(pixels.width)x\(pixels.height)|override|\(hover)"

      surface.updateSurfaceSize(size)
      surface.updateStyle(.init(appearance: appearance, theme: appearance.synthesizedTheme()))
      surface.updateSurfaceCapabilities(
        cellPixelSize: pixels,
        pointerInputCapabilities: .init(supportsHover: hover, supportsPreciseScroll: !hover)
      )
      session.requestSurfaceRefresh()

      let frames = await surface.waitForFrames { frames in
        frames.contains { $0.raster.lines.joined(separator: "\n").contains(expected) }
      }
      #expect(frames.last { $0.raster.lines.joined(separator: "\n").contains(expected) } != nil)
    }

    _ = try await session.stopAndWait()
    _ = try await runTask.value
  }
}

private struct SceneHostEnvironmentApp: App {
  var body: some Scene {
    WindowGroup("Primary", id: "primary") {
      SceneHostEnvironmentView()
    }
  }
}

private struct SceneHostEnvironmentView: View {
  @Environment(\.terminalSize) private var terminalSize
  @Environment(\.terminalAppearance) private var appearance
  @Environment(\.cellPixelMetrics) private var cellPixels
  @Environment(\.pointerInputCapabilities) private var pointerCapabilities

  var body: some View {
    Text(
      "\(terminalSize.width)x\(terminalSize.height)|"
        + "\(cellPixels.width)x\(cellPixels.height)|"
        + "\(appearance.source.rawValue)|\(pointerCapabilities.supportsHover)"
    )
  }
}

// MARK: - Attempt 017: whole hosted-session state replacement

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 017 replacement sessions reset state and discard stale actions")
  func sceneHost017ReplacementSessionsResetStateAndDiscardStaleActions() async throws {
    // Hypothesis: replacing a session on one surface can restore the departed
    // state container or dispatch a key command through an earlier run loop.
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 24, height: 5),
      appearance: .fallback,
      frameDelivery: .assumedMainActor,
      onFrame: { _ in }
    )

    for _ in 0..<8 {
      let baselineCount = await surface.waitForFrames { _ in true }.count
      let session = try HostedSceneSession(
        for: SceneHostCounterApp(),
        sceneID: "primary",
        surface: surface
      )
      let runTask = Task { try await session.start() }
      _ = await surface.waitForFrames { frames in
        frames.dropFirst(baselineCount).contains { sceneHostRasterText($0).contains("Count 0") }
      }

      session.send(.key(KeyPress(.character("i"), modifiers: .ctrl)))
      let incremented = await surface.waitForFrames { frames in
        frames.dropFirst(baselineCount).contains { sceneHostRasterText($0).contains("Count 1") }
      }
      let currentFrames = incremented.dropFirst(baselineCount)
      #expect(currentFrames.contains { sceneHostRasterText($0).contains("Count 0") })
      #expect(currentFrames.contains { sceneHostRasterText($0).contains("Count 1") })
      #expect(!currentFrames.contains { sceneHostRasterText($0).contains("Count 2") })

      _ = try await session.stopAndWait()
      _ = try await runTask.value
    }
  }
}

private struct SceneHostCounterApp: App {
  var body: some Scene {
    WindowGroup("Primary", id: "primary") {
      SceneHostCounterView()
    }
  }
}

private struct SceneHostCounterView: View {
  @State private var count = 0

  var body: some View {
    Panel(id: "counter") {
      Text("Count \(count)")
        .focusable(true)
    }
    .keyCommand("Increment", key: .character("i"), modifiers: .ctrl) {
      count += 1
    }
  }
}

private func sceneHostRasterText(_ frame: SemanticHostFrame) -> String {
  frame.raster.lines.joined(separator: "\n")
}

// MARK: - Attempt 018: independent hosted-size axes

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 018 mixed proposals keep negotiated axes independent")
  func sceneHost018MixedProposalsKeepNegotiatedAxesIndependent() {
    // Hypothesis: resolving one finite host axis can accidentally substitute
    // its proposal or probe state into the opposite unspecified axis.
    let negotiator = HostedSurfaceSizeNegotiator(
      cellSize: .init(width: 2, height: 4),
      preferredGridSize: .init(width: 10, height: 6),
      renderedGridSize: .init(width: 12, height: 8)
    )

    for generation in 1...24 {
      if generation.isMultiple(of: 2) {
        let proposedWidth = Double(3 + generation) * 2 + 1.5
        let expectedCells = min(10, 3 + generation)
        let result = negotiator.negotiate(
          proposedWidth: proposedWidth,
          proposedHeight: nil
        )
        #expect(result.size == .init(width: Double(expectedCells) * 2, height: 24))
        #expect(result.probeGridSize == nil)
      } else {
        let proposedHeight = Double(2 + generation) * 4 + 3.5
        let expectedCells = min(6, 2 + generation)
        let result = negotiator.negotiate(
          proposedWidth: nil,
          proposedHeight: proposedHeight
        )
        #expect(result.size == .init(width: 20, height: Double(expectedCells) * 4))
        #expect(result.probeGridSize == nil)
      }
    }
  }
}

// MARK: - Attempt 019: per-axis confirmed-slack invalidation

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 019 slack invalidation stays isolated to the changed axis")
  func sceneHost019SlackInvalidationStaysIsolatedToChangedAxis() {
    // Hypothesis: updating one invalid size relation can clear or preserve both
    // axis records because confirmed slack is retained as one aggregate value.
    for _ in 0..<16 {
      var widthInvalidated = HostedSurfaceConfirmedSlack()
      widthInvalidated.update(
        preferredGridSize: .init(width: 10, height: 5),
        renderedGridSize: .init(width: 14, height: 9)
      )
      widthInvalidated.update(
        preferredGridSize: .init(width: 14, height: 5),
        renderedGridSize: .init(width: 14, height: 8)
      )
      #expect(
        widthInvalidated.confirmedPreferredWidth(proposed: 12, preferred: 14, rendered: 14)
          == nil)
      #expect(
        widthInvalidated.confirmedPreferredHeight(proposed: 8, preferred: 5, rendered: 8) == 5)
      #expect(
        HostedSurfaceSizeNegotiator(
          cellSize: .init(width: 1, height: 1),
          preferredGridSize: .init(width: 14, height: 5),
          renderedGridSize: .init(width: 14, height: 8),
          confirmedSlack: widthInvalidated
        ).negotiate(proposedWidth: 12, proposedHeight: 8)
          == .init(size: .init(width: 12, height: 5), probeGridSize: nil)
      )

      var heightInvalidated = HostedSurfaceConfirmedSlack()
      heightInvalidated.update(
        preferredGridSize: .init(width: 10, height: 5),
        renderedGridSize: .init(width: 14, height: 9)
      )
      heightInvalidated.update(
        preferredGridSize: .init(width: 10, height: 9),
        renderedGridSize: .init(width: 13, height: 9)
      )
      #expect(
        heightInvalidated.confirmedPreferredWidth(proposed: 12, preferred: 10, rendered: 13)
          == 10)
      #expect(
        heightInvalidated.confirmedPreferredHeight(proposed: 7, preferred: 9, rendered: 9)
          == nil)
      #expect(
        HostedSurfaceSizeNegotiator(
          cellSize: .init(width: 1, height: 1),
          preferredGridSize: .init(width: 10, height: 9),
          renderedGridSize: .init(width: 13, height: 9),
          confirmedSlack: heightInvalidated
        ).negotiate(proposedWidth: 12, proposedHeight: 7)
          == .init(size: .init(width: 10, height: 7), probeGridSize: nil)
      )
    }
  }
}

// MARK: - Attempt 020: fractional host cell metric conversion

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 020 fractional cell metrics floor every probe exactly")
  func sceneHost020FractionalCellMetricsFloorEveryProbeExactly() {
    // Hypothesis: floating-point proposal churn can round a host axis upward,
    // produce zero cells, or leak a prior generation's probe cardinality.
    for generation in 0..<24 {
      let cellSize = HostLengthSize(
        width: 1.25 + Double(generation % 4) * 0.5,
        height: 2.5 + Double(generation % 3) * 0.75
      )
      let expectedGrid = CellSize(
        width: 1 + generation % 11,
        height: 1 + generation % 7
      )
      let negotiator = HostedSurfaceSizeNegotiator(
        cellSize: cellSize,
        preferredGridSize: nil,
        renderedGridSize: nil,
        fallbackGridSize: .init(width: 80, height: 24)
      )
      let result = negotiator.negotiate(
        proposedWidth: (Double(expectedGrid.width) + 0.999) * cellSize.width,
        proposedHeight: (Double(expectedGrid.height) + 0.999) * cellSize.height
      )

      #expect(result.size == cellSize)
      #expect(result.probeGridSize == expectedGrid)
    }
  }
}

// MARK: - Attempt 021: preferred-size disappearance clears slack

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 021 preferred size disappearance clears confirmed slack")
  func sceneHost021PreferredSizeDisappearanceClearsConfirmedSlack() {
    // Hypothesis: a nil preferred-size generation can leave old slack evidence
    // active when the same preferred dimensions later reappear.
    var slack = HostedSurfaceConfirmedSlack()

    for _ in 0..<16 {
      slack.update(
        preferredGridSize: .init(width: 8, height: 4),
        renderedGridSize: .init(width: 12, height: 8)
      )
      #expect(slack.confirmedPreferredWidth(proposed: 10, preferred: 8, rendered: 12) == 8)
      #expect(slack.confirmedPreferredHeight(proposed: 6, preferred: 4, rendered: 8) == 4)

      slack.update(preferredGridSize: nil, renderedGridSize: .init(width: 12, height: 8))
      #expect(slack.confirmedPreferredWidth(proposed: 10, preferred: 8, rendered: 12) == nil)
      #expect(slack.confirmedPreferredHeight(proposed: 6, preferred: 4, rendered: 8) == nil)
      #expect(
        HostedSurfaceSizeNegotiator(
          cellSize: .init(width: 2, height: 3),
          preferredGridSize: .init(width: 8, height: 4),
          renderedGridSize: .init(width: 12, height: 8),
          confirmedSlack: slack
        ).negotiate(proposedWidth: 20, proposedHeight: 18)
          == .init(size: .init(width: 16, height: 12), probeGridSize: nil)
      )
    }
  }
}

// MARK: - Attempt 022: growth-probe feedback convergence

extension FrameworkStressSceneHostTests {
  @Test("stress scene host 022 growth probe feedback converges without a two cycle")
  func sceneHost022GrowthProbeFeedbackConvergesWithoutTwoCycle() {
    // Hypothesis: once a large probe confirms slack, returning to the preferred
    // rendered grid can erase that evidence and request the same probe forever.
    for generation in 0..<16 {
      let preferred = CellSize(width: 8 + generation % 5, height: 4 + generation % 3)
      let probe = CellSize(width: preferred.width + 7, height: preferred.height + 5)
      let cellSize = HostLengthSize(width: 2, height: 3)
      var slack = HostedSurfaceConfirmedSlack()

      let first = HostedSurfaceSizeNegotiator(
        cellSize: cellSize,
        preferredGridSize: preferred,
        renderedGridSize: preferred,
        confirmedSlack: slack
      ).negotiate(
        proposedWidth: Double(probe.width) * cellSize.width,
        proposedHeight: Double(probe.height) * cellSize.height
      )
      #expect(
        first
          == .init(
            size: .init(
              width: Double(preferred.width) * cellSize.width,
              height: Double(preferred.height) * cellSize.height
            ),
            probeGridSize: probe
          )
      )

      slack.update(preferredGridSize: preferred, renderedGridSize: probe)
      let confirmed = HostedSurfaceSizeNegotiator(
        cellSize: cellSize,
        preferredGridSize: preferred,
        renderedGridSize: probe,
        confirmedSlack: slack
      ).negotiate(
        proposedWidth: Double(probe.width) * cellSize.width,
        proposedHeight: Double(probe.height) * cellSize.height
      )
      #expect(confirmed.size == first.size)
      #expect(confirmed.probeGridSize == nil)

      slack.update(preferredGridSize: preferred, renderedGridSize: preferred)
      let revisited = HostedSurfaceSizeNegotiator(
        cellSize: cellSize,
        preferredGridSize: preferred,
        renderedGridSize: preferred,
        confirmedSlack: slack
      ).negotiate(
        proposedWidth: Double(probe.width) * cellSize.width,
        proposedHeight: Double(probe.height) * cellSize.height
      )
      #expect(revisited == confirmed)
    }
  }
}
