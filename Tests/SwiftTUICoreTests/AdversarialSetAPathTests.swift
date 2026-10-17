import Testing

@testable import SwiftTUICore

// STUI-609, STUI-692, STUI-906 and STUI-911: fill, bounds and transforms
// must agree about implicit origins and independently closed subpaths.
@Suite("Adversarial set A: path geometry")
struct AdversarialSetAPathTests {
  @Test func setA071LeadingLineTriangleSurvivesNegativeTranslation() {
    var path = Path()
    path.addLine(to: .init(x: 8, y: 0))
    path.addLine(to: .init(x: 4, y: 8))
    translation(path, dx: -13, dy: 21)
  }

  @Test func setA072LeadingQuadraticKeepsImplicitOriginAfterTranslation() {
    var path = Path()
    path.addQuadCurve(to: .init(x: 8, y: 0), control: .init(x: 4, y: 10))
    path.close()
    translation(path, dx: 17, dy: -9)
  }

  @Test func setA073LeadingCubicKeepsImplicitOriginAfterTranslation() {
    var path = Path()
    path.addCurve(to: .init(x: 8, y: 0), control1: .init(x: 0, y: 9), control2: .init(x: 8, y: 9))
    translation(path, dx: -19, dy: -11)
  }

  @Test func setA074TranslationCannotBridgeDisjointOpenContours() {
    var path = triangle()
    path.move(to: .init(x: 20, y: 0))
    path.addLine(to: .init(x: 28, y: 0))
    path.addLine(to: .init(x: 24, y: 8))
    translation(path, dx: 7, dy: 13)
    #expect(!path.contains(.init(x: 14, y: 3)))
    #expect(!path.translatedBy(dx: 7, dy: 13).contains(.init(x: 21, y: 16)))
  }

  @Test func setA075CloseBeforeFirstLineRetainsTransformableOrigin() {
    var path = Path()
    path.close()
    path.addLine(to: .init(x: 8, y: 0))
    path.addLine(to: .init(x: 4, y: 8))
    translation(path, dx: 11, dy: 19)
  }

  @Test func setA076ReflectionPreservesSelfIntersectionFillRules() {
    var path = Path()
    path.addLine(to: .init(x: 8, y: 8))
    path.addLine(to: .init(x: 0, y: 8))
    path.addLine(to: .init(x: 8, y: 0))
    let reflected = path.scaledBy(sx: -1, sy: 1)
    for point in probes {
      for rule: FillRule in [.nonZero, .evenOdd] {
        #expect(
          path.contains(point, fillRule: rule)
            == reflected.contains(.init(x: -point.x, y: point.y), fillRule: rule))
      }
    }
  }

  @Test func setA077AnisotropicScaleIncludesLeadingLineOrigin() {
    let path = triangle()
    let scaled = path.scaledBy(sx: 3, sy: 0.5)
    #expect(scaled.flattened() == [[.zero, .init(x: 24, y: 0), .init(x: 12, y: 4)]])
    for point in probes {
      #expect(path.contains(point) == scaled.contains(.init(x: point.x * 3, y: point.y * 0.5)))
    }
  }

  @Test func setA078TrimCommutesWithTranslationAcrossContours() {
    var path = triangle()
    path.move(to: .init(x: 20, y: 0))
    path.addLine(to: .init(x: 20, y: 12))
    let first = path.trimmedPath(from: 0.2, to: 0.85).translatedBy(dx: 12, dy: -7)
    let second = path.translatedBy(dx: 12, dy: -7).trimmedPath(from: 0.2, to: 0.85)
    points(first.flattened(), second.flattened())
  }

  @Test func setA079InverseTranslationDoesNotAccumulateImplicitSegments() {
    let original = triangle()
    var path = original
    for _ in 0..<10 { path = path.translatedBy(dx: 64, dy: -32).translatedBy(dx: -64, dy: 32) }
    #expect(path.flattened() == original.flattened())
    #expect(path.boundingRect == original.boundingRect)
    #expect(path == original)
  }

  @Test func setA080EvenOddHoleSurvivesReflectionAndTranslation() {
    var path = Path(.init(origin: .zero, size: .init(width: 10, height: 10)))
    path.addRect(.init(origin: .init(x: 2, y: 2), size: .init(width: 6, height: 6)))
    let moved = path.scaledBy(sx: -1, sy: -1).translatedBy(dx: 30, dy: 40)
    #expect(!moved.contains(.init(x: 25, y: 35), fillRule: .evenOdd))
    #expect(moved.contains(.init(x: 25, y: 35), fillRule: .nonZero))
    for point in probes {
      for rule: FillRule in [.nonZero, .evenOdd] {
        #expect(
          path.contains(point, fillRule: rule)
            == moved.contains(.init(x: 30 - point.x, y: 40 - point.y), fillRule: rule))
      }
    }
  }

  private var probes: [Point] {
    (-1...11).flatMap { y in (-1...11).map { x in Point(x: Double(x) + 0.25, y: Double(y) + 0.25) }
    }
  }

  private func triangle() -> Path {
    var path = Path()
    path.addLine(to: .init(x: 8, y: 0))
    path.addLine(to: .init(x: 4, y: 8))
    return path
  }

  private func translation(_ path: Path, dx: Double, dy: Double) {
    let moved = path.translatedBy(dx: dx, dy: dy)
    let expected = path.flattened().map { $0.map { Point(x: $0.x + dx, y: $0.y + dy) } }
    points(moved.flattened(), expected)
    if let before = path.boundingRect, let after = moved.boundingRect {
      #expect(abs(after.origin.x - before.origin.x - dx) < 0.000001)
      #expect(abs(after.origin.y - before.origin.y - dy) < 0.000001)
      #expect(after.size == before.size)
    } else {
      Issue.record("Nonempty paths must have bounds")
    }
    for point in probes {
      for rule: FillRule in [.nonZero, .evenOdd] {
        #expect(
          path.contains(point, fillRule: rule)
            == moved.contains(.init(x: point.x + dx, y: point.y + dy), fillRule: rule))
      }
    }
  }

  private func points(_ actual: [[Point]], _ expected: [[Point]]) {
    #expect(actual.count == expected.count)
    for (a, b) in zip(actual, expected) {
      #expect(a.count == b.count)
      for (p, q) in zip(a, b) {
        #expect(abs(p.x - q.x) < 0.000001)
        #expect(abs(p.y - q.y) < 0.000001)
      }
    }
  }
}
