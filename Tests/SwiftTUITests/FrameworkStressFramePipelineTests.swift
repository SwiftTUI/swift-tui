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
