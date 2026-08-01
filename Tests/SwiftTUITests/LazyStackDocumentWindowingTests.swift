import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Scroll-latency Stage 2 (plan 2026-07-31-002): the document composition —
/// `ScrollView { LazyVStack { ForEach } }` with the wrappers real document
/// apps put around the `ForEach` — must reach windowed measurement. mrkdwn's
/// document pane guards its `ForEach` behind `if let document` and pads the
/// stack; neither may silently push the document onto the exhaustive path.
@MainActor
@Suite(.serialized)
struct LazyStackDocumentWindowingTests {
  @Test("a bare ForEach document windows under the scroll hint")
  func bareForEachDocumentWindows() {
    IndexedChildRealizationProbe.reset()
    _ = DefaultRenderer().render(
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          ForEach(0..<300, id: \.self) { index in
            Text("block \(index)")
          }
        }
      },
      context: .init(identity: testIdentity("BareDocument"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(80), height: .finite(24))
    )
    #expect(
      IndexedChildRealizationProbe.realizedChildCount <= 40,
      "realized \(IndexedChildRealizationProbe.realizedChildCount) of 300 blocks"
    )
  }

  @Test("the mrkdwn-shaped composition (conditional + padding) windows too")
  func conditionalPaddedDocumentWindows() {
    IndexedChildRealizationProbe.reset()
    let document: [Int]? = Array(0..<300)
    _ = DefaultRenderer().render(
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          if let document {
            ForEach(document, id: \.self) { index in
              Text("block \(index)")
            }
          } else {
            Text("Loading…")
          }
        }
        .padding(.init(horizontal: 1, vertical: 1))
      },
      context: .init(
        identity: testIdentity("ConditionalDocument"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(80), height: .finite(24))
    )
    #expect(
      IndexedChildRealizationProbe.realizedChildCount <= 40,
      "realized \(IndexedChildRealizationProbe.realizedChildCount) of 300 blocks"
    )
  }
}
