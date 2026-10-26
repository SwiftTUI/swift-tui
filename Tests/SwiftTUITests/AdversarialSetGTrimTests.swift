import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIPrimitives
@testable import SwiftTUIViews

/// Every coordinate of a path's elements, in order, with a tag per element.
private func setGCoordinates(_ path: Path) -> [Double] {
  path.elements.flatMap { element -> [Double] in
    switch element {
    case .move(let point): [0, point.x, point.y]
    case .line(let point): [1, point.x, point.y]
    case .quadCurve(let to, let control): [2, to.x, to.y, control.x, control.y]
    case .curve(let to, let control1, let control2):
      [3, to.x, to.y, control1.x, control1.y, control2.x, control2.y]
    case .close: [4]
    }
  }
}

private func setGClose(_ a: Point, _ b: Point, _ tolerance: Double = 1e-9) -> Bool {
  abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

private func setGRectPath(_ n: [Int]) -> (path: Path, rect: Rect) {
  let rect = Rect(
    origin: Point(x: Double(n[0] % 11 - 5), y: Double(n[1] % 11 - 5)),
    size: Size(width: Double(n[2] % 12 + 1), height: Double(n[3] % 12 + 1)))
  return (Path(rect), rect)
}

@MainActor
@Suite("Campaign F5 pass 2 trim properties", .serialized)
struct AdversarialSetGTrimTests {
  @Test(arguments: Array(112...117))
  func trim(id: Int) {
    switch id {
    case 112: powerOfTwoEquivariance(id)
    case 113: rectangleEndpoint(id)
    case 114: farOutline(id)
    case 115: nestedTrims(id)
    case 116: publicPathMatchesRaster(id)
    default: windowedTrack(id)
    }
  }

  private func powerOfTwoEquivariance(_ id: Int) {
    setGProperty(id, setGDraws(14)) { n in
      let odds: [Double] = [1, 3, 5, 7]
      var path = Path()
      for index in 0..<(2 + n[0] % 3) {
        let point = Point(
          x: Double(n[1 + 2 * index] % 17 - 8) * odds[n[9] % 4],
          y: Double(n[2 + 2 * index] % 17 - 8) * odds[n[10] % 4])
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      let aspect = [1.5, 2, 2.5, 3, 4][n[11] % 5]
      let factor = setGPow2(n[12] % 1021)
      let lower = Double(n[13] % 16) / 16
      let upper = Double(n[13] / 16 % 17) / 16
      let scaled = path.scaledBy(sx: factor, sy: factor)
      guard setGCoordinates(scaled).allSatisfy(\.isFinite) else { return nil }
      let expected = path.physicallyTrimmedPath(from: lower, to: upper, aspectRatio: aspect)
        .scaledBy(sx: factor, sy: factor)
      let actual = scaled.physicallyTrimmedPath(from: lower, to: upper, aspectRatio: aspect)
      let lhs = setGCoordinates(expected)
      guard lhs.allSatisfy(\.isFinite) else { return nil }
      let rhs = setGCoordinates(actual)
      return lhs == rhs ? nil : "trim of the scaled outline \(rhs) != scaled trim \(lhs)"
    }
  }

  private func rectangleEndpoint(_ id: Int) {
    setGProperty(id, setGDraws(6)) { n in
      let (path, rect) = setGRectPath(n)
      let aspect = [1, 1.5, 2, 2.5][n[4] % 4]
      let fraction = Double(n[5] % 33) / 32
      let points = path.physicallyTrimmedPath(from: 0, to: fraction, aspectRatio: aspect)
        .flattened().flatMap { $0 }
      if fraction == 0 { return points.isEmpty ? nil : "a zero trim drew \(points)" }
      guard let first = points.first, let last = points.last else { return "empty trim" }
      let width = rect.size.width
      let vertical = rect.size.height * aspect
      var distance = fraction * (2 * width + 2 * vertical)
      let minX = rect.origin.x
      let minY = rect.origin.y
      let expected: Point
      if distance <= width {
        expected = Point(x: minX + distance, y: minY)
      } else if distance - width <= vertical {
        distance -= width
        expected = Point(x: rect.maxX, y: minY + distance / aspect)
      } else if distance - width - vertical <= width {
        distance -= width + vertical
        expected = Point(x: rect.maxX - distance, y: rect.maxY)
      } else {
        distance -= 2 * width + vertical
        expected = Point(x: minX, y: rect.maxY - distance / aspect)
      }
      guard setGClose(first, Point(x: minX, y: minY)) else { return "trim starts at \(first)" }
      return setGClose(last, expected) ? nil : "trim ends at \(last), expected \(expected)"
    }
  }

  private func farOutline(_ id: Int) {
    setGProperty(id, setGDraws(10)) { n in
      let aspect = [1.5, 2, 3][n[0] % 3]
      func far(_ raw: Int) -> Double {
        let magnitude = Double.greatestFiniteMagnitude * (0.5 + Double(raw % 501) / 1000)
        return raw % 2 == 0 ? magnitude : -magnitude
      }
      func any(_ raw: Int) -> Double {
        let magnitude = Double(sign: .plus, exponent: raw % 1024, significand: 1.5)
        return raw % 2 == 0 ? magnitude : -magnitude
      }
      var points: [Point] = []
      for index in 0..<(2 + n[1] % 3) {
        points.append(Point(x: any(n[2 + 2 * index]), y: far(n[3 + 2 * index])))
      }
      var path = Path()
      path.move(to: points[0])
      for point in points.dropFirst() { path.addLine(to: point) }
      guard zip(points, points.dropFirst()).contains(where: { $0 != $1 }) else { return nil }
      let whole = path.physicallyTrimmedPath(from: 0, to: 1, aspectRatio: aspect)
        .flattened().flatMap { $0 }
      let middle = path.physicallyTrimmedPath(from: 0.25, to: 0.75, aspectRatio: aspect)
        .flattened().flatMap { $0 }
      guard !whole.isEmpty, !middle.isEmpty else {
        return "far outline trimmed to an empty path (whole \(whole.count), middle \(middle.count))"
      }
      guard (whole + middle).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
        return "far outline trimmed to non-finite points"
      }
      // Endpoint error is measured against the outline's own extent: a whole
      // trim reaches its last point at t = (end - travelled) / length, which
      // carries the rounding of the summed lengths (oracle correction C1).
      // Halved, so a span of the whole Double range stays finite.
      let halfExtent =
        zip(points, points.dropFirst()).map {
          max(abs($1.x / 2 - $0.x / 2), abs($1.y / 2 - $0.y / 2))
        }.max() ?? 0
      func relativelyClose(_ a: Point, _ b: Point) -> Bool {
        abs(a.x / 2 - b.x / 2) <= 1e-12 * halfExtent && abs(a.y / 2 - b.y / 2) <= 1e-12 * halfExtent
      }
      guard let first = whole.first, let last = whole.last, let start = points.first,
        let end = points.last
      else { return "missing endpoints" }
      return relativelyClose(first, start) && relativelyClose(last, end)
        ? nil : "whole trim runs \(first) ... \(last), outline \(start) ... \(end)"
    }
  }

  private func nestedTrims(_ id: Int) {
    setGProperty(id, setGDraws(8)) { n in
      let (path, _) = setGRectPath(n)
      let aspect = [1, 1.5, 2, 2.5][n[4] % 4]
      let outerFrom = Double(n[5] % 9) / 16
      let outerTo = 0.5 + Double(n[6] % 9) / 16
      let innerFrom = Double(n[7] % 9) / 16
      let innerTo = 0.5 + Double(n[7] / 9 % 9) / 16
      let nested = path.physicallyTrimmedPath(from: outerFrom, to: outerTo, aspectRatio: aspect)
        .physicallyTrimmedPath(from: innerFrom, to: innerTo, aspectRatio: aspect)
        .flattened().flatMap { $0 }
      let span = outerTo - outerFrom
      let composed = path.physicallyTrimmedPath(
        from: outerFrom + span * innerFrom, to: outerFrom + span * innerTo, aspectRatio: aspect
      ).flattened().flatMap { $0 }
      if nested.isEmpty || composed.isEmpty {
        return nested.isEmpty == composed.isEmpty
          ? nil : "nested \(nested.count) points, composed \(composed.count)"
      }
      guard let a = nested.first, let b = composed.first, let c = nested.last,
        let d = composed.last
      else { return "missing endpoints" }
      return setGClose(a, b) && setGClose(c, d)
        ? nil : "nested \(a) ... \(c), composed \(b) ... \(d)"
    }
  }

  private func publicPathMatchesRaster(_ id: Int) {
    setGProperty(id, setGDraws(5)) { n in
      let width = n[0] % 16 + 1
      let height = n[1] % 16 + 1
      let from = Double(n[2] % 16) / 16
      let to = Double(n[3] % 17) / 16
      let rect = Rect(origin: .zero, size: Size(width: Double(width), height: Double(height)))
      let aspect = RectangleStrokeTrack.snappedAspectRatio(CellPixelMetrics.estimated.aspectRatio)
      let pair: (path: Path, geometry: ShapeGeometry, whole: Bool)
      switch n[4] % 5 {
      case 0:
        let shape = TrimmedShape(base: Circle(), from: from, to: to)
        pair = (shape.path(in: rect), shape.fillGeometry, shape.strokeTrim == nil)
      case 1:
        let shape = TrimmedShape(base: Ellipse(), from: from, to: to)
        pair = (shape.path(in: rect), shape.fillGeometry, shape.strokeTrim == nil)
      case 2:
        let shape = TrimmedShape(base: Capsule(), from: from, to: to)
        pair = (shape.path(in: rect), shape.fillGeometry, shape.strokeTrim == nil)
      case 3:
        let shape = TrimmedShape(base: RoundedRectangle(cornerRadius: 2), from: from, to: to)
        pair = (shape.path(in: rect), shape.fillGeometry, shape.strokeTrim == nil)
      default:
        let shape = TrimmedShape(base: Rectangle(), from: from, to: to)
        pair = (shape.path(in: rect), shape.fillGeometry, shape.strokeTrim == nil)
      }
      guard !pair.whole else { return nil }
      guard
        case .path(let boxed, _) = pair.geometry.resolved(
          in: CellSize(width: width, height: height), trimAspectRatio: aspect)
      else { return "a partial trim did not resolve to a placed path" }
      let placed = boxed.path.scaledBy(sx: Double(width), sy: Double(height))
        .flattened().flatMap { $0 }
      let published = pair.path.flattened().flatMap { $0 }
      guard placed.count == published.count else {
        return "placed \(placed.count) points, public path \(published.count)"
      }
      for (a, b) in zip(placed, published) where !setGClose(a, b) {
        return "placed \(a) but the public path has \(b)"
      }
      return nil
    }
  }

  private func windowedTrack(_ id: Int) {
    setGProperty(id, setGDraws(6)) { n in
      let reach = setGPow2(16 + n[0] % 15) + Double(n[1] % 1000)
      let extent = setGPow2(16 + n[2] % 15) + Double(n[3] % 1000)
      let row = n[4] % 20
      let aspect = n[5] % 2 == 0 ? 1.0 : 2.0
      let window = Rect(origin: .zero, size: Size(width: 40, height: 20))
      let track = SampledStrokeTrack(
        polylines: [[Point(x: -reach, y: Double(row)), Point(x: extent, y: Double(row))]],
        aspectRatio: aspect, samplingWindow: window)
      for x in 0..<40 {
        let position = track.position(nearestToX: x, y: row)
        let expected = (Double(x) + reach) * 0.5
        if abs(position - expected) > 0.125 + 1e-6 {
          return "subpixel \(x): position \(position), projection \(expected)"
        }
      }
      return nil
    }
  }
}
