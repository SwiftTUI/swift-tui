import SwiftTUICore
import Testing

struct PathArcTests {
  @Test("arc sweeps distinguish zero, full turns, wrapped endpoints and direction")
  func sweeps() {
    func arc(_ degrees: Double, clockwise: Bool = false) -> Path {
      var path = Path()
      path.addArc(
        center: .zero, radius: 1, startAngle: .zero, endAngle: .degrees(degrees),
        clockwise: clockwise)
      return path
    }
    #expect(arc(0).elements.isEmpty)
    #expect(arc(90).elements.count == 2)
    #expect(arc(90, clockwise: true).elements.count == 4)
    #expect(arc(-90).elements.count == 4)
    for degrees in [360.0, -360, 720] {
      for clockwise in [false, true] {
        let path = arc(degrees, clockwise: clockwise)
        #expect(path.elements.count == 5)
        #expect(path.flattened().first?.first == path.flattened().first?.last)
        #expect(path.contains(.zero))
      }
    }
    let forward = arc(90).flattened().flatMap { $0 }
    #expect(forward.allSatisfy { $0.x >= -1e-12 && $0.y >= -1e-12 })
    #expect(abs(forward.last!.x) < 1e-12)
    #expect(abs(forward.last!.y - 1) < 1e-12)
    let reverse = arc(-90, clockwise: true).flattened().flatMap { $0 }
    #expect(reverse.allSatisfy { $0.x >= -1e-12 && $0.y <= 1e-12 })
  }

  @Test("arc construction connects subpaths and ignores invalid geometry atomically")
  func penAndDegenerates() {
    var path = Path { $0.move(to: .zero) }
    path.addArc(
      center: .zero, radius: 1, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
    #expect(path.elements[1] == .line(to: Point(x: 1, y: 0)))
    let original = path
    for radius in [0, -1, Double.nan, .infinity] {
      path.addArc(
        center: .zero, radius: radius, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
      #expect(path == original)
    }
    for value in [Double.nan, .infinity, -.infinity] {
      path.addArc(
        center: .zero, radius: 1, startAngle: .radians(value), endAngle: .zero, clockwise: false)
      #expect(path == original)
    }
    path.addArc(
      center: .init(x: .greatestFiniteMagnitude, y: 0), radius: .greatestFiniteMagnitude,
      startAngle: .zero, endAngle: .degrees(360), clockwise: false)
    #expect(path == original)
    path.close()
    path.addArc(
      center: .init(x: -1, y: 0), radius: 1, startAngle: .zero, endAngle: .degrees(90),
      clockwise: false)
    // Closing restores the subpath pen to the origin, already this arc's start.
    #expect(path.elements.count == original.elements.count + 2)
  }
}
