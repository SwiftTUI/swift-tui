import Testing

@_spi(Testing) @testable import SwiftTUICore

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

  @Test("retained phase signature rejects type-erased draw payloads")
  func retainedPhaseSignatureRejectsTypeErasedDrawPayloads() {
    struct Dots: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setPixel(x: 0, y: 0)
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

    #expect(RetainedPhaseExtractionSignature.make(from: ordinary) != nil)
    #expect(RetainedPhaseExtractionSignature.make(from: canvas) == nil)
  }
}
