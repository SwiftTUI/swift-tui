import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

/// H1 — retained draw extraction must not mispair siblings that share a
/// `ViewNodeID`.
///
/// Two siblings under one `.id(_:)` report the same `ViewNodeID` (see
/// `ViewNode.claimExactIdentityOccurrence`'s doc comment: "two occurrence-0
/// claims of one entity thrash the shared home ... both rows report one
/// `viewNodeID`"). The retained-draw reuse index is a
/// `[ViewNodeID: DrawNode]` dictionary, so a colliding key silently kept only
/// the last writer, and the *other* sibling then reused a draw node that was
/// never its own — rendering one sibling's content twice and dropping the
/// other's.
///
/// This is pre-existing and independent of damage production, but it only
/// became observable once the incremental raster path went live, because the
/// mispaired tree also feeds damage diffing.
@Suite
struct RetainedDrawDuplicateIdentityTests {
  private static let sharedViewNodeID = ViewNodeID(rawValue: 7)
  private static let unitBounds = CellRect(
    origin: .zero,
    size: .init(width: 8, height: 1)
  )

  private static func placedSibling(
    identity: Identity,
    text: String,
    y: Int
  ) -> PlacedNode {
    PlacedNode(
      viewNodeID: sharedViewNodeID,
      identity: identity,
      bounds: .init(
        origin: .init(x: 0, y: y),
        size: .init(width: 8, height: 1)
      ),
      drawPayload: .text(text)
    )
  }

  /// The two siblings share `ViewNodeID` but carry distinct identities and
  /// distinct text — the shape `.id("dup")` on two siblings produces.
  private static func placedRoot() -> PlacedNode {
    PlacedNode(
      identity: testIdentity("root"),
      bounds: .init(origin: .zero, size: .init(width: 8, height: 2)),
      children: [
        placedSibling(identity: testIdentity("root", "first"), text: "A", y: 0),
        placedSibling(identity: testIdentity("root", "second"), text: "B", y: 1),
      ]
    )
  }

  private static func collectText(_ command: DrawCommand) -> [String] {
    switch command {
    case .text(_, let content, _, _, _, _):
      return [content]
    case .group(_, let children):
      return children.flatMap(collectText)
    default:
      return []
    }
  }

  private static func collectText(_ node: DrawNode) -> [String] {
    var found = node.commands.flatMap(collectText)
    for child in node.children {
      found.append(contentsOf: collectText(child))
    }
    return found
  }

  @Test("retained draw reuse never serves a sibling another sibling's draw node")
  func retainedDrawReuseDoesNotMispairDuplicateViewNodeIDSiblings() {
    let placed = Self.placedRoot()
    let extractor = DrawExtractor()

    // The fresh extraction is the oracle: it cannot mispair, because it never
    // consults the index.
    let fresh = extractor.extract(from: placed)
    let freshText = Self.collectText(fresh)
    #expect(freshText == ["A", "B"], "fresh extraction is the correctness oracle")

    // Build the retained index exactly as FrameTailRetainedState does, from
    // the previous frame's draw tree.
    var index: [ViewNodeID: DrawNode] = [:]
    func indexDrawNode(_ node: DrawNode) {
      if let viewNodeID = node.viewNodeID {
        index[viewNodeID] = node
      }
      for child in node.children { indexDrawNode(child) }
    }
    indexDrawNode(fresh)

    // The proof must admit the *siblings* only. `.wholeTreeIdentical` would
    // reuse the root wholesale, so extraction never descends and never looks a
    // sibling up — the mispairing would be masked and this test would pass for
    // the wrong reason.
    let retained = RetainedDrawExtractionInput(
      previousDraw: fresh,
      previousDrawByNodeID: index,
      proof: .subtreesIdentical([
        testIdentity("root", "first"),
        testIdentity("root", "second"),
      ])
    )

    let reused = extractor.extract(from: placed, retained: retained)

    // The property that matters: reuse is an optimisation, so it must produce
    // the same draw tree the fresh path produces. Before the fix this fails
    // with ["B", "B"] — the index kept only the second sibling, and the first
    // sibling reused it.
    #expect(
      Self.collectText(reused) == freshText,
      "retained reuse must agree with fresh extraction for duplicate-id siblings"
    )
  }

  @Test("a colliding ViewNodeID never resolves to a node with a different identity")
  func collidingViewNodeIDDoesNotResolveAcrossIdentities() {
    let placed = Self.placedRoot()
    let fresh = DrawExtractor().extract(from: placed)

    var index: [ViewNodeID: DrawNode] = [:]
    func indexDrawNode(_ node: DrawNode) {
      if let viewNodeID = node.viewNodeID {
        index[viewNodeID] = node
      }
      for child in node.children { indexDrawNode(child) }
    }
    indexDrawNode(fresh)

    let retained = RetainedDrawExtractionInput(
      previousDraw: fresh,
      previousDrawByNodeID: index,
      proof: .wholeTreeIdentical
    )

    // Ask the seam directly for each sibling. A candidate whose identity is
    // not the requesting node's identity is a mispairing, and serving nil
    // (falling through to fresh extraction) is always sound.
    for sibling in placed.children {
      if let candidate = retained.previousDrawNode(for: sibling) {
        #expect(
          candidate.identity == sibling.identity,
          """
          previousDrawNode served \(candidate.identity) for \(sibling.identity); \
          a reuse candidate must be the requesting node's own previous draw node
          """
        )
      }
    }
  }
}
