import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI text-content stress behavior", .serialized)
struct FrameworkStressTextContentTests {}

@MainActor
private func textContentRetainedAndFresh<Content: View>(
  renderer: DefaultRenderer,
  rootIdentity: Identity,
  generation: Int,
  proposal: ProposedSize,
  content: Content
) -> (retained: RenderSnapshot, fresh: RenderSnapshot) {
  let retained = renderer.render(
    content,
    context: .init(
      identity: rootIdentity,
      invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
    ),
    proposal: proposal
  )
  let fresh = DefaultRenderer().render(
    content,
    context: .init(identity: rootIdentity),
    proposal: proposal
  )
  return (retained, fresh)
}

private func textContentVisibleWidth(_ line: String) -> Int {
  line.reduce(0) { $0 + cellWidth(of: $1) }
}

// MARK: - Attempt 001: pending separator churn

extension FrameworkStressTextContentTests {
  @Test("stress text content 001 pending separators follow current wrapping")
  func textContent001PendingSeparatorsFollowCurrentWrapping() {
    // Hypothesis: word-boundary wrapping can retain a pending multi-space separator from the
    // previous proposal and replay it at the start of a later retained line.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent001")

    for generation in 0..<24 {
      let width = [6, 9, 7, 10][generation % 4]
      let content = generation.isMultiple(of: 2) ? "AA   BBB CC" : "AA BBB   CC"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text(content).textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.lines.allSatisfy { !$0.hasPrefix(" ") })
    }
  }
}
