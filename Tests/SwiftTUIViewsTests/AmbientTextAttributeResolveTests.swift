import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Ambient-propagation contract, Stage 0 (org root
// docs/plans/2026-08-04-001-ambient-propagation-contract-plan.md):
// resolve-level pins for the SwiftUI environment semantics of
// `lineLimit`/`truncationMode`. Verified against real SwiftUI on macOS
// (2026-08-05, ImageRenderer probes): `lineLimit(_: Int?)` is plain
// environment replacement — the innermost write wins and `nil` clears an
// inherited limit. The raw (unclamped) value travels in the environment;
// rendering clamps non-positive limits to one line.
@MainActor
@Suite
struct AmbientTextAttributeResolveTests {
  private func textNodes(in root: ResolvedNode) -> [ResolvedNode] {
    var found: [ResolvedNode] = []
    func walk(_ node: ResolvedNode) {
      if node.kind == .view("Text") {
        found.append(node)
      }
      for child in node.children {
        walk(child)
      }
    }
    walk(root)
    return found
  }

  @Test("container lineLimit stamps every descendant text at resolve time")
  func containerLineLimitStampsDescendantTexts() {
    let resolved = Resolver().resolve(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma")
        Text("one two three")
      }
      .lineLimit(2),
      in: .init(identity: testIdentity("ContainerLimit"))
    )

    let texts = textNodes(in: resolved)
    #expect(texts.count == 2)
    #expect(texts.allSatisfy { $0.layoutMetadata.lineLimit == 2 })
  }

  @Test("the innermost lineLimit write wins over an enclosing one")
  func innermostLineLimitWriteWins() {
    let resolved = Resolver().resolve(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma").lineLimit(5)
      }
      .lineLimit(1),
      in: .init(identity: testIdentity("InnermostWins"))
    )

    #expect(textNodes(in: resolved).first?.layoutMetadata.lineLimit == 5)
  }

  @Test("lineLimit(nil) clears an inherited limit")
  func lineLimitNilClearsInheritedLimit() {
    let resolved = Resolver().resolve(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma").lineLimit(nil)
      }
      .lineLimit(1),
      in: .init(identity: testIdentity("NilClears"))
    )

    let texts = textNodes(in: resolved)
    #expect(texts.count == 1)
    #expect(texts.first?.layoutMetadata.lineLimit == nil)
  }

  @Test("container truncationMode reaches descendant texts, innermost write winning")
  func containerTruncationModeReachesDescendantTexts() {
    let inherited = Resolver().resolve(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma")
      }
      .truncationMode(.head),
      in: .init(identity: testIdentity("TruncationInherits"))
    )
    let overridden = Resolver().resolve(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma").truncationMode(.middle)
      }
      .truncationMode(.head),
      in: .init(identity: testIdentity("TruncationInnermost"))
    )

    let inheritedMode = textNodes(in: inherited).first
      .map { $0.layoutMetadata.textTruncationMode ?? .tail }
    let overriddenMode = textNodes(in: overridden).first
      .map { $0.layoutMetadata.textTruncationMode ?? .tail }
    #expect(inheritedMode == .head)
    #expect(overriddenMode == .middle)
  }

  @Test("a non-positive container lineLimit clamps to one line at the consuming leaf")
  func nonPositiveContainerLineLimitClampsToOneLine() {
    let resolved = Resolver().resolve(
      VStack(alignment: .leading, spacing: 0) {
        Text("alpha beta gamma")
      }
      .lineLimit(0),
      in: .init(identity: testIdentity("NonPositiveClamp"))
    )

    #expect(textNodes(in: resolved).first?.layoutMetadata.lineLimit == 1)
  }
}
