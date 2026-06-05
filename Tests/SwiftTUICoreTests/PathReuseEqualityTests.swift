import Testing

@testable import SwiftTUICore

/// Phase 3: the reuse fast paths key on value equality of `drawPayload`. A
/// custom-path node carries `ShapeGeometry.path(BoxedPath, FillRule)`, where
/// `BoxedPath` is `indirect`-boxed and COW-backed. These tests pin the
/// equality semantics that the retained-reuse / commit machinery depends on:
/// a shared box compares equal in O(1) (pointer identity), distinct boxes fall
/// back to a correct structural compare, and a genuine path change busts
/// equality (so reuse is invalidated exactly when the visual changes).
@Suite("Path geometry reuse equality")
struct PathReuseEqualityTests {

  private func triangle() -> Path {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addLine(to: Point(x: 1, y: 0))
    path.addLine(to: Point(x: 0.5, y: 1))
    path.close()
    return path
  }

  @Test("a copied BoxedPath shares storage and compares equal")
  func sharedBoxEqual() {
    let a = BoxedPath(triangle())
    let b = a  // struct copy shares the COW storage (pointer identity)
    #expect(a == b)
  }

  @Test("independently constructed equal paths compare equal structurally")
  func distinctBoxesEqualContent() {
    let a = BoxedPath(triangle())
    let b = BoxedPath(triangle())  // distinct storage, identical content
    #expect(a == b)
  }

  @Test("different path content compares unequal")
  func differentContentUnequal() {
    let a = BoxedPath(triangle())
    var other = triangle()
    other.addLine(to: Point(x: 0.25, y: 0.25))
    let b = BoxedPath(other)
    #expect(a != b)
  }

  @Test("ShapeGeometry.path equality reflects path and fill rule")
  func geometryEquality() {
    let a = ShapeGeometry.path(BoxedPath(triangle()), .nonZero)
    let sameContent = ShapeGeometry.path(BoxedPath(triangle()), .nonZero)
    let differentRule = ShapeGeometry.path(BoxedPath(triangle()), .evenOdd)
    var mutated = triangle()
    mutated.addLine(to: Point(x: 0.1, y: 0.9))
    let differentPath = ShapeGeometry.path(BoxedPath(mutated), .nonZero)

    #expect(a == sameContent)
    #expect(a != differentRule)
    #expect(a != differentPath)
  }

  @Test("path geometry is distinct from the analytic cases")
  func pathVersusAnalytic() {
    let path = ShapeGeometry.path(BoxedPath(triangle()), .nonZero)
    #expect(path != .circle)
    #expect(path != .rectangle)
    #expect(ShapeGeometry.circle == .circle)
  }

  @Test("a path-bearing ShapePayload round-trips its geometry")
  func payloadCarriesPath() {
    let payload = ShapePayload(
      geometry: .path(BoxedPath(triangle()), .nonZero),
      insetAmount: 0,
      operation: .fill(style: nil, mode: .full)
    )
    guard case .path(let boxed, let rule) = payload.geometry else {
      Issue.record("expected a path geometry")
      return
    }
    #expect(rule == .nonZero)
    #expect(boxed.path.elements.count == triangle().elements.count)
  }
}
