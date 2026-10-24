@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore

@MainActor
@Suite("Campaign F5 path properties", .serialized)
struct AdversarialSetGGeometryTests {
  @Test(arguments: Array(41...60))
  func geometry(id: Int) {
    setGCheck(id, setGNumbers) { n in
      let x = Double(n[0] % 9 - 4)
      let y = Double(n[1] % 9 - 4)
      let width = Double(n[2] % 8 + 1)
      let height = Double(n[3] % 8 + 1)
      let rect = Rect(origin: .init(x: x, y: y), size: .init(width: width, height: height))
      let path = Path(rect)
      let query = Point(x: x + Double(n[0] % 13 - 2), y: y + Double(n[1] % 13 - 2))
      let sx = Double(n[2] % 4 + 1)
      let sy = Double(n[3] % 4 + 1)
      let dx = Double(n[0] % 7 - 3)
      let dy = Double(n[1] % 7 - 3)
      var triangle = Path()
      triangle.move(to: .init(x: x, y: y))
      triangle.addLine(to: .init(x: x + width, y: y))
      triangle.addLine(to: .init(x: x, y: y + height))
      var line = Path()
      line.move(to: .init(x: x, y: y))
      line.addLine(to: .init(x: x + width, y: y))
      switch id {
      case 41:
        return path.contains(query)
          == path.translatedBy(dx: dx, dy: dy).contains(.init(x: query.x + dx, y: query.y + dy))
          ? nil : "translation containment"
      case 42:
        return path.contains(query)
          == path.scaledBy(sx: sx, sy: sy).contains(.init(x: query.x * sx, y: query.y * sy))
          ? nil : "scale containment"
      case 43:
        return path.contains(query)
          == path.scaledBy(sx: -1, sy: 1).contains(.init(x: -query.x, y: query.y))
          ? nil : "reflection containment"
      case 44:
        let expected = Rect(origin: .init(x: x + dx, y: y + dy), size: rect.size)
        return path.translatedBy(dx: dx, dy: dy).boundingRect == expected
          ? nil : "translated bounds"
      case 45:
        let expected = Rect(
          origin: .init(x: x * sx, y: y * sy), size: .init(width: width * sx, height: height * sy))
        return path.scaledBy(sx: sx, sy: sy).boundingRect == expected ? nil : "scaled bounds"
      case 46:
        var closed = triangle
        closed.close()
        return triangle.contains(query) == closed.contains(query) ? nil : "implicit closure"
      case 47, 48:
        var doubled = path
        doubled.addRect(rect)
        let inside = Point(x: x + width / 2, y: y + height / 2)
        return doubled.contains(inside, fillRule: id == 47 ? .evenOdd : .nonZero) == (id == 48)
          ? nil : "duplicate contour fill"
      case 49:
        let fraction = Double(n[0] % 9) / 8
        let points = [
          Point(x: x, y: y + height * fraction), Point(x: x + width, y: y + height * fraction),
          Point(x: x + width * fraction, y: y), Point(x: x + width * fraction, y: y + height),
        ]
        return points.allSatisfy { path.contains($0) } ? nil : "boundary excluded"
      case 50:
        var curve = Path()
        curve.move(to: .init(x: x, y: y))
        curve.addCurve(
          to: .init(x: x + width, y: y), control1: .init(x: x, y: y + height),
          control2: .init(x: x + width, y: y - height))
        guard let bounds = curve.boundingRect else { return "missing cubic hull" }
        let points: [Point] = curve.flattened().flatMap { $0 }
        let minimumX = bounds.origin.x - 1e-8
        let maximumX = bounds.origin.x + bounds.size.width + 1e-8
        let minimumY = bounds.origin.y - 1e-8
        let maximumY = bounds.origin.y + bounds.size.height + 1e-8
        let inside = points.allSatisfy { point in
          let horizontal = point.x >= minimumX && point.x <= maximumX
          let vertical = point.y >= minimumY && point.y <= maximumY
          return horizontal && vertical
        }
        return inside ? nil : "flattened curve escaped hull"
      case 51, 52:
        let lower = Double(n[0] % 4) / 8
        let upper = 0.5 + Double(n[1] % 5) / 8
        let first = line.trimmedPath(from: lower, to: upper)
        let result = id == 51 ? first : first.trimmedPath(from: 0.25, to: 0.75)
        let lo = id == 51 ? lower : lower + (upper - lower) * 0.25
        let hi = id == 51 ? upper : lower + (upper - lower) * 0.75
        let points = result.flattened().flatMap { $0 }
        guard let a = points.first, let b = points.last else { return "missing trimmed line" }
        return setGPointNear(a, .init(x: x + width * lo, y: y))
          && setGPointNear(b, .init(x: x + width * hi, y: y)) ? nil : "trim endpoints \(points)"
      case 53:
        let fraction = Double(n[0]) / 255
        return line.trimmedPath(from: fraction, to: fraction).elements.isEmpty
          ? nil : "zero interval is nonempty"
      case 54:
        return line.trimmedPath(from: .nan, to: 1).elements.isEmpty
          && line.trimmedPath(from: 0, to: .nan).elements.isEmpty ? nil : "NaN trim"
      case 55:
        return line.trimmedPath(from: -.infinity, to: .infinity).elements
          == line.trimmedPath(from: 0, to: 1).elements ? nil : "infinite clamp"
      case 56:
        return [Double.nan, .infinity, -.infinity].allSatisfy {
          !path.contains(.init(x: $0, y: y)) && !path.contains(.init(x: x, y: $0))
        } ? nil : "nonfinite query admitted"
      case 57:
        var bad = triangle
        bad.addLine(to: .init(x: .nan, y: y))
        return bad.boundingRect == nil && bad.flattened().isEmpty
          ? nil : "nonfinite path has geometry"
      case 58:
        return triangle.translatedBy(dx: dx, dy: dy).translatedBy(dx: -dx, dy: -dy).elements
          == triangle.elements ? nil : "inverse translation"
      case 59:
        triangle.close()
        let points = triangle.flattened().flatMap { $0 }
        return points.count >= 4 && points.first == points.last ? nil : "closed flatten endpoint"
      default:
        let points = triangle.flattened().flatMap { $0 }
        return points.count == 3 && points.first != points.last ? nil : "open flatten closes"
      }
    }
  }
}
