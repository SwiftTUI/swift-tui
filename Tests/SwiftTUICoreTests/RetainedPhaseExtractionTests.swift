import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct RetainedPhaseExtractionTests {
  @Test("retained semantic extraction falls back without a whole-tree proof")
  func retainedSemanticExtractionFallsBackWithoutProof() {
    let current = PlacedNode(
      identity: testIdentity("current"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
    )
    let previous = PlacedNode(
      identity: testIdentity("previous"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
    )
    let previousSnapshot = SemanticSnapshot(
      focusRegions: [
        FocusRegion(
          identity: previous.identity,
          rect: previous.bounds,
          focusInteractions: .activate
        )
      ]
    )

    let retained = RetainedSemanticExtractionInput(
      previousSnapshot: previousSnapshot,
      proof: .none
    )

    let extracted = SemanticExtractor().extract(from: current, retained: retained)

    #expect(extracted == SemanticExtractor().extract(from: current))
    #expect(extracted != previousSnapshot)
  }

  @Test("retained semantic extraction reuses with a whole-tree proof")
  func retainedSemanticExtractionReusesWithWholeTreeProof() {
    let placed = PlacedNode(
      identity: testIdentity("root"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
    )
    let previousSnapshot = SemanticSnapshot(
      focusRegions: [
        FocusRegion(
          identity: placed.identity,
          rect: placed.bounds,
          focusInteractions: .activate
        )
      ]
    )

    let retained = RetainedSemanticExtractionInput(
      previousSnapshot: previousSnapshot,
      proof: .wholeTreeIdentical
    )

    let extracted = SemanticExtractor().extract(from: placed, retained: retained)

    #expect(extracted == previousSnapshot)
  }

  @Test("retained draw extraction falls back without a whole-tree proof")
  func retainedDrawExtractionFallsBackWithoutProof() {
    let current = PlacedNode(
      identity: testIdentity("current"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
    )
    let previous = PlacedNode(
      identity: testIdentity("previous"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
    )
    let previousDraw = DrawNode(
      identity: previous.identity,
      bounds: previous.bounds
    )

    let retained = RetainedDrawExtractionInput(
      previousDraw: previousDraw,
      proof: .none
    )

    let extracted = DrawExtractor().extract(from: current, retained: retained)

    #expect(extracted == DrawExtractor().extract(from: current))
    #expect(extracted != previousDraw)
  }

  @Test("retained draw extraction reuses with a whole-tree proof")
  func retainedDrawExtractionReusesWithWholeTreeProof() {
    let placed = PlacedNode(
      identity: testIdentity("root"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
    )
    let previousDraw = DrawNode(
      identity: placed.identity,
      bounds: placed.bounds,
      commands: [
        .text(
          bounds: placed.bounds,
          content: "cached",
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )

    let retained = RetainedDrawExtractionInput(
      previousDraw: previousDraw,
      proof: .wholeTreeIdentical
    )

    let extracted = DrawExtractor().extract(from: placed, retained: retained)

    #expect(extracted == previousDraw)
  }

  @Test("retained draw extraction substitutes proven clean subtrees")
  func retainedDrawExtractionSubstitutesProvenCleanSubtrees() {
    let rootID = testIdentity("retained-draw-root")
    let dirtyID = testIdentity("retained-draw-root", "dirty")
    let cleanID = testIdentity("retained-draw-root", "clean")
    let dirty = PlacedNode(
      viewNodeID: ViewNodeID(rawValue: 2),
      identity: dirtyID,
      bounds: .init(origin: .zero, size: .init(width: 5, height: 1)),
      drawPayload: .text("dirty")
    )
    let clean = PlacedNode(
      viewNodeID: ViewNodeID(rawValue: 3),
      identity: cleanID,
      bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 5, height: 1)),
      drawPayload: .text("clean")
    )
    let placed = PlacedNode(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: rootID,
      bounds: .init(origin: .zero, size: .init(width: 5, height: 2)),
      children: [dirty, clean]
    )
    let cachedCleanDraw = DrawNode(
      viewNodeID: ViewNodeID(rawValue: 3),
      identity: cleanID,
      bounds: clean.bounds,
      commands: [
        .text(
          bounds: clean.bounds,
          content: "cached-clean",
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )
    let previousDraw = DrawNode(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: rootID,
      bounds: placed.bounds,
      children: [
        DrawExtractor().extract(from: dirty),
        cachedCleanDraw,
      ]
    )
    let retained = RetainedDrawExtractionInput(
      previousDraw: previousDraw,
      previousDrawByNodeID: [ViewNodeID(rawValue: 3): cachedCleanDraw],
      proof: .subtreesIdentical([cleanID])
    )

    let extracted = DrawExtractor().extract(from: placed, retained: retained)

    #expect(extracted.children.count == 2)
    #expect(extracted.children[1] == cachedCleanDraw)
    #expect(extracted.children[0] == DrawExtractor().extract(from: dirty))
  }

  @Test("phase signature distinguishes lazy child scroll estimates (F133)")
  func phaseSignatureDistinguishesLazyChildScrollEstimates() {
    // A lazy container's never-placed children surface only through
    // `lazyChildScrollEstimates` — the semantic phase derives out-of-window
    // `scrollTo` targets from them. Changing an out-of-window row identity
    // leaves every signature-visible field (geometry, payloads, metadata)
    // byte-identical, so a signature blind to the estimates would prove
    // `.wholeTreeIdentical` and serve a stale SemanticSnapshot in which
    // `scrollTo(newID)` resolves nothing.
    var container = PlacedNode(
      identity: testIdentity("lazy"),
      bounds: .init(origin: .zero, size: .init(width: 10, height: 4))
    )
    container.lazyChildScrollEstimates = [
      .init(
        identity: testIdentity("lazy", "row-7"),
        rect: .init(origin: .init(x: 0, y: 28), size: .init(width: 10, height: 4))
      )
    ]
    var changed = container
    changed.lazyChildScrollEstimates = [
      .init(
        identity: testIdentity("lazy", "row-8"),
        rect: .init(origin: .init(x: 0, y: 28), size: .init(width: 10, height: 4))
      )
    ]

    #expect(RetainedPhaseExtractionSignature.subtreesIdentical(container, container))
    #expect(!RetainedPhaseExtractionSignature.subtreesIdentical(container, changed))
  }

  @Test("placed node equality distinguishes lazy child scroll estimates (F133)")
  func placedNodeEqualityDistinguishesLazyChildScrollEstimates() {
    // `PlacedNode.==` backs the retained-baseline match in the frame tail;
    // estimate-blind equality would treat an out-of-window identity churn as
    // a byte-identical baseline.
    var container = PlacedNode(
      identity: testIdentity("lazy"),
      bounds: .init(origin: .zero, size: .init(width: 10, height: 4))
    )
    container.lazyChildScrollEstimates = [
      .init(
        identity: testIdentity("lazy", "row-7"),
        rect: .init(origin: .init(x: 0, y: 28), size: .init(width: 10, height: 4))
      )
    ]
    var changed = container
    changed.lazyChildScrollEstimates = nil

    #expect(container != changed)
  }

  @Test("retained phase signature rejects type-erased draw payloads")
  func retainedPhaseSignatureRejectsTypeErasedDrawPayloads() {
    struct Dots: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setSample(GridSample(x: 0, y: 0))
      }
    }

    let ordinary = PlacedNode(
      identity: testIdentity("text"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      drawPayload: .text("stable")
    )
    let canvas = PlacedNode(
      identity: testIdentity("canvas"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      drawPayload: .canvas(.init(drawing: Dots()))
    )

    #expect(RetainedPhaseExtractionSignature.subtreesIdentical(ordinary, ordinary))
    // Canvas payloads are never value-comparable: an unsupported node cannot
    // prove phase-reuse equivalence even against itself.
    #expect(!RetainedPhaseExtractionSignature.subtreesIdentical(canvas, canvas))
  }
}
