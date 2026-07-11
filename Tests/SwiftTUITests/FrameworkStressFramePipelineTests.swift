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
