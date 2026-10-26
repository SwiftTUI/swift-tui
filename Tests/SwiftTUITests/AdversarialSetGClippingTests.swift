import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIPrimitives

/// A finite coordinate of magnitude 2^-60 ... greatestFiniteMagnitude, either sign.
private func setGCoordinate(_ raw: Int) -> Double {
  let exponent = raw % 1084 - 60
  let significand = 1 + Double((raw / 1084) % 1024) / 1024
  let sign: FloatingPointSign = (raw / (1084 * 1024)) % 2 == 0 ? .plus : .minus
  return Double(sign: sign, exponent: exponent, significand: significand)
}

private let setGCoordinateDraws = 0...(1084 * 1024 * 2 - 1)
private let setGOdds: [Double] = [1, 3, 5, 7, 9, 11, 13]

/// Samples the canvas lights, read back by probing each sample.
private func setGLitSamples(_ buffer: CanvasGridBuffer) -> Set<[Int]> {
  var lit = Set<[Int]>()
  for y in 0..<buffer.pixelHeight {
    for x in 0..<buffer.pixelWidth {
      var probe = buffer
      probe.setPixel(x: x, y: y)
      if probe == buffer { lit.insert([x, y]) }
    }
  }
  return lit
}

/// Whether every sample of `a` has a sample of `b` within Chebyshev distance 1.
private func setGNear(_ a: Set<[Int]>, _ b: Set<[Int]>) -> Bool {
  a.allSatisfy { sample in
    b.contains { abs($0[0] - sample[0]) <= 1 && abs($0[1] - sample[1]) <= 1 }
  }
}

/// `floor(sqrt(value))`, exactly.
private func setGIntegerSquareRoot(_ value: UInt128) -> UInt128 {
  var low: UInt128 = 0
  var high: UInt128 = 1 << 64
  while low < high {
    let middle = (low + high + 1) / 2
    if middle * middle <= value { low = middle } else { high = middle - 1 }
  }
  return low
}

@MainActor
@Suite("Campaign F5 pass 2 clipping properties", .serialized)
struct AdversarialSetGClippingTests {
  @Test(arguments: Array(101...111))
  func clipping(id: Int) {
    switch id {
    case 101: clippedInsideSquare(id)
    case 102: clippedStaysOnLine(id)
    case 103: insideUnchangedOutsideRejected(id)
    case 104: scaleEquivariance(id)
    case 105: subnormalMinorCoordinate(id)
    case 106: parameterIntervalMaximal(id)
    case 107: farCanvasLine(id)
    case 108: clippedBresenham(id)
    case 109: parametricOutline(id)
    case 110: fillCircleSpans(id)
    default: containmentScaling(id)
    }
  }

  private func clippedInsideSquare(_ id: Int) {
    setGProperty(id, setGDraws(5, setGCoordinateDraws)) { n in
      let limit = [1, 1000, setGPow2(59), setGPow2(60)][n[4] % 4]
      let a = Point(x: setGCoordinate(n[0]), y: setGCoordinate(n[1]))
      let b = Point(x: setGCoordinate(n[2]), y: setGCoordinate(n[3]))
      guard let c = SegmentClipping.clipped(from: a, to: b, within: limit) else { return nil }
      let values = [c.start.x, c.start.y, c.end.x, c.end.y]
      return values.allSatisfy { abs($0) <= limit } ? nil : "clipped \(values) outside \(limit)"
    }
  }

  private func clippedStaysOnLine(_ id: Int) {
    setGProperty(id, setGDraws(6)) { n in
      let p = Double(n[0] % 7 + 1)
      let q = Double(n[1] % 15 - 7)
      let s = setGOdds[n[2] % 7] * setGPow2(56 + n[3] % 65)
      let t = setGOdds[n[4] % 7] * setGPow2(56 + n[5] % 65)
      let limit = setGPow2(59)
      let a = Point(x: -s * p, y: -s * q)
      let b = Point(x: t * p, y: t * q)
      guard let c = SegmentClipping.clipped(from: a, to: b, within: limit) else {
        return "a segment through the origin was rejected"
      }
      let tolerance = setGPow2(-40) * limit * (abs(p) + abs(q))
      for point in [c.start, c.end] {
        let residual = abs(point.y * p - point.x * q)
        if !(residual <= tolerance) {
          return "clipped \(point) is \(residual) off the line (tolerance \(tolerance))"
        }
      }
      return nil
    }
  }

  private func insideUnchangedOutsideRejected(_ id: Int) {
    setGProperty(id, setGDraws(7)) { n in
      let limit = [1, 1000, setGPow2(59)][n[0] % 3]
      func inside(_ raw: Int) -> Double { limit * (Double(raw % 2001) - 1000) / 1000 }
      let a = Point(x: inside(n[1]), y: inside(n[2]))
      let b = Point(x: inside(n[3]), y: inside(n[4]))
      guard let c = SegmentClipping.clipped(from: a, to: b, within: limit) else {
        return "inside segment rejected"
      }
      let before = [a.x, a.y, b.x, b.y].map(\.bitPattern)
      let after = [c.start.x, c.start.y, c.end.x, c.end.y].map(\.bitPattern)
      if before != after { return "inside segment changed" }
      let beyond = limit * (1 + Double(n[5] % 100 + 1) / 100)
      let other = limit * (1 + Double(n[6] % 100 + 1) / 100)
      let side = Point(x: beyond, y: inside(n[1]))
      let far = Point(x: other, y: inside(n[2]))
      if SegmentClipping.clipped(from: side, to: far, within: limit) != nil {
        return "segment beyond the trailing edge admitted"
      }
      return nil
    }
  }

  private func scaleEquivariance(_ id: Int) {
    setGProperty(id, setGDraws(5, setGCoordinateDraws)) { n in
      let a = Point(x: setGCoordinate(n[0]), y: setGCoordinate(n[1]))
      let b = Point(x: setGCoordinate(n[2]), y: setGCoordinate(n[3]))
      let factor = setGPow2(n[4] % 68 - 64)
      let limit = setGPow2(59)
      let original = [a.x, a.y, b.x, b.y]
      let scaled = original.map { $0 * factor }
      guard scaled.allSatisfy({ $0.isNormal }) else { return nil }
      let base = SegmentClipping.clipped(from: a, to: b, within: limit)
      let image = SegmentClipping.clipped(
        from: Point(x: scaled[0], y: scaled[1]), to: Point(x: scaled[2], y: scaled[3]),
        within: limit * factor)
      switch (base, image) {
      case (nil, nil):
        return nil
      case (let base?, let image?):
        let expected = [base.start.x, base.start.y, base.end.x, base.end.y].map { $0 * factor }
        guard expected.allSatisfy({ $0 == 0 || $0.isNormal }) else { return nil }
        let actual = [image.start.x, image.start.y, image.end.x, image.end.y]
        return expected == actual ? nil : "scaled clip \(actual) != \(expected)"
      default:
        return
          "acceptance differs: base \(String(describing: base)), scaled \(String(describing: image))"
      }
    }
  }

  private func subnormalMinorCoordinate(_ id: Int) {
    setGProperty(id, setGDraws(3)) { n in
      let reach = Double(
        sign: .plus, exponent: 1023, significand: 1 + Double(n[0] % 1000) / 1000)
      let sign: Double = n[2] % 2 == 0 ? 1 : -1
      let y = sign * Double.leastNonzeroMagnitude * Double(2 * (n[1] % 1000) + 1)
      let limit = setGPow2(59)
      guard
        let c = SegmentClipping.clipped(
          from: Point(x: -reach, y: y), to: Point(x: reach, y: y), within: limit)
      else { return "horizontal segment rejected" }
      let exact =
        c.start.x == -limit && c.end.x == limit && c.start.y.bitPattern == y.bitPattern
        && c.end.y.bitPattern == y.bitPattern
      return exact ? nil : "clipped (\(c.start), \(c.end)); expected y \(y) on both ends"
    }
  }

  private func parameterIntervalMaximal(_ id: Int) {
    setGProperty(id, setGDraws(8)) { n in
      let start = Point(x: Double(n[0] % 41 - 20), y: Double(n[1] % 41 - 20))
      let end = Point(x: Double(n[2] % 41 - 20), y: Double(n[3] % 41 - 20))
      let minX = Double(n[4] % 21 - 10)
      let maxX = minX + Double(n[5] % 11)
      let minY = Double(n[6] % 21 - 10)
      let maxY = minY + Double(n[7] % 11)
      func point(_ t: Double) -> Point {
        Point(x: start.x + t * (end.x - start.x), y: start.y + t * (end.y - start.y))
      }
      func inBox(_ p: Point, slack: Double) -> Bool {
        p.x >= minX - slack && p.x <= maxX + slack && p.y >= minY - slack && p.y <= maxY + slack
      }
      guard
        let interval = SegmentClipping.parameterInterval(
          from: start, to: end, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
      else {
        for step in 0...4096 where inBox(point(Double(step) / 4096), slack: -1e-9) {
          return "nil although t = \(step)/4096 lies inside"
        }
        return nil
      }
      guard 0 <= interval.lower, interval.lower <= interval.upper, interval.upper <= 1 else {
        return "interval \(interval) out of order"
      }
      guard inBox(point(interval.lower), slack: 1e-9), inBox(point(interval.upper), slack: 1e-9)
      else { return "interval \(interval) has an endpoint outside the box" }
      let delta = 1e-6
      if interval.lower - delta >= 0, inBox(point(interval.lower - delta), slack: -1e-9) {
        return "interval \(interval) is not maximal below"
      }
      if interval.upper + delta <= 1, inBox(point(interval.upper + delta), slack: -1e-9) {
        return "interval \(interval) is not maximal above"
      }
      return nil
    }
  }

  private func farCanvasLine(_ id: Int) {
    setGProperty(id, setGDraws(6)) { n in
      let p = Double(n[0] % 5 + 1)
      let q = Double(n[1] % 5 + 1)
      let s = setGOdds[n[2] % 7] * setGPow2(60 + n[3] % 51)
      let t = setGOdds[n[4] % 7] * setGPow2(60 + n[5] % 51)
      func lit(from a: Point, to b: Point) -> Set<[Int]> {
        var context = CanvasContext(
          canvas: CanvasGridBuffer(size: CellSize(width: 8, height: 4), grid: .braille2x4),
          foreground: .white, background: nil)
        context.line(from: a, to: b)
        return setGLitSamples(context.canvas)
      }
      let near = lit(from: Point(x: -8 * p, y: -8 * q), to: Point(x: 64 * p, y: 64 * q))
      let far = lit(from: Point(x: -s * p, y: -s * q), to: Point(x: t * p, y: t * q))
      guard !far.isEmpty else { return "far line lit nothing; near line lit \(near.count)" }
      return setGNear(far, near) && setGNear(near, far)
        ? nil
        : "far line lit \(far.sorted { $0.lexicographicallyPrecedes($1) }.prefix(6)), near lit \(near.sorted { $0.lexicographicallyPrecedes($1) }.prefix(6))"
    }
  }

  private func clippedBresenham(_ id: Int) {
    setGProperty(id, setGDraws(7)) { n in
      let width = n[0] % 24 + 1
      let height = n[1] % 24 + 1
      let span = n[6] % 2 == 0 ? 801 : 81
      let shift = span == 801 ? 400 : 30
      let start = (x: n[2] % span - shift, y: n[3] % span - shift)
      let end = (x: n[4] % span - shift, y: n[5] % span - shift)
      var clipped = Set<[Int]>()
      ClippedRaster.line(from: start, to: end, width: width, height: height) {
        clipped.insert([$0, $1])
      }
      let reference = Set(
        setGBresenham(from: start, to: end).filter {
          $0[0] >= 0 && $0[0] < width && $0[1] >= 0 && $0[1] < height
        })
      return clipped == reference
        ? nil
        : "clipped \(clipped.subtracting(reference)) extra, \(reference.subtracting(clipped)) missing"
    }
  }

  private func parametricOutline(_ id: Int) {
    setGProperty(id, setGDraws(7)) { n in
      let width = n[0] % 12 + 1
      let height = n[1] % 12 + 1
      let threshold = 4096 + 4 * (width + height)
      var radiusX = n[2] % 3000 + 1
      let radiusY = n[3] % 3000 + 1
      if radiusX + radiusY <= threshold { radiusX += threshold }
      let angle =
        n[4] % 3604 < 3600
        ? 2 * Double.pi * Double(n[4] % 3604) / 3600 : Double(n[4] % 3604 - 3600) * Double.pi / 2
      let centerX = -Int((Double(radiusX) * cos(angle)).rounded()) + n[5] % (width + 21) - 10
      let centerY = -Int((Double(radiusY) * sin(angle)).rounded()) + n[6] % (height + 21) - 10
      var walked = Set<[Int]>()
      let accepted = ClippedRaster.parametricOutline(
        centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY, minimumSteps: 32,
        width: width, height: height
      ) { walked.insert([$0, $1]) }
      guard accepted else { return nil }
      func inBuffer(_ sample: [Int]) -> Bool {
        sample[0] >= 0 && sample[0] < width && sample[1] >= 0 && sample[1] < height
      }
      let steps = max(32, 4 * (radiusX + radiusY))
      let twoPi = 2.0 * .pi
      var reference = Set<[Int]>()
      var previous: (x: Int, y: Int)?
      for index in 0...steps {
        let theta = twoPi * Double(index) / Double(steps)
        let point = (
          x: centerX + Int((Double(radiusX) * cos(theta)).rounded()),
          y: centerY + Int((Double(radiusY) * sin(theta)).rounded())
        )
        if let previous {
          if max(previous.x, point.x) >= 0, min(previous.x, point.x) < width,
            max(previous.y, point.y) >= 0, min(previous.y, point.y) < height
          {
            for sample in setGBresenham(from: previous, to: point) where inBuffer(sample) {
              reference.insert(sample)
            }
          }
        } else if inBuffer([point.x, point.y]) {
          reference.insert([point.x, point.y])
        }
        previous = point
      }
      return walked == reference
        ? nil
        : "outline \(walked.subtracting(reference)) extra, \(reference.subtracting(walked)) missing"
    }
  }

  private func fillCircleSpans(_ id: Int) {
    setGProperty(id, setGDraws(4)) { n in
      let exponent = n[0] % 31 + 10
      let radius = (1 << exponent) + n[1] % (1 << min(exponent, 20))
      var canvas = BrailleCanvas(width: 4, height: 4)
      let centerX = radius + n[2] % 8
      let centerY = n[3] % 16
      canvas.fillCircle(centerX: centerX, centerY: centerY, radius: radius)
      for y in 0..<16 {
        let dy = y - centerY
        let span = Int(
          setGIntegerSquareRoot(
            UInt128(radius) * UInt128(radius) - UInt128(dy.magnitude) * UInt128(dy.magnitude)))
        for x in 0..<8 {
          let expected = (x - centerX).magnitude <= span
          let actual = canvas.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4)
          if expected != actual {
            return "r \(radius), dy \(dy): dot \(x) lit \(actual), exact span \(span)"
          }
        }
      }
      return nil
    }
  }

  private func containmentScaling(_ id: Int) {
    setGProperty(id, setGDraws(12)) { n in
      let count = 3 + n[0] % 2
      var path = Path()
      for vertex in 0..<count {
        let point = Point(
          x: Double(n[1 + 2 * vertex] % 17 - 8), y: Double(n[2 + 2 * vertex] % 17 - 8))
        if vertex == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      path.close()
      let query = Point(x: Double(n[9] % 17 - 8) + 0.375, y: Double(n[10] % 17 - 8) + 0.625)
      let factor = setGPow2(n[11] % 1011)
      let expected = path.contains(query)
      let actual = path.scaledBy(sx: factor, sy: factor).contains(
        Point(x: query.x * factor, y: query.y * factor))
      return expected == actual
        ? nil : "contains \(expected) at unit scale, \(actual) at scale \(factor)"
    }
  }
}
