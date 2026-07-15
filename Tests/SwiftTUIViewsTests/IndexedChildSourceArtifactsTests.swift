import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

/// F145 (proposal 2026-07-13-002 Stage 1b): a lazy container's
/// `ForEachIndexedChildSource` re-minted every `EntityIdentity` and rebuilt a
/// joined identity-path signature string on EVERY container resolve. The
/// hosting `ViewNode` now retains those identity artifacts per container, and
/// a rebuilt source adopts them when (element ids, identity root, entity
/// scope) are unchanged — sharing the signature's storage box, so downstream
/// equivalence comparisons take the pointer-equal fast path. Element caches
/// are deliberately NOT adopted: equal ids do not imply equal element values,
/// and realized rows capture the declaring frame's context.
@MainActor
@Suite("Indexed child source identity-artifact retention (F145)")
struct IndexedChildSourceArtifactsTests {
  private struct Row: Hashable {
    var id: Int
    var title: String
  }

  private func makeSource(
    rows: [Row],
    context: ResolveContext
  ) -> ForEachIndexedChildSource<[Row], Int, Text> {
    ForEachIndexedChildSource(
      data: rows,
      id: \.id,
      content: { Text($0.title) },
      childContext: context
    )
  }

  private func collectedTexts(_ node: ResolvedNode) -> [String] {
    var texts: [String] = []
    func walk(_ node: ResolvedNode) {
      if case .text(let content) = node.drawPayload {
        texts.append(content)
      }
      for child in node.children {
        walk(child)
      }
    }
    walk(node)
    return texts
  }

  @Test("unchanged ids adopt retained artifacts: the signature shares storage")
  func unchangedIdsAdoptRetainedArtifacts() {
    let host = SwiftTUIGraph.ViewNode(identity: testIdentity("Host"))
    let context = ResolveContext(identity: testIdentity("Root", "LazyVStack[0]"))
    let rows = (0..<8).map { Row(id: $0, title: "row \($0)") }

    let first = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rows, context: context)
    }
    let second = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rows, context: context)
    }

    #expect(second.measurementSignature == first.measurementSignature)
    #expect(
      second.measurementSignature.storageIdentifier
        == first.measurementSignature.storageIdentifier,
      "an unchanged-id rebuild must adopt the retained signature box, not re-derive it"
    )
  }

  @Test("without a hosting node, equal content still compares equal (byte-exact fallback)")
  func equalContentComparesEqualWithoutRetention() {
    let context = ResolveContext(identity: testIdentity("Root", "LazyVStack[0]"))
    let rows = (0..<4).map { Row(id: $0, title: "row \($0)") }

    let first = makeSource(rows: rows, context: context)
    let second = makeSource(rows: rows, context: context)

    #expect(
      second.measurementSignature.storageIdentifier
        != first.measurementSignature.storageIdentifier,
      "no host node means no retention — the boxes must be independent"
    )
    #expect(second.measurementSignature == first.measurementSignature)
  }

  @Test("id changes miss adoption and compare unequal: reorder, append, removal")
  func changedIdsCompareUnequal() {
    let host = SwiftTUIGraph.ViewNode(identity: testIdentity("Host"))
    let context = ResolveContext(identity: testIdentity("Root", "LazyVStack[0]"))
    let rows = [Row(id: 1, title: "a"), Row(id: 2, title: "b"), Row(id: 3, title: "c")]

    let baseline = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rows, context: context)
    }
    let reordered = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: [rows[1], rows[0], rows[2]], context: context)
    }
    #expect(reordered.measurementSignature != baseline.measurementSignature)

    let appended = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rows + [Row(id: 4, title: "d")], context: context)
    }
    #expect(appended.measurementSignature != baseline.measurementSignature)

    let removed = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: Array(rows.dropLast()), context: context)
    }
    #expect(removed.measurementSignature != baseline.measurementSignature)
  }

  @Test("duplicate-id occurrence qualification survives adoption")
  func duplicateIdOccurrencesSurviveAdoption() {
    let host = SwiftTUIGraph.ViewNode(identity: testIdentity("Host"))
    let context = ResolveContext(identity: testIdentity("Root", "LazyVStack[0]"))
    let rows = [
      Row(id: 7, title: "first"), Row(id: 7, title: "second"), Row(id: 3, title: "third"),
    ]

    let first = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rows, context: context)
    }
    let second = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rows, context: context)
    }
    #expect(
      second.measurementSignature.storageIdentifier
        == first.measurementSignature.storageIdentifier
    )

    let freshIdentities = makeEntityIdentities(
      ids: rows.map(\.id),
      scope: context.structuralPath
    )
    for index in rows.indices {
      #expect(second.child(at: index).entityIdentity == freshIdentities[index])
    }
  }

  @Test("adoption keeps identities but never element caches: fresh values render")
  func elementRealizationReflectsFreshDataAfterAdoption() {
    let host = SwiftTUIGraph.ViewNode(identity: testIdentity("Host"))
    let context = ResolveContext(identity: testIdentity("Root", "LazyVStack[0]"))

    let first = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: [Row(id: 1, title: "before")], context: context)
    }
    #expect(collectedTexts(first.child(at: 0)) == ["before"])

    // Same id, different element value: identity artifacts adopt, but the
    // realized row must come from the NEW data, not the old source's cache.
    let second = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: [Row(id: 1, title: "after")], context: context)
    }
    #expect(
      second.measurementSignature.storageIdentifier
        == first.measurementSignature.storageIdentifier
    )
    #expect(collectedTexts(second.child(at: 0)) == ["after"])
  }

  @Test("containers retain independently per identity root under one host")
  func perContainerIsolationUnderOneHost() {
    let host = SwiftTUIGraph.ViewNode(identity: testIdentity("Host"))
    let contextA = ResolveContext(identity: testIdentity("Root", "LazyVStack[0]"))
    let contextB = ResolveContext(identity: testIdentity("Root", "LazyVStack[1]"))
    let rowsA = (0..<3).map { Row(id: $0, title: "a\($0)") }
    let rowsB = (10..<15).map { Row(id: $0, title: "b\($0)") }

    let firstA = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rowsA, context: contextA)
    }
    _ = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rowsB, context: contextB)
    }
    // A second container under the same host must not have evicted the
    // first container's artifacts.
    let secondA = ViewNodeContext.withCurrentValue(host) {
      makeSource(rows: rowsA, context: contextA)
    }
    #expect(
      secondA.measurementSignature.storageIdentifier
        == firstA.measurementSignature.storageIdentifier
    )
  }

  @Test("signature prefilter never proves equality: tie falls back to path bytes")
  func signatureEqualityIsByteExact() {
    let empty = IndexedChildMeasurementSignature(elementPaths: [])
    let alsoEmpty = IndexedChildMeasurementSignature(elementPaths: [])
    #expect(empty == alsoEmpty)

    let ab = IndexedChildMeasurementSignature(elementPaths: ["a", "b"])
    let abAgain = IndexedChildMeasurementSignature(elementPaths: ["a", "b"])
    #expect(ab == abAgain)
    #expect(ab.storageIdentifier != abAgain.storageIdentifier)

    let a = IndexedChildMeasurementSignature(elementPaths: ["a"])
    #expect(a != ab)
    let ba = IndexedChildMeasurementSignature(elementPaths: ["b", "a"])
    #expect(ba != ab)
  }
}
