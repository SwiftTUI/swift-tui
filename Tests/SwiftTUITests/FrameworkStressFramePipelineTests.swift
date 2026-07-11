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
      identity: testIdentity(prefix, "Root", "Child[\(index)]"),
      bounds: .init(
        origin: .init(x: 0, y: index),
        size: .init(width: 12, height: 1)
      ),
      drawPayload: .text("child-\(index)")
    )
  }
  return FramePipelineArtifactNode(
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
      identity: node.identity,
      kind: .view("FramePipelineArtifact"),
      children: node.children.map(resolved),
      drawPayload: node.drawPayload,
      intrinsicSize: node.bounds.size
    )
  }

  func measured(_ node: FramePipelineArtifactNode) -> MeasuredNode {
    MeasuredNode(
      identity: node.identity,
      proposal: .init(width: node.bounds.size.width, height: node.bounds.size.height),
      measuredSize: node.bounds.size,
      childMeasurements: node.children.map(measured)
    )
  }

  func placed(_ node: FramePipelineArtifactNode) -> PlacedNode {
    PlacedNode(
      identity: node.identity,
      bounds: node.bounds,
      children: node.children.map(placed),
      drawPayload: node.drawPayload
    )
  }

  func draw(_ node: FramePipelineArtifactNode) -> DrawNode {
    DrawNode(
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
