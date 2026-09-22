import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct SpatialTapGestureTests {
  private func precise(_ point: Point) -> PointerLocation {
    .subCell(location: point, source: .nativePixels, metrics: .estimated)
  }

  @Test("SpatialTapGesture carries tap location in its value (local coords)")
  func carriesLocation() throws {
    let g = SpatialTapGesture()
    let rec = g._makeRecognizer(
      context: .init(
        attachingIdentity: Identity(components: [IdentityComponent(rawValue: "r")]),
        gestureStateRegistry: nil,
        requestDeadline: { _ in }
      )
    )
    let rect = CellRect(origin: CellPoint(x: 4, y: 2), size: CellSize(width: 8, height: 2))
    _ = rec.handle(
      event: .init(
        kind: .down(.primary),
        location: precise(Point(x: 6, y: 3)),
        targetRect: rect
      ))
    _ = rec.handle(
      event: .init(
        kind: .up(.primary),
        location: precise(Point(x: 6, y: 3)),
        targetRect: rect
      ))
    let v: SpatialTapGesture.Value? = rec.currentValue()
    // .local: location relative to rect.origin → (6-4, 3-2) = (2, 1)
    #expect(v?.location == Point(x: 2, y: 1))
    #expect(v?.pointer.location == Point(x: 6, y: 3))
  }

  @Test("SpatialTapGesture .global returns raw terminal point")
  func globalCoordinates() throws {
    let g = SpatialTapGesture(coordinateSpace: .global)
    let rec = g._makeRecognizer(
      context: .init(
        attachingIdentity: Identity(components: [IdentityComponent(rawValue: "r")]),
        gestureStateRegistry: nil,
        requestDeadline: { _ in }
      )
    )
    let rect = CellRect(origin: CellPoint(x: 4, y: 2), size: CellSize(width: 8, height: 2))
    _ = rec.handle(
      event: .init(
        kind: .down(.primary),
        location: precise(Point(x: 6, y: 3)),
        targetRect: rect
      ))
    _ = rec.handle(
      event: .init(
        kind: .up(.primary),
        location: precise(Point(x: 6, y: 3)),
        targetRect: rect
      ))
    let v: SpatialTapGesture.Value? = rec.currentValue()
    #expect(v?.location == Point(x: 6, y: 3))
  }

  @Test("SpatialTapGesture fails on drag movement")
  func failsOnMove() {
    let g = SpatialTapGesture()
    let rec = g._makeRecognizer(
      context: .init(
        attachingIdentity: Identity(components: [IdentityComponent(rawValue: "r")]),
        gestureStateRegistry: nil,
        requestDeadline: { _ in }
      )
    )
    let rect = CellRect(origin: .zero, size: CellSize(width: 4, height: 4))
    _ = rec.handle(
      event: .init(
        kind: .down(.primary),
        location: Point(x: 1, y: 1),
        targetRect: rect
      ))
    _ = rec.handle(
      event: .init(
        kind: .dragged(.primary),
        location: Point(x: 3, y: 1),
        targetRect: rect
      ))
    #expect(rec.phase == .failed)
  }
}
