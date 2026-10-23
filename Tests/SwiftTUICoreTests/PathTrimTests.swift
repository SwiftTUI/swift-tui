import Testing

@testable import SwiftTUICore

@Suite
struct PathTrimTests {
  @Test("placed trims measure physical distance while preserving the placed outline")
  func placedTrimUsesPhysicalLength() throws {
    let geometry = ShapeGeometry.trimmed(.circle, from: 0.4, to: 0.6)
      .resolved(in: .init(width: 40, height: 20), trimAspectRatio: 2)
    guard case .path(let path, _) = geometry else {
      Issue.record("Expected resolved trim path")
      return
    }
    let points = path.path.flattened().flatMap { $0 }
    let first = try #require(points.first)
    let last = try #require(points.last)
    // A physical circle: 40% and 60% of its circumference are 144° and 216°.
    #expect(abs(first.x - 0.09549) < 0.002)
    #expect(abs(first.y - 0.79389) < 0.002)
    #expect(abs(last.x - 0.09549) < 0.002)
    #expect(abs(last.y - 0.20611) < 0.002)
  }

  @Test("trimming normalizes overflowing lengths and preserves finite coordinates")
  func extremeLengths() throws {
    let crossing = Path([.move(to: .init(x: -1e308, y: 0)), .line(to: .init(x: 1e308, y: 0))])
    let points = crossing.trimmedPath(from: 0.25, to: 0.75).flattened().flatMap { $0 }
    try #require(points.count == 2)
    #expect(abs(points[0].x / 1e308 + 0.5) < 1e-12)
    #expect(abs(points[1].x / 1e308 - 0.5) < 1e-12)
    let repeated = Path([
      .move(to: .zero), .line(to: .init(x: 1e308, y: 0)),
      .line(to: .zero), .line(to: .init(x: 1e308, y: 0)),
    ])
    #expect(
      repeated.trimmedPath(from: 1.0 / 3, to: 2.0 / 3).elements == [
        .move(to: .init(x: 1e308, y: 0)), .line(to: .zero),
      ])
  }

  /// A 4 x 2 rectangle: 12 units round, starting at the origin and running along
  /// the top edge first.
  private var rectangle: Path {
    var path = Path()
    path.addRect(Rect(origin: Point(x: 0, y: 0), size: Size(width: 4, height: 2)))
    return path
  }

  @Test("length normalization is independent of the path's translation")
  func translatedTinyLength() {
    var path = Path()
    path.move(to: Point(x: 0, y: 1e308))
    path.addLine(to: Point(x: 1e-100, y: 1e308))
    let elements = path.trimmedPath(from: 0.25, to: 0.75).elements
    #expect(
      elements == [
        .move(to: Point(x: 0.25e-100, y: 1e308)),
        .line(to: Point(x: 0.75e-100, y: 1e308)),
      ])
    var crossing = Path()
    crossing.move(to: Point(x: -1e308, y: 0))
    crossing.addLine(to: Point(x: 1e308, y: 0))
    #expect(crossing.contains(.zero))
    #expect(!crossing.contains(Point(x: 0, y: 1)))
  }

  @Test("a trim keeps the fraction of the length between its ends")
  func firstQuarter() {
    // A quarter of 12 is 3, which is three quarters of the top edge.
    #expect(
      rectangle.trimmedPath(from: 0, to: 0.25).elements == [
        .move(to: Point(x: 0, y: 0)),
        .line(to: Point(x: 3, y: 0)),
      ])
  }

  @Test("a trim that spans a corner keeps both segments")
  func acrossACorner() {
    // From 6 to 12: the bottom edge, right to left, then the leading edge, up.
    #expect(
      rectangle.trimmedPath(from: 0.5, to: 1).elements == [
        .move(to: Point(x: 4, y: 2)),
        .line(to: Point(x: 0, y: 2)),
        .line(to: Point(x: 0, y: 0)),
      ])
  }

  @Test("a trim that starts and ends inside one segment")
  func insideOneSegment() {
    // From 1 to 2 along the top edge.
    let third = rectangle.trimmedPath(from: 1.0 / 12, to: 2.0 / 12).elements
    #expect(third.count == 2)
    guard case .move(let start) = third[0], case .line(let end) = third[1] else {
      Issue.record("expected a move and a line, got \(third)")
      return
    }
    #expect(abs(start.x - 1) < 1e-9 && start.y == 0)
    #expect(abs(end.x - 2) < 1e-9 && end.y == 0)
  }

  @Test("the fractions are measured across every subpath, in order")
  func acrossSubpaths() {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addLine(to: Point(x: 2, y: 0))
    path.move(to: Point(x: 0, y: 5))
    path.addLine(to: Point(x: 2, y: 5))
    // 4 units in all. The middle half is the second unit of the first line and
    // the first unit of the second, as two separate strokes.
    #expect(
      path.trimmedPath(from: 0.25, to: 0.75).elements == [
        .move(to: Point(x: 1, y: 0)),
        .line(to: Point(x: 2, y: 0)),
        .move(to: Point(x: 0, y: 5)),
        .line(to: Point(x: 1, y: 5)),
      ])
  }

  @Test("the whole trim keeps every segment")
  func wholeTrim() {
    #expect(rectangle.trimmedPath(from: 0, to: 1).elements.count == 5)
    // Out-of-range fractions clamp.
    #expect(
      rectangle.trimmedPath(from: -3, to: 7).elements
        == rectangle.trimmedPath(from: 0, to: 1).elements)
  }

  @Test("a trim with nothing between its ends is empty")
  func emptyTrims() {
    #expect(rectangle.trimmedPath(from: 0.5, to: 0.5).elements.isEmpty)
    #expect(rectangle.trimmedPath(from: 0.75, to: 0.25).elements.isEmpty)
    #expect(rectangle.trimmedPath(from: .nan, to: 1).elements.isEmpty)
    #expect(Path().trimmedPath(from: 0, to: 1).elements.isEmpty)
  }

  @Test("a curve is trimmed by arc length")
  func curvedPath() throws {
    var circle = Path()
    circle.addEllipse(in: Rect(origin: Point(x: 0, y: 0), size: Size(width: 2, height: 2)))
    // Half of a circle's length ends at the point opposite its start.
    let half = circle.trimmedPath(from: 0, to: 0.5)
    guard case .move(let start) = try #require(half.elements.first),
      case .line(let end) = try #require(half.elements.last)
    else {
      Issue.record("expected a move first and a line last")
      return
    }
    #expect(abs((start.x - 1) + (end.x - 1)) < 0.02)
    #expect(abs((start.y - 1) + (end.y - 1)) < 0.02)
  }
}
