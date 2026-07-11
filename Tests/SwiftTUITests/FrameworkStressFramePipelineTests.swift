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
