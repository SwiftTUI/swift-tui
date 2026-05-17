import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct PipelineContractTests {
  @Test("sync and async artifacts stay equivalent with committed registrations")
  func syncAndAsyncArtifactsStayEquivalentWithCommittedRegistrations() async {
    let rootIdentity = testIdentity("PipelineContractParityRoot")
    let proposal = ProposedSize(width: 24, height: 5)

    @MainActor
    func root() -> some View {
      PipelineContractCommandView(value: 1)
    }

    let syncArtifacts = DefaultRenderer().render(
      root(),
      context: .init(identity: rootIdentity),
      proposal: proposal,
      collectsDiagnostics: false
    )
    let asyncArtifacts = await DefaultRenderer().renderAsync(
      root(),
      context: .init(identity: rootIdentity),
      proposal: proposal,
      collectsDiagnostics: false
    )

    #expect(syncArtifacts == asyncArtifacts)
  }

  @Test("every modeled frame-drop blocker still forces must-commit")
  func everyModeledFrameDropBlockerStillForcesMustCommit() {
    for blocker in FrameDropEligibility.Blocker.allCases {
      let artifacts = makePipelineContractArtifacts(dropEligibilityBlockers: [blocker])
      let eligibility = FrameDropEligibility.classify(
        .init(
          artifacts: artifacts,
          hasCompleteBarrierSignals: true
        ))

      #expect(eligibility.decision == .mustCommit(blockers: [blocker]))
      #expect(eligibility.canDrop == false)
    }
  }

  @Test("semantic host frames keep contiguous sequence and current frame payload")
  func semanticHostFramesKeepContiguousSequenceAndCurrentPayload() throws {
    let rootIdentity = testIdentity("PipelineContractSemanticHostRoot")
    let surface = PipelineContractSemanticSurface()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: EmptyPipelineContractInputReader(),
      signalReader: EmptyPipelineContractSignalReader(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker
    ) { _, _ in
      PipelineContractSemanticHostView()
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(surface.rasterOnlyPresentations == 0)
    #expect(surface.rasterDamagePresentations == 0)
    #expect(surface.semanticFrames.count == 2)
    #expect(
      surface.semanticFrames.enumerated().allSatisfy { index, frame in
        frame.sequence == UInt64(index)
      })
    for frame in surface.semanticFrames {
      #expect(frame.raster.lines.joined(separator: "\n").contains("Run"))
      #expect(
        frame.semantics.focusRegions.map(\.identity)
          .contains(testIdentity("PipelineContractSemanticHostButton")))
      #expect(frame.focusedIdentity == testIdentity("PipelineContractSemanticHostButton"))
    }
  }

  @Test("focus convergence uses current semantic snapshot after target churn")
  func focusConvergenceUsesCurrentSemanticSnapshotAfterTargetChurn() throws {
    let rootIdentity = testIdentity("PipelineContractDefaultFocusRoot")
    let stateContainer = StateContainer(
      initialState: PipelineContractFocusState(showsSecond: true),
      invalidationIdentities: [rootIdentity]
    )
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let surface = PipelineContractSemanticSurface()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: EmptyPipelineContractInputReader(),
      signalReader: EmptyPipelineContractSignalReader(),
      stateContainer: stateContainer,
      focusTracker: focusTracker
    ) { state, _ in
      PipelineContractDefaultFocusView(showsSecond: state.showsSecond)
    }

    stateContainer.invalidator = runLoop.scheduler
    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(focusTracker.currentFocusIdentity == testIdentity("PipelineContractFocus", "Second"))
    #expect(
      runLoop.latestSemanticSnapshot.focusRegions.map(\.identity)
        .contains(testIdentity("PipelineContractFocus", "Second")))

    stateContainer.replace(with: PipelineContractFocusState(showsSecond: false))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let focusRegionIDs = runLoop.latestSemanticSnapshot.focusRegions.map(\.identity)
    #expect(focusRegionIDs.contains(testIdentity("PipelineContractFocus", "First")))
    #expect(!focusRegionIDs.contains(testIdentity("PipelineContractFocus", "Second")))
    #expect(focusTracker.currentFocusIdentity == testIdentity("PipelineContractFocus", "First"))
    #expect(surface.semanticFrames.last?.focusedIdentity == focusTracker.currentFocusIdentity)
  }

  @Test("retained placement refreshes semantic metadata in renderer path")
  func retainedPlacementRefreshesSemanticMetadataInRendererPath() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("PipelineContractRetainedMetadataRoot")
    let buttonIdentity = testIdentity("PipelineContractRetainedMetadataButton")

    _ = renderer.render(
      PipelineContractAccessibilityView(label: "First", identity: buttonIdentity),
      context: .init(identity: rootIdentity),
      proposal: ProposedSize(width: 24, height: 4)
    )
    let updated = renderer.render(
      PipelineContractAccessibilityView(label: "Second", identity: buttonIdentity),
      context: .init(identity: rootIdentity),
      proposal: ProposedSize(width: 24, height: 4)
    )
    let accessibilityNode = try #require(
      updated.semanticSnapshot.accessibilityNodes.first { $0.identity == buttonIdentity }
    )

    #expect(accessibilityNode.label == "Second")
    #expect(updated.rasterSurface.lines.joined(separator: "\n").contains("Action"))
  }

  @Test(.disabled("closed by Stage 4: raster reuse soundness split"))
  func incrementalRasterReuseMatchesFreshRasterForMutationMatrix() {
    Issue.record(
      "Stage 4 must compare curated incremental raster mutations byte-for-byte with fresh raster."
    )
  }

  @Test(.disabled("closed by Stage 5: closed frame-drop impact model"))
  func frameDropClassificationIsClosedOverCommittedEffects() {
    Issue.record(
      "Stage 5 must replace the current open blocker enum with a closed impact product or guard."
    )
  }

  @Test(.disabled("closed by Stage 6: worker and recursion safety"))
  func frameTailAvoidsUnboundedWorkerAndRecursiveDestructionPaths() {
    Issue.record(
      "Stage 6 must prove worker dispatch and deep tree processing are bounded."
    )
  }

  @Test(.disabled("closed by Stage 7: presentation seam split"))
  func semanticHostFramesDoNotInheritTerminalCommandObligations() {
    Issue.record(
      "Stage 7 must split semantic host-frame delivery from terminal command obligations."
    )
  }
}

private struct PipelineContractCommandView: View {
  var value: Int

  var body: some View {
    Panel(id: "pipeline-contract-command") {
      Text("value \(value)")
        .focusable(true)
    }
    .keyCommand("Commit", key: .character("k"), modifiers: .ctrl) {}
  }
}

private struct PipelineContractSemanticHostView: View {
  var body: some View {
    Button("Run") {}
      .id(testIdentity("PipelineContractSemanticHostButton"))
  }
}

private struct PipelineContractFocusState: Equatable, Sendable {
  var showsSecond: Bool
}

private enum PipelineContractFocusField: Hashable {
  case first
  case second
}

private struct PipelineContractDefaultFocusView: View {
  @FocusState private var focusedField: PipelineContractFocusField?

  var showsSecond: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("First") {}
        .id(testIdentity("PipelineContractFocus", "First"))
        .focused($focusedField, equals: .first)
      if showsSecond {
        Button("Second") {}
          .id(testIdentity("PipelineContractFocus", "Second"))
          .focused($focusedField, equals: .second)
      }
    }
    .defaultFocus($focusedField, showsSecond ? .second : .first)
  }
}

private struct PipelineContractAccessibilityView: View {
  var label: String
  var identity: Identity

  var body: some View {
    Button("Action") {}
      .id(identity)
      .accessibilityLabel(label)
  }
}

private final class PipelineContractSemanticSurface:
  PresentationSurface, DamageAwarePresentationSurface, SemanticHostFramePresentationSurface
{
  let surfaceSize = CellSize(width: 24, height: 6)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let semanticHostFrameCapabilities: SemanticHostFrameCapabilities = .standard
  private(set) var semanticFrames: [SemanticHostFrame] = []
  private(set) var rasterOnlyPresentations = 0
  private(set) var rasterDamagePresentations = 0

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    rasterOnlyPresentations += 1
    return TerminalPresentationMetrics.rasterHostMetrics(for: surface, damage: nil)
  }

  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    rasterDamagePresentations += 1
    return TerminalPresentationMetrics.rasterHostMetrics(for: surface, damage: damage)
  }

  @discardableResult
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    semanticFrames.append(frame)
    return TerminalPresentationMetrics.rasterHostMetrics(
      for: frame.raster,
      damage: frame.rasterDamage
    )
  }
}

private final class EmptyPipelineContractInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class EmptyPipelineContractSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private func makePipelineContractArtifacts(
  dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>
) -> FrameArtifacts {
  let identity = testIdentity("PipelineContractDrop")
  let resolved = ResolvedNode(identity: identity, kind: .root)
  let measured = MeasuredNode(
    identity: identity,
    proposal: .unspecified,
    measuredSize: .zero
  )
  let placed = PlacedNode(
    identity: identity,
    bounds: .init(origin: .zero, size: .zero)
  )
  let draw = DrawNode(identity: identity, bounds: .init(origin: .zero, size: .zero))
  let diagnostics = FrameDiagnostics(dropEligibilityBlockers: dropEligibilityBlockers)

  return FrameArtifacts(
    resolvedTree: resolved,
    measuredTree: measured,
    placedTree: placed,
    semanticSnapshot: .init(),
    drawTree: draw,
    rasterSurface: .init(),
    presentationDamage: nil,
    commitPlan: .init(transaction: .init(), semanticSnapshot: .init()),
    diagnostics: diagnostics
  )
}
