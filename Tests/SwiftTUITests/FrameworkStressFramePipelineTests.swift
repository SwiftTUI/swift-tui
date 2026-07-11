import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI frame-pipeline stress behavior", .serialized)
struct FrameworkStressFramePipelineTests {}

// MARK: - Attempt 001: alternating narrow dirty sets

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 001 alternating dirty siblings preserve narrow reuse")
  func framePipeline001AlternatingDirtySiblingsPreserveNarrowReuse() {
    // Hypothesis: switching the directly-dirty sibling every generation can
    // broaden the retained invalidation summary and stop reusing the clean peer.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("FramePipeline001", "Root")
    let proposal = ProposedSize(width: 40, height: 4)
    var first = "first-0"
    var second = "second-0"

    _ = renderer.render(
      FramePipelineSiblingView(first: first, second: second),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    for generation in 1...16 {
      let dirtyIdentity: Identity
      if generation.isMultiple(of: 2) {
        first = "first-\(generation)"
        dirtyIdentity = testIdentity("FramePipeline001", "Root", "VStack[0]")
      } else {
        second = "second-\(generation)"
        dirtyIdentity = testIdentity("FramePipeline001", "Root", "VStack[1]")
      }

      let retained = renderer.render(
        FramePipelineSiblingView(first: first, second: second),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [dirtyIdentity]
        ),
        proposal: proposal
      )
      let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
        FramePipelineSiblingView(first: first, second: second),
        context: .init(identity: rootIdentity),
        proposal: proposal
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.diagnostics.input.invalidatedIdentities == [dirtyIdentity])
      #expect(
        retained.diagnostics.work.resolvedNodesReused >= 1,
        "generation \(generation) should reuse the sibling outside the dirty set"
      )
      #expect(retained.diagnostics.work.measuredNodesReused >= 1)
      #expect(retained.diagnostics.work.placedNodesReused >= 1)
    }
  }
}

@MainActor
private struct FramePipelineSiblingView: View {
  let first: String
  let second: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(first)
      Text(second)
    }
  }
}

// MARK: - Attempt 002: descendant dirtiness remains narrow

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 002 descendant dirtiness never promotes to root")
  func framePipeline002DescendantDirtinessNeverPromotesToRoot() {
    // Hypothesis: repeated descendant-only invalidations can be retained as a
    // coarse root invalidation, defeating selective frame-head evaluation.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("FramePipeline002", "Root")
    let dirtyIdentity = testIdentity("FramePipeline002", "DirtyLeaf")
    let proposal = ProposedSize(width: 48, height: 6)

    _ = renderer.render(
      FramePipelineNestedView(generation: 0, dirtyIdentity: dirtyIdentity),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    for generation in 1...18 {
      let retained = renderer.render(
        FramePipelineNestedView(generation: generation, dirtyIdentity: dirtyIdentity),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [dirtyIdentity]
        ),
        proposal: proposal
      )
      let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
        FramePipelineNestedView(generation: generation, dirtyIdentity: dirtyIdentity),
        context: .init(identity: rootIdentity),
        proposal: proposal
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.diagnostics.input.invalidatedIdentities == [dirtyIdentity])
      #expect(!retained.diagnostics.input.invalidatedIdentities.contains(rootIdentity))
      #expect(retained.diagnostics.work.resolvedNodesReused >= 2)
    }
  }
}

@MainActor
private struct FramePipelineNestedView: View {
  let generation: Int
  let dirtyIdentity: Identity

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Text("stable-left")
        Text("dirty-\(generation)")
          .id(dirtyIdentity)
      }
      Text("stable-bottom")
    }
  }
}

// MARK: - Attempt 003: revisited dirty baseline

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 003 revisited dirty sibling uses latest committed baseline")
  func framePipeline003RevisitedDirtySiblingUsesLatestCommittedBaseline() {
    // Hypothesis: an A-dirty, B-dirty, A-dirty sequence can index A against
    // the first frame and reuse B from the intermediate generation incorrectly.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("FramePipeline003", "Root")
    let firstIdentity = testIdentity("FramePipeline003", "Root", "VStack[0]")
    let secondIdentity = testIdentity("FramePipeline003", "Root", "VStack[1]")
    let proposal = ProposedSize(width: 42, height: 4)
    var first = "A-0"
    var second = "B-0"

    _ = renderer.render(
      FramePipelineSiblingView(first: first, second: second),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    func renderAndCheck(dirtyIdentity: Identity) {
      let retained = renderer.render(
        FramePipelineSiblingView(first: first, second: second),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [dirtyIdentity]
        ),
        proposal: proposal
      )
      let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
        FramePipelineSiblingView(first: first, second: second),
        context: .init(identity: rootIdentity),
        proposal: proposal
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.diagnostics.work.resolvedNodesReused >= 1)
      #expect(retained.diagnostics.input.invalidatedIdentities == [dirtyIdentity])
    }

    for cycle in 1...12 {
      first = "A-\(cycle)"
      renderAndCheck(dirtyIdentity: firstIdentity)

      second = "B-\(cycle)"
      renderAndCheck(dirtyIdentity: secondIdentity)

      first = "A-\(cycle - 1)"
      renderAndCheck(dirtyIdentity: firstIdentity)
    }
  }
}

// MARK: - Attempt 004: clean generation clears dirty evidence

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 004 clean generation clears prior dirty diagnostics")
  func framePipeline004CleanGenerationClearsPriorDirtyDiagnostics() {
    // Hypothesis: a narrow invalidation can remain in the retained frame input
    // and be reported or recomputed again on the following clean generation.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("FramePipeline004", "Root")
    let dirtyIdentity = testIdentity("FramePipeline004", "Root", "VStack[1]")
    let proposal = ProposedSize(width: 40, height: 4)

    _ = renderer.render(
      FramePipelineSiblingView(first: "stable", second: "value-0"),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    renderer.enableSelectiveEvaluation()
    let dirty = renderer.render(
      FramePipelineSiblingView(first: "stable", second: "value-1"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [dirtyIdentity]
      ),
      proposal: proposal
    )
    let clean = renderer.render(
      FramePipelineSiblingView(first: "stable", second: "value-1"),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    #expect(dirty.diagnostics.input.invalidatedIdentities == [dirtyIdentity])
    #expect(clean.diagnostics.input.invalidatedIdentities.isEmpty)
    #expect(clean.diagnostics.work.resolvedNodesComputed == 0)
    #expect(clean.diagnostics.work.resolvedNodesReused == 0)
    #expect(clean.rasterSurface == dirty.rasterSurface)
    #expect(clean.presentationDamage?.dirtyRows.isEmpty == true)
  }
}

// MARK: - Attempt 005: proposal-specific phase products

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 005 revisited proposal rejects intervening phase products")
  func framePipeline005RevisitedProposalRejectsInterveningPhaseProducts() {
    // Hypothesis: proposal A -> B -> A can carry B's retained semantic/draw
    // products into the revisited A frame because only tree identity is checked.
    let state = FrameTailRetainedState()
    let root = framePipelineArtifactTree(prefix: "FramePipeline005", childCount: 2)
    let artifacts = framePipelineArtifacts(root: root, rasterLine: "phase-products")
    let proposalA = ProposedSize(width: 24, height: 4)
    let proposalB = ProposedSize(width: 12, height: 4)

    state.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: artifacts.placedTree,
      proposal: proposalA
    )
    let firstA = state.input(invalidatedIdentities: [])
    #expect(
      firstA.phaseExtractionProof(
        for: proposalA,
        placed: artifacts.placedTree,
        animationOverlaySnapshot: .init()
      ) == .wholeTreeIdentical
    )

    state.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: artifacts.placedTree,
      proposal: proposalB
    )
    let afterB = state.input(invalidatedIdentities: [])
    #expect(
      afterB.phaseExtractionProof(
        for: proposalA,
        placed: artifacts.placedTree,
        animationOverlaySnapshot: .init()
      ) == .none
    )

    state.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: artifacts.placedTree,
      proposal: proposalA
    )
    let revisitedA = state.input(invalidatedIdentities: [])
    #expect(
      revisitedA.phaseExtractionProof(
        for: proposalA,
        placed: artifacts.placedTree,
        animationOverlaySnapshot: .init()
      ) == .wholeTreeIdentical
    )
  }
}

private struct FramePipelineArtifactNode {
  var viewNodeID: ViewNodeID? = nil
  var identity: Identity
  var bounds: CellRect
  var children: [Self] = []
  var drawPayload: DrawPayload = .none
}

private func framePipelineArtifactTree(
  prefix: String,
  childCount: Int
) -> FramePipelineArtifactNode {
  let children = (0..<childCount).map { index in
    FramePipelineArtifactNode(
      viewNodeID: ViewNodeID(rawValue: UInt64(index + 2)),
      identity: testIdentity(prefix, "Root", "Child[\(index)]"),
      bounds: .init(
        origin: .init(x: 0, y: index),
        size: .init(width: 12, height: 1)
      ),
      drawPayload: .text("child-\(index)")
    )
  }
  return FramePipelineArtifactNode(
    viewNodeID: ViewNodeID(rawValue: 1),
    identity: testIdentity(prefix, "Root"),
    bounds: .init(
      origin: .zero,
      size: .init(width: 12, height: max(1, childCount))
    ),
    children: children
  )
}

private func framePipelineArtifacts(
  root: FramePipelineArtifactNode,
  rasterLine: String,
  drawnIdentities: Set<Identity>? = nil,
  commitPlan: CommitPlan = .init(),
  diagnostics: FrameDiagnostics = .init()
) -> FrameArtifacts {
  func resolved(_ node: FramePipelineArtifactNode) -> ResolvedNode {
    ResolvedNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      kind: .view("FramePipelineArtifact"),
      children: node.children.map(resolved),
      drawPayload: node.drawPayload,
      intrinsicSize: node.bounds.size
    )
  }

  func measured(_ node: FramePipelineArtifactNode) -> MeasuredNode {
    MeasuredNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      proposal: .init(width: node.bounds.size.width, height: node.bounds.size.height),
      measuredSize: node.bounds.size,
      childMeasurements: node.children.map(measured)
    )
  }

  func placed(_ node: FramePipelineArtifactNode) -> PlacedNode {
    PlacedNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      bounds: node.bounds,
      children: node.children.map(placed),
      drawPayload: node.drawPayload
    )
  }

  func draw(_ node: FramePipelineArtifactNode) -> DrawNode {
    DrawNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      bounds: node.bounds,
      children: node.children.map(draw)
    )
  }

  func identities(_ node: FramePipelineArtifactNode) -> Set<Identity> {
    node.children.reduce(into: Set([node.identity])) { result, child in
      result.formUnion(identities(child))
    }
  }

  return FrameArtifacts(
    resolvedTree: resolved(root),
    measuredTree: measured(root),
    placedTree: placed(root),
    semanticSnapshot: .init(),
    drawTree: draw(root),
    rasterSurface: .init(size: root.bounds.size, lines: [rasterLine]),
    presentationDamage: nil,
    drawnIdentities: drawnIdentities ?? identities(root),
    commitPlan: commitPlan,
    diagnostics: diagnostics
  )
}

// MARK: - Attempt 006: unsupported dirty subtree preserves sibling reuse

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 006 unsupported dirty subtree preserves clean phase reuse")
  func framePipeline006UnsupportedDirtySubtreePreservesCleanPhaseReuse() {
    // Hypothesis: a canvas in the dirty branch can make the nil whole-tree
    // signature suppress retained semantic/draw extraction for clean siblings.
    let state = FrameTailRetainedState()
    let rootIdentity = testIdentity("FramePipeline006", "Root")
    let cleanIdentity = testIdentity("FramePipeline006", "Root", "Clean")
    let dirtyIdentity = testIdentity("FramePipeline006", "Root", "Canvas")
    let clean = FramePipelineArtifactNode(
      identity: cleanIdentity,
      bounds: .init(origin: .zero, size: .init(width: 8, height: 1)),
      drawPayload: .text("clean")
    )
    let canvas = FramePipelineArtifactNode(
      identity: dirtyIdentity,
      bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 8, height: 1)),
      drawPayload: .canvas(.init(drawing: FramePipelineCanvasDots()))
    )
    let root = FramePipelineArtifactNode(
      identity: rootIdentity,
      bounds: .init(origin: .zero, size: .init(width: 8, height: 2)),
      children: [clean, canvas]
    )
    let artifacts = framePipelineArtifacts(root: root, rasterLine: "clean")
    let proposal = ProposedSize(width: 8, height: 2)

    state.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: artifacts.placedTree,
      proposal: proposal
    )
    let retained = state.input(invalidatedIdentities: [dirtyIdentity])
    let proof = retained.phaseExtractionProof(
      for: proposal,
      placed: artifacts.placedTree,
      animationOverlaySnapshot: .init()
    )

    #expect(proof == .subtreesIdentical([cleanIdentity]))
    #expect(proof.canReuseSubtree(rootedAt: cleanIdentity))
    #expect(!proof.canReuseSubtree(rootedAt: dirtyIdentity))
    #expect(!proof.canReuseSubtree(rootedAt: rootIdentity))
  }
}

private struct FramePipelineCanvasDots: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.setSample(GridSample(x: 0, y: 0))
  }
}

// MARK: - Attempt 007: overlay mismatch is one-generation state

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 007 clean commit restores phase products after overlay")
  func framePipeline007CleanCommitRestoresPhaseProductsAfterOverlay() {
    // Hypothesis: once an animation overlay makes effective placement differ
    // from its baseline, the phase-product store can remain disabled forever.
    let state = FrameTailRetainedState()
    let proposal = ProposedSize(width: 12, height: 2)
    let baselineRoot = framePipelineArtifactTree(prefix: "FramePipeline007", childCount: 2)
    let baseline = framePipelineArtifacts(root: baselineRoot, rasterLine: "baseline")
    var overlayRoot = baselineRoot
    overlayRoot.children[1].bounds.origin.x = 3
    let overlay = framePipelineArtifacts(root: overlayRoot, rasterLine: "overlay")

    for _ in 1...10 {
      state.storeCommittedFrame(
        overlay,
        baselinePlacedTree: baseline.placedTree,
        proposal: proposal
      )
      let disabled = state.input(invalidatedIdentities: [])
      #expect(disabled.previousPhaseProducts == nil)
      #expect(
        disabled.phaseExtractionProof(
          for: proposal,
          placed: overlay.placedTree,
          animationOverlaySnapshot: .init()
        ) == .none
      )

      state.storeCommittedFrame(
        baseline,
        baselinePlacedTree: baseline.placedTree,
        proposal: proposal
      )
      let restored = state.input(invalidatedIdentities: [])
      #expect(restored.previousPhaseProducts != nil)
      #expect(
        restored.phaseExtractionProof(
          for: proposal,
          placed: baseline.placedTree,
          animationOverlaySnapshot: .init()
        ) == .wholeTreeIdentical
      )
    }
  }
}

// MARK: - Attempt 008: retained index shrink and regrow

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 008 retained index metrics follow shrink and regrow")
  func framePipeline008RetainedIndexMetricsFollowShrinkAndRegrow() throws {
    // Hypothesis: the retained index patch path can keep removed entries after
    // a shrink, then alias them when the same structural slots regrow.
    let state = FrameTailRetainedState()
    let proposal = ProposedSize(width: 12, height: 24)
    let largeRoot = framePipelineArtifactTree(prefix: "FramePipeline008", childCount: 24)
    let smallRoot = framePipelineArtifactTree(prefix: "FramePipeline008", childCount: 2)
    let regrownRoot = framePipelineArtifactTree(prefix: "FramePipeline008", childCount: 12)
    let departedIdentity = testIdentity("FramePipeline008", "Root", "Child[10]")

    let large = framePipelineArtifacts(root: largeRoot, rasterLine: "large")
    state.storeCommittedFrame(large, baselinePlacedTree: large.placedTree, proposal: proposal)
    #expect(state.memoryMetricSnapshot.count == 25)
    #expect(state.memoryMetricSnapshot.detail?["resolved"] == 25)

    let small = framePipelineArtifacts(root: smallRoot, rasterLine: "small")
    state.storeCommittedFrame(small, baselinePlacedTree: small.placedTree, proposal: proposal)
    let afterShrink = state.memoryMetricSnapshot
    #expect(afterShrink.count == 3)
    #expect(afterShrink.detail?["resolved"] == 3)
    #expect(
      state.input(invalidatedIdentities: []).retainedLayout.resolvedNode(for: departedIdentity)
        == nil
    )

    let regrown = framePipelineArtifacts(root: regrownRoot, rasterLine: "regrown")
    state.storeCommittedFrame(regrown, baselinePlacedTree: regrown.placedTree, proposal: proposal)
    let afterRegrow = state.memoryMetricSnapshot
    #expect(afterRegrow.count == 13)
    #expect(afterRegrow.detail?["resolved"] == 13)
    _ = try #require(
      state.input(invalidatedIdentities: []).retainedLayout.resolvedNode(for: departedIdentity)
    )
  }
}

// MARK: - Attempt 009: latest drawn-identity generation

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 009 drawn identities replace instead of accumulate")
  func framePipeline009DrawnIdentitiesReplaceInsteadOfAccumulate() {
    // Hypothesis: committed visibility can union across generations, causing
    // later offscreen-elision checks to treat long-departed nodes as visible.
    let state = FrameTailRetainedState()
    let root = framePipelineArtifactTree(prefix: "FramePipeline009", childCount: 3)
    let proposal = ProposedSize(width: 12, height: 3)
    let firstIdentity = root.children[0].identity
    let secondIdentity = root.children[1].identity
    let thirdIdentity = root.children[2].identity

    let first = framePipelineArtifacts(
      root: root,
      rasterLine: "first",
      drawnIdentities: [firstIdentity, secondIdentity]
    )
    state.storeCommittedFrame(first, baselinePlacedTree: first.placedTree, proposal: proposal)
    #expect(state.previousDrawnIdentities == [firstIdentity, secondIdentity])

    let second = framePipelineArtifacts(
      root: root,
      rasterLine: "second",
      drawnIdentities: [secondIdentity, thirdIdentity]
    )
    state.storeCommittedFrame(second, baselinePlacedTree: second.placedTree, proposal: proposal)
    #expect(state.previousDrawnIdentities == [secondIdentity, thirdIdentity])
    #expect(!state.previousDrawnIdentities.contains(firstIdentity))

    let third = framePipelineArtifacts(
      root: root,
      rasterLine: "third",
      drawnIdentities: [thirdIdentity]
    )
    state.storeCommittedFrame(third, baselinePlacedTree: third.placedTree, proposal: proposal)
    #expect(state.previousDrawnIdentities == [thirdIdentity])
  }
}

// MARK: - Attempt 010: completed candidate cannot become retained baseline

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 010 uncommitted candidate leaves committed baseline isolated")
  func framePipeline010UncommittedCandidateLeavesCommittedBaselineIsolated() async {
    // Hypothesis: rendering and previewing a completed candidate can publish
    // its raster or layout baseline before ordered commit chooses its outcome.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("FramePipeline010", "Root")
    let proposal = ProposedSize(width: 36, height: 4)
    let committed = renderer.render(
      FramePipelineSiblingView(first: "committed-a", second: "committed-b"),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    let committedInput = renderer.frameTailRenderer.retainedInput(invalidatedIdentities: [])
    let committedDrawn = renderer.frameTailRenderer.previousDrawnIdentities
    let committedMetric = renderer.frameTailRenderer.memoryMetricSnapshot

    let draft = renderer.prepareFrameHeadForCancellationTesting(
      FramePipelineSiblingView(
        first: "candidate-is-much-wider-than-committed",
        second: "candidate-b"
      ),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    _ = await renderer.previewCompletedFrameCandidateForTesting(draft)

    let whileUncommitted = renderer.frameTailRenderer.retainedInput(invalidatedIdentities: [])
    #expect(whileUncommitted.previousRasterSurface == committed.rasterSurface)
    #expect(whileUncommitted.previousRasterSurface == committedInput.previousRasterSurface)
    #expect(renderer.frameTailRenderer.previousDrawnIdentities == committedDrawn)
    #expect(renderer.frameTailRenderer.memoryMetricSnapshot == committedMetric)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    let afterAbort = renderer.frameTailRenderer.retainedInput(invalidatedIdentities: [])
    #expect(afterAbort.previousRasterSurface == committed.rasterSurface)
    #expect(renderer.frameTailRenderer.previousDrawnIdentities == committedDrawn)

    let rerendered = renderer.render(
      FramePipelineSiblingView(first: "committed-a", second: "committed-b"),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    #expect(rerendered.rasterSurface == committed.rasterSurface)
  }
}

// MARK: - Attempt 011: lifecycle reappearance after steady and removal

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 011 lifecycle owner reappears after steady removal cycle")
  func framePipeline011LifecycleOwnerReappearsAfterSteadyRemovalCycle() {
    // Hypothesis: the commit planner can preserve the first lifetime in its
    // lifecycle baseline and suppress appear when the same identity returns.
    let graph = ViewGraph()
    let empty = framePipelineLifecycleTree(prefix: "FramePipeline011", includesLeaf: false)
    let live = framePipelineLifecycleTree(prefix: "FramePipeline011", includesLeaf: true)
    _ = graph.applySnapshot(empty)

    let firstAppear = framePipelinePlan(graph: graph, resolved: live)
    let steady = framePipelinePlan(graph: graph, resolved: live)
    let disappear = framePipelinePlan(graph: graph, resolved: empty)
    let secondAppear = framePipelinePlan(graph: graph, resolved: live)

    #expect(firstAppear.lifecycle.map(\.operation) == [.appear(handlerIDs: ["appear"])])
    #expect(steady.lifecycle.isEmpty)
    #expect(disappear.lifecycle.map(\.operation) == [.disappear(handlerIDs: ["disappear"])])
    #expect(secondAppear.lifecycle.map(\.operation) == [.appear(handlerIDs: ["appear"])])
  }
}

private func framePipelineLifecycleTree(
  prefix: String,
  includesLeaf: Bool,
  task: TaskDescriptor? = nil,
  siblingTask: TaskDescriptor? = nil
) -> ResolvedNode {
  var children: [ResolvedNode] = []
  if includesLeaf {
    children.append(
      ResolvedNode(
        identity: testIdentity(prefix, "Root", "Leaf"),
        kind: .view("FramePipelineLifecycleLeaf"),
        lifecycleMetadata: .init(
          appearHandlerIDs: ["appear"],
          disappearHandlerIDs: ["disappear"],
          tasks: task.map { [$0] } ?? []
        )
      )
    )
  }
  if let siblingTask {
    children.append(
      ResolvedNode(
        identity: testIdentity(prefix, "Root", "Sibling"),
        kind: .view("FramePipelineLifecycleSibling"),
        lifecycleMetadata: .init(
          appearHandlerIDs: ["sibling-appear"],
          disappearHandlerIDs: ["sibling-disappear"],
          tasks: [siblingTask]
        )
      )
    )
  }
  return ResolvedNode(
    identity: testIdentity(prefix, "Root"),
    kind: .root,
    children: children
  )
}

@MainActor
private func framePipelinePlan(
  graph: ViewGraph,
  resolved: ResolvedNode,
  placed: PlacedNode? = nil
) -> CommitPlan {
  let lifecycleEvents = graph.applySnapshot(
    resolved,
    placed: placed?.viewportVisibilitySummary
  )
  return CommitPlanner().plan(
    resolved: resolved,
    placed: placed,
    semantics: .init(),
    lifecycleEvents: lifecycleEvents
  )
}

// MARK: - Attempt 012: task descriptor round trip

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 012 task descriptor A B A restarts exact lifetime")
  func framePipeline012TaskDescriptorABARestartsExactLifetime() {
    // Hypothesis: commit-plan task diffing can remember that descriptor A ran
    // once and suppress its restart after an intervening descriptor B.
    let graph = ViewGraph()
    let taskA = TaskDescriptor(id: "task-A", priority: .medium)
    let taskB = TaskDescriptor(id: "task-B", priority: .high)
    let empty = framePipelineLifecycleTree(prefix: "FramePipeline012", includesLeaf: false)
    let treeA = framePipelineLifecycleTree(
      prefix: "FramePipeline012",
      includesLeaf: true,
      task: taskA
    )
    let treeB = framePipelineLifecycleTree(
      prefix: "FramePipeline012",
      includesLeaf: true,
      task: taskB
    )
    _ = graph.applySnapshot(empty)
    _ = framePipelinePlan(graph: graph, resolved: treeA)

    let toB = framePipelinePlan(graph: graph, resolved: treeB)
    let backToA = framePipelinePlan(graph: graph, resolved: treeA)
    let steadyA = framePipelinePlan(graph: graph, resolved: treeA)

    #expect(
      toB.lifecycle.map(\.operation) == [
        .taskCancel(taskA),
        .taskStart(taskB),
      ]
    )
    #expect(
      backToA.lifecycle.map(\.operation) == [
        .taskCancel(taskB),
        .taskStart(taskA),
      ]
    )
    #expect(steadyA.lifecycle.isEmpty)
  }
}

// MARK: - Attempt 013: viewport visibility lifecycle round trip

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 013 visible offscreen visible restarts lifecycle")
  func framePipeline013VisibleOffscreenVisibleRestartsLifecycle() {
    // Hypothesis: viewport lifecycle state can retain the offscreen generation
    // and omit appear/task-start when the same resolved owner becomes visible.
    let graph = ViewGraph()
    let task = TaskDescriptor(id: "viewport-task", priority: .medium)
    let resolved = framePipelineIndexedLifecycleResolved(prefix: "FramePipeline013")
    let visible = framePipelineIndexedLifecyclePlaced(
      prefix: "FramePipeline013",
      includesLeaf: true,
      task: task
    )
    let hidden = framePipelineIndexedLifecyclePlaced(
      prefix: "FramePipeline013",
      includesLeaf: false,
      task: task
    )

    let firstVisible = framePipelinePlan(graph: graph, resolved: resolved, placed: visible)
    let offscreen = framePipelinePlan(graph: graph, resolved: resolved, placed: hidden)
    let visibleAgain = framePipelinePlan(graph: graph, resolved: resolved, placed: visible)

    #expect(
      firstVisible.lifecycle.map(\.operation) == [
        .appear(handlerIDs: ["appear"]),
        .taskStart(task),
      ]
    )
    #expect(
      offscreen.lifecycle.map(\.operation) == [
        .taskCancel(task),
        .disappear(handlerIDs: ["disappear"]),
      ]
    )
    #expect(
      visibleAgain.lifecycle.map(\.operation) == [
        .appear(handlerIDs: ["appear"]),
        .taskStart(task),
      ]
    )
  }
}

private func framePipelineIndexedLifecycleResolved(prefix: String) -> ResolvedNode {
  let lazyIdentity = testIdentity(prefix, "Root", "Lazy")
  return ResolvedNode(
    identity: testIdentity(prefix, "Root"),
    kind: .root,
    children: [
      ResolvedNode(
        identity: lazyIdentity,
        kind: .view("LazyVStack"),
        layoutBehavior: .lazyStack(
          axis: .vertical,
          spacing: 0,
          horizontalAlignment: .leading,
          verticalAlignment: .center
        ),
        indexedChildSource: FramePipelineEmptyIndexedChildSource(identityRoot: lazyIdentity)
      )
    ]
  )
}

private func framePipelineIndexedLifecyclePlaced(
  prefix: String,
  includesLeaf: Bool,
  task: TaskDescriptor
) -> PlacedNode {
  let lazyIdentity = testIdentity(prefix, "Root", "Lazy")
  let leaf = PlacedNode(
    identity: testIdentity(prefix, "Root", "Lazy", "ID[0]"),
    bounds: .init(origin: .zero, size: .init(width: 8, height: 1)),
    lifecycleMetadata: .init(
      appearHandlerIDs: ["appear"],
      disappearHandlerIDs: ["disappear"],
      tasks: [task]
    )
  )
  return PlacedNode(
    identity: testIdentity(prefix, "Root"),
    kind: .root,
    bounds: .init(origin: .zero, size: .init(width: 8, height: 1)),
    children: [
      PlacedNode(
        identity: lazyIdentity,
        kind: .view("LazyVStack"),
        bounds: .init(origin: .zero, size: .init(width: 8, height: 1)),
        children: includesLeaf ? [leaf] : [],
        semanticRole: .container
      )
    ],
    semanticRole: .container
  )
}

private struct FramePipelineEmptyIndexedChildSource: IndexedChildSource {
  let count = 0
  let identityRoot: Identity
  let measurementSignature = "frame-pipeline-empty"

  func child(at _: Int) -> ResolvedNode {
    preconditionFailure("No indexed children should be materialized.")
  }
}

// MARK: - Attempt 014: survivor restart around sibling departure

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 014 sibling removal orders survivor task restart safely")
  func framePipeline014SiblingRemovalOrdersSurvivorTaskRestartSafely() {
    // Hypothesis: combining a departed owner with a stable sibling's task
    // replacement can start the sibling before all old-generation work cancels.
    let graph = ViewGraph()
    let departedTask = TaskDescriptor(id: "departed", priority: .low)
    let survivorOldTask = TaskDescriptor(id: "survivor-old", priority: .medium)
    let survivorNewTask = TaskDescriptor(id: "survivor-new", priority: .high)
    let previous = framePipelineLifecycleTree(
      prefix: "FramePipeline014",
      includesLeaf: true,
      task: departedTask,
      siblingTask: survivorOldTask
    )
    let next = framePipelineLifecycleTree(
      prefix: "FramePipeline014",
      includesLeaf: false,
      siblingTask: survivorNewTask
    )
    _ = graph.applySnapshot(previous)

    let plan = framePipelinePlan(graph: graph, resolved: next)
    let leafIdentity = testIdentity("FramePipeline014", "Root", "Leaf")
    let siblingIdentity = testIdentity("FramePipeline014", "Root", "Sibling")

    #expect(
      plan.lifecycle.map(\.operation) == [
        .taskCancel(survivorOldTask),
        .taskCancel(departedTask),
        .disappear(handlerIDs: ["disappear"]),
        .taskStart(survivorNewTask),
      ]
    )
    #expect(
      plan.lifecycle.map(\.identity) == [
        siblingIdentity,
        leafIdentity,
        leafIdentity,
        siblingIdentity,
      ]
    )
  }
}

// MARK: - Attempt 015: preview and commit after lifecycle churn

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 015 preview plan matches commit after many generations")
  func framePipeline015PreviewPlanMatchesCommitAfterManyGenerations() async {
    // Hypothesis: candidate preview can be computed from an older lifecycle
    // baseline after repeated prior commits and diverge from ordered commit.
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("FramePipeline015", "Root")
    let proposal = ProposedSize(width: 32, height: 5)

    _ = renderer.render(
      FramePipelineCommitPlanView(generation: 0, showsExtra: false),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    for generation in 1...8 {
      _ = renderer.render(
        FramePipelineCommitPlanView(
          generation: generation,
          showsExtra: generation.isMultiple(of: 2)
        ),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [rootIdentity]
        ),
        proposal: proposal
      )
    }

    let draft = renderer.prepareFrameHeadForCancellationTesting(
      FramePipelineCommitPlanView(generation: 9, showsExtra: true),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    let comparison = await renderer.commitCompletedFrameCandidateForTesting(draft)

    #expect(comparison.previewCommit == comparison.committedCommit)
    #expect(comparison.committedArtifacts.commitPlan == comparison.committedCommit)
    #expect(
      comparison.committedCommit.lifecycle.contains {
        if case .taskStart = $0.operation { true } else { false }
      }
    )
    #expect(comparison.committedArtifacts.rasterSurface.lines.contains("generation 9"))
  }
}

@MainActor
private struct FramePipelineCommitPlanView: View {
  let generation: Int
  let showsExtra: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("generation \(generation)")
        .task(id: generation) {}
      if showsExtra {
        Text("extra \(generation)")
          .onAppear {}
          .onDisappear {}
      }
    }
  }
}

// MARK: - Attempt 016: stale candidate preserves sibling commit products

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 016 stale candidate skip preserves sibling products")
  func framePipeline016StaleCandidateSkipPreservesSiblingProducts() async {
    // Hypothesis: the stale-baseline guard can preserve graph state but still
    // rewind a sibling commit's retained raster, visibility, or index products.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("FramePipeline016", "Root")
    let proposal = ProposedSize(width: 40, height: 4)
    _ = renderer.render(
      FramePipelineSiblingView(first: "baseline-a", second: "baseline-b"),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    let staleDraft = renderer.prepareFrameHeadForCancellationTesting(
      FramePipelineSiblingView(first: "stale-a", second: "stale-b"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    let sibling = renderer.render(
      FramePipelineSiblingView(first: "sibling-latest-a", second: "sibling-latest-b"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    let committedGraph = renderer.viewGraph.debugTotalStateSnapshot()
    let committedInput = renderer.frameTailRenderer.retainedInput(invalidatedIdentities: [])
    let committedDrawn = renderer.frameTailRenderer.previousDrawnIdentities
    let committedMetric = renderer.frameTailRenderer.memoryMetricSnapshot

    let skipped = await renderer.resolveCompletedFrameCandidateForTesting(staleDraft)

    #expect(skipped)
    #expect(renderer.viewGraph.debugTotalStateSnapshot() == committedGraph)
    #expect(
      renderer.frameTailRenderer.retainedInput(invalidatedIdentities: []).previousRasterSurface
        == committedInput.previousRasterSurface
    )
    #expect(
      renderer.frameTailRenderer.retainedInput(invalidatedIdentities: []).previousRasterSurface
        == sibling.rasterSurface
    )
    #expect(renderer.frameTailRenderer.previousDrawnIdentities == committedDrawn)
    #expect(renderer.frameTailRenderer.memoryMetricSnapshot == committedMetric)

    let replay = renderer.render(
      FramePipelineSiblingView(first: "sibling-latest-a", second: "sibling-latest-b"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    #expect(replay.rasterSurface == sibling.rasterSurface)
  }
}

// MARK: - Attempt 017: consecutive stale candidates

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 017 consecutive stale candidates preserve one latest commit")
  func framePipeline017ConsecutiveStaleCandidatesPreserveOneLatestCommit() async {
    // Hypothesis: discarding the first stale candidate can perturb checkpoint
    // state so a second stale discard restores the original, older baseline.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("FramePipeline017", "Root")
    let proposal = ProposedSize(width: 42, height: 4)
    _ = renderer.render(
      FramePipelineSiblingView(first: "baseline-a", second: "baseline-b"),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    let firstStale = renderer.prepareFrameHeadForCancellationTesting(
      FramePipelineSiblingView(first: "stale-first-a", second: "stale-first-b"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    let secondStale = renderer.prepareFrameHeadForCancellationTesting(
      FramePipelineSiblingView(first: "stale-second-a", second: "stale-second-b"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    let latest = renderer.render(
      FramePipelineSiblingView(first: "latest-a", second: "latest-b"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    let committedGraph = renderer.viewGraph.debugTotalStateSnapshot()
    let committedDrawn = renderer.frameTailRenderer.previousDrawnIdentities
    let committedMetric = renderer.frameTailRenderer.memoryMetricSnapshot

    let skippedFirst = await renderer.resolveCompletedFrameCandidateForTesting(firstStale)
    #expect(skippedFirst)
    #expect(renderer.viewGraph.debugTotalStateSnapshot() == committedGraph)
    #expect(
      renderer.frameTailRenderer.retainedInput(invalidatedIdentities: []).previousRasterSurface
        == latest.rasterSurface
    )

    let skippedSecond = await renderer.resolveCompletedFrameCandidateForTesting(secondStale)
    #expect(skippedSecond)
    #expect(renderer.viewGraph.debugTotalStateSnapshot() == committedGraph)
    #expect(
      renderer.frameTailRenderer.retainedInput(invalidatedIdentities: []).previousRasterSurface
        == latest.rasterSurface
    )
    #expect(renderer.frameTailRenderer.previousDrawnIdentities == committedDrawn)
    #expect(renderer.frameTailRenderer.memoryMetricSnapshot == committedMetric)

    let replay = renderer.render(
      FramePipelineSiblingView(first: "latest-a", second: "latest-b"),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )
    #expect(replay.rasterSurface == latest.rasterSurface)
  }
}

// MARK: - Attempt 018: completed-drop progress run resets

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 018 progress commit resets completed drop run")
  func framePipeline018ProgressCommitResetsCompletedDropRun() async throws {
    // Hypothesis: the forward-progress commit can leave the drop counter at its
    // limit, forcing every later superseded visual frame to commit forever.
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("FramePipeline018", "Root")
    let proposal = ProposedSize(width: 30, height: 3)
    _ = renderer.render(
      FramePipelineVisualOnlyView(value: 0),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    func renderStale(_ value: Int) async -> CancellableRenderOutcome {
      await renderer.renderAsyncCancellable(
        FramePipelineVisualOnlyView(value: value),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: [rootIdentity]
        ),
        proposal: proposal,
        newestDesiredGeneration: { RenderGeneration(10_000) },
        completedFramePolicy: .dropCompletedVisualOnly,
        shouldCancelQueued: { false }
      )
    }

    let first = await renderStale(1)
    #expect(first.tailJobState == .droppedCompleted)
    #expect(first.completedFrameDropDecision?.action == .dropVisualOnly)
    #expect(renderer.visualOnlyDropRun.count == 1)

    let second = await renderStale(2)
    #expect(second.tailJobState == .droppedCompleted)
    #expect(second.completedFrameDropDecision?.action == .dropVisualOnly)
    #expect(renderer.visualOnlyDropRun.count == 2)

    let forced = await renderStale(3)
    #expect(forced.tailJobState == .completed)
    #expect(forced.completedFrameDropDecision?.action == .commitOrdered)
    #expect(forced.completedFrameDropDecision?.reconciliation.blockReason == .progressStarvation)
    _ = try #require(forced.artifacts)
    #expect(renderer.visualOnlyDropRun.count == 0)

    let afterProgress = await renderStale(4)
    #expect(afterProgress.tailJobState == .droppedCompleted)
    #expect(afterProgress.completedFrameDropDecision?.action == .dropVisualOnly)
    #expect(renderer.visualOnlyDropRun.count == 1)
  }
}

@MainActor
private struct FramePipelineVisualOnlyView: View {
  let value: Int

  var body: some View {
    Text("visual \(value)")
      .id(testIdentity("FramePipelineVisualOnly", "\(value)"))
  }
}

// MARK: - Attempt 019: redundant handler exemption is narrow

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 019 redundant handler exemption preserves preference blocker")
  func framePipeline019RedundantHandlerExemptionPreservesPreferenceBlocker() {
    // Hypothesis: exempting handler installation as redundant can subtract the
    // whole runtime-registration impact and accidentally erase preferences.
    let root = framePipelineArtifactTree(prefix: "FramePipeline019", childCount: 1)
    let commitPlan = CommitPlan(
      handlerInstallations: [
        HandlerInstallation(handlerID: testRoute("FramePipeline019", "Button"))
      ]
    )
    let diagnostics = FrameDiagnostics(
      drop: .init(eligibilityBlockers: [.preferenceObservationDelta])
    )
    let artifacts = framePipelineArtifacts(
      root: root,
      rasterLine: "preference-blocker",
      commitPlan: commitPlan,
      diagnostics: diagnostics
    )

    let eligibility = FrameDropEligibility.classify(
      .init(
        artifacts: artifacts,
        hasCompleteBarrierSignals: true,
        redundantHandlerInstallationsAreVisualOnly: true
      )
    )
    let decision = CompletedFrameDropDecision.dropVisualOnly(eligibility: eligibility)

    #expect(eligibility.blockers == [.preferenceObservationDelta])
    #expect(eligibility.impact.preferences)
    #expect(!eligibility.impact.runtimeRegistrations)
    #expect(decision.action == .blocked)
    #expect(decision.reconciliation.blockers == [.preferenceObservationDelta])
  }
}

// MARK: - Attempt 020: blocker product and reconciliation closure

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 020 blocker categories survive impact reconciliation")
  func framePipeline020BlockerCategoriesSurviveImpactReconciliation() {
    // Hypothesis: folding several effect categories into CompletedFrameImpact
    // can overwrite a prior category and omit its blocker from reconciliation.
    let blockers: Set<FrameDropEligibility.Blocker> = [
      .lifecycleAppear,
      .handlerInstallations,
      .focusGraph,
      .scrollSync,
      .preferenceObservationDelta,
      .animationCompletion,
      .workerCustomLayoutCacheUpdate,
      .retainedRasterBaseline,
      .graphicsReplay,
      .diagnosticsFullRecord,
    ]
    let eligibility = FrameDropEligibility(blockers: blockers)
    let decision = CompletedFrameDropDecision.dropVisualOnly(eligibility: eligibility)

    #expect(eligibility.blockers == blockers)
    #expect(eligibility.impact.lifecycle)
    #expect(eligibility.impact.runtimeRegistrations)
    #expect(eligibility.impact.focus)
    #expect(eligibility.impact.scroll)
    #expect(eligibility.impact.preferences)
    #expect(eligibility.impact.animation)
    #expect(eligibility.impact.workerOrCache)
    #expect(eligibility.impact.retainedBaselines)
    #expect(eligibility.impact.presentationRecovery)
    #expect(eligibility.impact.diagnostics)
    #expect(!eligibility.impact.isVisualOnly)
    #expect(decision.action == .blocked)
    #expect(decision.eligibility == .mustCommit(blockers: blockers))
    #expect(decision.reconciliation.blockers == blockers)
    #expect(decision.reconciliation.blockReason == .dropEligibilityBlockers)
    #expect(!decision.canSkipCompletedFrame)
  }
}

// MARK: - Attempt 021: cancelled replay respects newer animation

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 021 cancelled replay preserves newer animation request")
  func framePipeline021CancelledReplayPreservesNewerAnimationRequest() throws {
    // Hypothesis: replaying a cancelled frame after a newer explicit request
    // can overwrite the newer animation transaction with stale intent.
    let scheduler = FrameScheduler()
    let newerIdentity = testIdentity("FramePipeline021", "Newer")
    let cancelledIdentity = testIdentity("FramePipeline021", "Cancelled")
    let newerBatch = AnimationBatchID(21)
    scheduler.requestInvalidation(
      of: [newerIdentity],
      animation: .disabled,
      batchID: newerBatch
    )
    scheduler.replayCancelledFrameIntent(
      framePipelineScheduledFrame(
        identities: [cancelledIdentity],
        animation: .animate(AnyHashableSendable("stale-animation")),
        batchID: nil
      )
    )

    let frame = try #require(
      scheduler.consumeReadyFrame(
        at: MonotonicInstant(offset: .seconds(70_021)),
        armedBefore: scheduler.deadlineArmCut
      )
    )
    #expect(frame.animationRequest == .disabled)
    #expect(frame.animationBatchID == newerBatch)
    #expect(frame.invalidatedIdentities == [newerIdentity, cancelledIdentity])
  }
}

private func framePipelineScheduledFrame(
  causes: Set<WakeCause> = [.invalidation],
  identities: Set<Identity> = [],
  animation: AnimationRequest = .inherit,
  batchID: AnimationBatchID? = nil,
  supersededBatchIDs: [AnimationBatchID] = []
) -> ScheduledFrame {
  ScheduledFrame(
    causes: causes,
    invalidatedIdentities: identities,
    signalNames: [],
    externalReasons: [],
    triggeredDeadline: nil,
    nextDeadline: nil,
    animationRequest: animation,
    animationBatchID: batchID,
    supersededAnimationBatchIDs: supersededBatchIDs
  )
}

// MARK: - Attempt 022: replay deduplicates superseded batches

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 022 duplicate replay deduplicates superseded batches")
  func framePipeline022DuplicateReplayDeduplicatesSupersededBatches() throws {
    // Hypothesis: retrying cancellation replay can append the same displaced
    // batch repeatedly, firing or parking one completion more than once.
    let scheduler = FrameScheduler()
    let newerBatch = AnimationBatchID(220)
    let cancelledBatch = AnimationBatchID(221)
    let earlierSuperseded = AnimationBatchID(222)
    scheduler.requestInvalidation(
      of: [testIdentity("FramePipeline022", "Newer")],
      animation: .disabled,
      batchID: newerBatch
    )
    let cancelled = framePipelineScheduledFrame(
      identities: [testIdentity("FramePipeline022", "Cancelled")],
      animation: .disabled,
      batchID: cancelledBatch,
      supersededBatchIDs: [earlierSuperseded]
    )

    scheduler.replayCancelledFrameIntent(cancelled)
    scheduler.replayCancelledFrameIntent(cancelled)

    let frame = try #require(
      scheduler.consumeReadyFrame(
        at: MonotonicInstant(offset: .seconds(70_022)),
        armedBefore: scheduler.deadlineArmCut
      )
    )
    #expect(frame.animationBatchID == newerBatch)
    #expect(frame.supersededAnimationBatchIDs == [cancelledBatch, earlierSuperseded])
    #expect(Set(frame.supersededAnimationBatchIDs).count == 2)
  }
}

// MARK: - Attempt 023: replay unions old and new dirty identities

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 023 cancelled replay unions old and new invalidations")
  func framePipeline023CancelledReplayUnionsOldAndNewInvalidations() throws {
    // Hypothesis: cancellation replay can replace, rather than union with, a
    // newer dirty set when the two generations share one identity.
    let scheduler = FrameScheduler()
    let shared = testIdentity("FramePipeline023", "Shared")
    let oldOnly = testIdentity("FramePipeline023", "OldOnly")
    let newOnly = testIdentity("FramePipeline023", "NewOnly")
    scheduler.requestInvalidation(of: [shared])
    scheduler.requestInvalidation(of: [newOnly])

    scheduler.replayCancelledFrameIntent(
      framePipelineScheduledFrame(identities: [shared, oldOnly])
    )

    let frame = try #require(
      scheduler.consumeReadyFrame(
        at: MonotonicInstant(offset: .seconds(70_023)),
        armedBefore: scheduler.deadlineArmCut
      )
    )
    #expect(frame.invalidatedIdentities == [shared, oldOnly, newOnly])
    #expect(frame.causes == [.invalidation])
    #expect(frame.intentRequestCount == 3)
    #expect(scheduler.consumeReadyFrame() == nil)
  }
}

// MARK: - Attempt 024: reset does not reopen an old deadline cut

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 024 pre-reset cut withholds post-reset deadline set")
  func framePipeline024PreResetCutWithholdsPostResetDeadlineSet() throws {
    // Hypothesis: resetting scheduler storage can reuse arm ordinals so an old
    // drain cut consumes newly armed due deadlines along with an invalidation.
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(70_024))
    scheduler.requestDeadline(base)
    let cutBeforeReset = scheduler.deadlineArmCut
    scheduler.reset()

    let firstDeadline = base.advanced(by: .milliseconds(1))
    let secondDeadline = base.advanced(by: .milliseconds(2))
    scheduler.requestDeadline(firstDeadline)
    scheduler.requestDeadline(secondDeadline)
    scheduler.requestInvalidation(of: [testIdentity("FramePipeline024", "Dirty")])
    let now = base.advanced(by: .milliseconds(3))

    let invalidationOnly = try #require(
      scheduler.consumeReadyFrame(at: now, armedBefore: cutBeforeReset)
    )
    #expect(invalidationOnly.causes == [.invalidation])
    #expect(invalidationOnly.triggeredDeadline == nil)
    #expect(invalidationOnly.nextDeadline == firstDeadline)

    let deadlineFrame = try #require(
      scheduler.consumeReadyFrame(at: now, armedBefore: scheduler.deadlineArmCut)
    )
    #expect(deadlineFrame.causes == [.deadline])
    #expect(deadlineFrame.triggeredDeadline == secondDeadline)
    #expect(deadlineFrame.nextDeadline == nil)
  }
}

// MARK: - Attempt 025: sorted due deadlines respect arm cut

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 025 earlier post-cut deadline survives pre-cut drain")
  func framePipeline025EarlierPostCutDeadlineSurvivesPreCutDrain() throws {
    // Hypothesis: a newly armed deadline sorted ahead of older entries can be
    // deleted when a cut drains later-in-time, pre-cut deadlines around it.
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(70_025))
    let preCutFirst = base.advanced(by: .milliseconds(20))
    let preCutSecond = base.advanced(by: .milliseconds(30))
    let postCutEarlier = base.advanced(by: .milliseconds(10))
    scheduler.requestDeadline(preCutFirst)
    scheduler.requestDeadline(preCutSecond)
    let cut = scheduler.deadlineArmCut
    scheduler.requestDeadline(postCutEarlier)
    let now = base.advanced(by: .milliseconds(40))

    let firstDrain = try #require(
      scheduler.consumeReadyFrame(at: now, armedBefore: cut)
    )
    #expect(firstDrain.causes == [.deadline])
    #expect(firstDrain.triggeredDeadline == preCutSecond)
    #expect(firstDrain.nextDeadline == postCutEarlier)
    #expect(scheduler.hasPendingFrame(at: now))
    #expect(scheduler.nextWakeInstant(after: now) == now)

    let nextDrain = try #require(
      scheduler.consumeReadyFrame(at: now, armedBefore: scheduler.deadlineArmCut)
    )
    #expect(nextDrain.causes == [.deadline])
    #expect(nextDrain.triggeredDeadline == postCutEarlier)
    #expect(nextDrain.nextDeadline == nil)
    #expect(!scheduler.hasPendingFrame(at: now))
  }
}

// MARK: - Attempt 026: replay ignores non-invalidation work

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 026 cancelled non-invalidation causes do not replay")
  func framePipeline026CancelledNonInvalidationCausesDoNotReplay() {
    // Hypothesis: replay can synthesize a coarse invalidation from cancelled
    // input, signal, external, or deadline causes that carry no graph intent.
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(70_026))
    let cancelled = ScheduledFrame(
      causes: [.input, .signal, .external, .deadline],
      invalidatedIdentities: [],
      signalNames: ["SIGWINCH"],
      externalReasons: ["host-resize"],
      triggeredDeadline: base,
      nextDeadline: base.advanced(by: .seconds(1))
    )

    scheduler.replayCancelledFrameIntent(cancelled)

    #expect(!scheduler.hasPendingFrame(at: base.advanced(by: .seconds(2))))
    #expect(scheduler.nextWakeInstant(after: base) == nil)
    #expect(
      scheduler.consumeReadyFrame(
        at: base.advanced(by: .seconds(2)),
        armedBefore: scheduler.deadlineArmCut
      ) == nil
    )
  }
}

// MARK: - Attempt 027: terminal cancellation remains sticky for late observers

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 027 terminal cancellation survives late observer fanout")
  func framePipeline027TerminalCancellationSurvivesLateObserverFanout() async {
    // Hypothesis: reading a terminal cancellation can consume or reset it, so
    // later coordinator observers may see queued state or become stranded.
    let token = FrameTailJobCancellationToken()
    #expect(token.cancelBeforeStart())
    #expect(await token.waitUntilLeavesQueue() == .cancelledBeforeStart)

    let lateObservers = (0..<64).map { _ in
      Task { await token.waitUntilLeavesQueue() }
    }
    for observer in lateObservers {
      #expect(await observer.value == .cancelledBeforeStart)
    }

    #expect(token.currentState == .cancelledBeforeStart)
    #expect(await token.waitUntilLeavesQueue() == .cancelledBeforeStart)
    #expect(!token.cancelBeforeStart())
    #expect(!token.markStarted())
  }
}

// MARK: - Attempt 028: late cancellation cannot rewind started work

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 028 started tail rejects late cancellation")
  func framePipeline028StartedTailRejectsLateCancellation() async {
    // Hypothesis: a cancel signal racing just after worker start can move the
    // token back to cancelled-before-start and let two coordinator arms finish.
    let token = FrameTailJobCancellationToken()
    #expect(token.markStarted())
    #expect(token.currentState == .started)

    let observer = Task { await token.waitUntilLeavesQueue() }
    #expect(!token.cancelBeforeStart())
    #expect(token.currentState == .started)
    #expect(await observer.value == .started)

    #expect(token.markStarted())
    #expect(token.currentState == .started)
    token.markCompleted()
    token.markCompleted()
    #expect(token.currentState == .completed)
    #expect(!token.cancelBeforeStart())
    #expect(await token.waitUntilLeavesQueue() == .completed)
  }
}

// MARK: - Attempt 029: pre-cancelled observation is local

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 029 pre-cancelled observer leaves token startable")
  func framePipeline029PreCancelledObserverLeavesTokenStartable() async {
    // Hypothesis: a caller cancelled before observing the queued token can
    // mutate shared state and prevent later start or terminal observation.
    let token = FrameTailJobCancellationToken()
    let cancelledObserver = Task { await token.waitUntilLeavesQueue() }

    cancelledObserver.cancel()
    #expect(await cancelledObserver.value == .queued)
    #expect(token.currentState == .queued)

    #expect(token.markStarted())
    #expect(token.currentState == .started)
    #expect(await token.waitUntilLeavesQueue() == .started)

    token.markCompleted()
    #expect(token.currentState == .completed)
    #expect(await token.waitUntilLeavesQueue() == .completed)
  }
}

// MARK: - Attempt 030: moved subtree damages old and new coverage

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 030 moved dirty subtree damages old and new ranges")
  func framePipeline030MovedDirtySubtreeDamagesOldAndNewRanges() throws {
    // Hypothesis: retained damage can follow only the current dirty subtree and
    // leave glyphs painted at its previously committed rows and columns.
    let rootIdentity = testIdentity()
    let dirtyIdentity = testIdentity("FramePipeline030Dirty")
    let cleanIdentity = testIdentity("FramePipeline030Clean")
    let clean = FramePipelineArtifactNode(
      viewNodeID: ViewNodeID(rawValue: 2),
      identity: cleanIdentity,
      bounds: .init(origin: .zero, size: .init(width: 5, height: 1)),
      drawPayload: .text("clean")
    )
    let previousDirty = FramePipelineArtifactNode(
      viewNodeID: ViewNodeID(rawValue: 3),
      identity: dirtyIdentity,
      bounds: .init(origin: .init(x: 2, y: 1), size: .init(width: 4, height: 2)),
      drawPayload: .text("old")
    )
    let currentDirty = FramePipelineArtifactNode(
      viewNodeID: ViewNodeID(rawValue: 3),
      identity: dirtyIdentity,
      bounds: .init(origin: .init(x: 7, y: 4), size: .init(width: 3, height: 2)),
      drawPayload: .text("new")
    )
    let previousRoot = FramePipelineArtifactNode(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: rootIdentity,
      bounds: .init(origin: .zero, size: .init(width: 12, height: 7)),
      children: [clean, previousDirty]
    )
    let currentRoot = FramePipelineArtifactNode(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: rootIdentity,
      bounds: .init(origin: .zero, size: .init(width: 12, height: 7)),
      children: [clean, currentDirty]
    )
    let previous = framePipelineArtifacts(root: previousRoot, rasterLine: "previous")
    let current = framePipelineArtifacts(root: currentRoot, rasterLine: "current")
    let state = FrameTailRetainedState()
    state.storeCommittedFrame(
      previous,
      baselinePlacedTree: previous.placedTree,
      proposal: .init(width: 12, height: 7)
    )
    let retained = state.input(invalidatedIdentities: [dirtyIdentity])
    let retainedIndex = try #require(retained.retainedLayout.previousFrameIndex)
    _ = try #require(retainedIndex.resolvedNode(for: dirtyIdentity))
    _ = try #require(retainedIndex.placedPath(to: dirtyIdentity))

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: rootIdentity,
      placed: current.placedTree,
      retainedLayout: retained.retainedLayout,
      previousSurfaceTopology: retained.previousSurfaceTopology
    )
    let damage = try #require(plan.damage)

    #expect(plan.barriers.isEmpty)
    #expect(
      damage.textRows == [
        .init(row: 1, columnRanges: [2..<6]),
        .init(row: 2, columnRanges: [2..<6]),
        .init(row: 4, columnRanges: [7..<10]),
        .init(row: 5, columnRanges: [7..<10]),
      ]
    )
  }
}

// MARK: - Attempt 031: overlapping sibling damage normalizes

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 031 overlapping dirty siblings merge exact ranges")
  func framePipeline031OverlappingDirtySiblingsMergeExactRanges() throws {
    // Hypothesis: unioning multiple dirty-subtree contributions can preserve
    // duplicate or overlapping spans, producing inconsistent raster culling.
    let rootIdentity = testIdentity()
    let firstIdentity = testIdentity("FramePipeline031First")
    let secondIdentity = testIdentity("FramePipeline031Second")
    let cleanIdentity = testIdentity("FramePipeline031Clean")

    func root(firstPayload: String, secondPayload: String) -> FramePipelineArtifactNode {
      FramePipelineArtifactNode(
        viewNodeID: ViewNodeID(rawValue: 1),
        identity: rootIdentity,
        bounds: .init(origin: .zero, size: .init(width: 12, height: 5)),
        children: [
          FramePipelineArtifactNode(
            viewNodeID: ViewNodeID(rawValue: 2),
            identity: firstIdentity,
            bounds: .init(origin: .init(x: 1, y: 1), size: .init(width: 5, height: 2)),
            drawPayload: .text(firstPayload)
          ),
          FramePipelineArtifactNode(
            viewNodeID: ViewNodeID(rawValue: 3),
            identity: secondIdentity,
            bounds: .init(origin: .init(x: 4, y: 2), size: .init(width: 5, height: 2)),
            drawPayload: .text(secondPayload)
          ),
          FramePipelineArtifactNode(
            viewNodeID: ViewNodeID(rawValue: 4),
            identity: cleanIdentity,
            bounds: .init(origin: .init(x: 0, y: 4), size: .init(width: 5, height: 1)),
            drawPayload: .text("clean")
          ),
        ]
      )
    }

    let previous = framePipelineArtifacts(
      root: root(firstPayload: "old-first", secondPayload: "old-second"),
      rasterLine: "previous"
    )
    let current = framePipelineArtifacts(
      root: root(firstPayload: "new-first", secondPayload: "new-second"),
      rasterLine: "current"
    )
    let state = FrameTailRetainedState()
    state.storeCommittedFrame(
      previous,
      baselinePlacedTree: previous.placedTree,
      proposal: .init(width: 12, height: 5)
    )
    let retained = state.input(invalidatedIdentities: [firstIdentity, secondIdentity])
    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: rootIdentity,
      placed: current.placedTree,
      retainedLayout: retained.retainedLayout,
      previousSurfaceTopology: retained.previousSurfaceTopology
    )
    let damage = try #require(plan.damage)

    #expect(plan.barriers.isEmpty)
    #expect(
      damage.textRows == [
        .init(row: 1, columnRanges: [1..<6]),
        .init(row: 2, columnRanges: [1..<9]),
        .init(row: 3, columnRanges: [4..<9]),
      ]
    )
    #expect(damage.columnRanges(for: 2) == [1..<9])
  }
}

// MARK: - Attempt 032: full-row dominance and diagnostic accounting

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 032 full row dominates partial damage metrics")
  func framePipeline032FullRowDominatesPartialDamageMetrics() {
    // Hypothesis: combining previous/current partial spans with a later full-row
    // contribution can retain hidden spans and undercount diagnostic coverage.
    let graphicsA = testIdentity("FramePipeline032", "GraphicsA")
    let graphicsB = testIdentity("FramePipeline032", "GraphicsB")
    let damage = PresentationDamage(
      textRows: [
        .init(row: 2, columnRanges: [2..<5]),
        .init(row: 1, columnRanges: [1..<4]),
        .init(row: 3, columnRanges: [-3..<2, 2..<4, 8..<8]),
        .init(row: 2),
        .init(row: 1, columnRanges: [3..<8]),
      ],
      graphicsInvalidation: [graphicsA, graphicsB]
    )
    let diagnostics = PresentationDamageDiagnostics(
      damage: damage,
      surfaceWidth: 10
    )

    #expect(
      damage.textRows == [
        .init(row: 1, columnRanges: [1..<8]),
        .init(row: 2),
        .init(row: 3, columnRanges: [0..<4]),
      ]
    )
    #expect(damage.columnRanges(for: 2) == [])
    #expect(diagnostics.textRowCount == 3)
    #expect(diagnostics.rangeAwareTextRowCount == 2)
    #expect(diagnostics.textSpanCount == 3)
    #expect(diagnostics.textCellCount == 21)
    #expect(diagnostics.graphicsInvalidationCount == 2)
    #expect(!diagnostics.requiresFullTextRepaint)
    #expect(!diagnostics.requiresFullGraphicsReplay)
  }
}

// MARK: - Attempt 033: elision uses only latest committed visibility

extension FrameworkStressFramePipelineTests {
  @Test("stress frame pipeline 033 offscreen elision uses latest visible generation")
  func framePipeline033OffscreenElisionUsesLatestVisibleGeneration() {
    // Hypothesis: drawn identities from a departed committed generation can
    // survive in the elision input and force an offscreen deadline to render.
    let state = FrameTailRetainedState()
    let root = framePipelineArtifactTree(prefix: "FramePipeline033", childCount: 2)
    let departed = root.children[0].identity
    let visible = root.children[1].identity
    let proposal = ProposedSize(width: 12, height: 2)

    let first = framePipelineArtifacts(
      root: root,
      rasterLine: "departed-visible",
      drawnIdentities: [departed]
    )
    state.storeCommittedFrame(first, baselinePlacedTree: first.placedTree, proposal: proposal)
    #expect(state.previousDrawnIdentities == [departed])

    let second = framePipelineArtifacts(
      root: root,
      rasterLine: "current-visible",
      drawnIdentities: [visible]
    )
    state.storeCommittedFrame(second, baselinePlacedTree: second.placedTree, proposal: proposal)
    let latestDrawn = state.previousDrawnIdentities
    #expect(latestDrawn == [visible])

    #expect(
      OffscreenFrameElision.shouldElide(
        causes: [.deadline],
        animationRequest: .inherit,
        redrawIdentities: [departed],
        drawnIdentities: latestDrawn
      )
    )
    #expect(
      !OffscreenFrameElision.shouldElide(
        causes: [.deadline],
        animationRequest: .inherit,
        redrawIdentities: [visible],
        drawnIdentities: latestDrawn
      )
    )
  }
}
