#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import ucrt
#endif

/// The ordered outline of a curved shape or a custom path, which is what a
/// stroke on the Braille grid draws.
///
/// A rectangle's track is a ring of cells. A curve has no cells to walk, so its
/// track is the outline itself, sampled densely in subpixel space and measured
/// in the same unit as ``RectangleStrokeTrack``: one unit is the width of a
/// cell, and a vertical distance is scaled by the snapped cell aspect ratio. A
/// dash is therefore the same physical length on a `Circle` as on a
/// `Rectangle`.
///
/// The outline starts where SwiftUI starts the shape's path and runs clockwise:
/// an ellipse and a capsule start at the middle of their trailing edge and go
/// down first. A custom path starts where it was authored to.
///
/// The stroke is still rasterized the way it always was. The track only decides
/// which of the lit subpixels a mask keeps, so an unmasked stroke is untouched.
package struct SampledStrokeTrack: Equatable, Sendable {
  /// Outline samples, in subpixel coordinates.
  package private(set) var points: [Point] = []
  /// The track position of each sample.
  package private(set) var positions: [Double] = []
  package private(set) var length: Double = 0

  /// Track units per subpixel. A cell is two subpixels wide and four tall.
  private let unitX: Double
  private let unitY: Double

  /// No sample is further than this from its neighbor, in subpixels, so the
  /// nearest sample to a lit subpixel is a good estimate of its position.
  private static let maximumStep = 0.5

  /// - Parameter polylines: Ordered outlines in subpixel coordinates. Positions
  ///   continue from one polyline to the next, as SwiftUI measures a trim across
  ///   every subpath of a path.
  package init(polylines: [[Point]], aspectRatio: Double) {
    unitX = 0.5
    unitY = RectangleStrokeTrack.snappedAspectRatio(aspectRatio) / 4
    var travelled = 0.0
    for polyline in polylines where polyline.count >= 2 {
      append(polyline[0], at: travelled)
      for index in polyline.indices.dropFirst() {
        let a = polyline[index - 1]
        let b = polyline[index]
        let raw = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
        guard raw > 0 else {
          continue
        }
        let segment = trackDistance(from: a, to: b)
        let steps = max(1, Int((raw / Self.maximumStep).rounded(.up)))
        for step in 1...steps {
          let t = Double(step) / Double(steps)
          append(
            Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
            at: travelled + segment * t)
        }
        travelled += segment
      }
    }
    length = travelled
  }

  private mutating func append(_ point: Point, at position: Double) {
    points.append(point)
    positions.append(position)
  }

  private func trackDistance(from a: Point, to b: Point) -> Double {
    let dx = (b.x - a.x) * unitX
    let dy = (b.y - a.y) * unitY
    return (dx * dx + dy * dy).squareRoot()
  }

  /// The track position of the outline sample nearest a subpixel.
  package func position(nearestToX x: Int, y: Int) -> Double {
    let target = Point(x: Double(x), y: Double(y))
    var best = 0.0
    var bestDistance = Double.infinity
    for index in points.indices {
      let distance = trackDistance(from: points[index], to: target)
      if distance < bestDistance {
        bestDistance = distance
        best = positions[index]
      }
    }
    return best
  }

  /// Clears the lit subpixels the mask turns off.
  package func apply(_ mask: StrokeMask, to canvas: inout BrailleCanvas) {
    guard !mask.isSolid, !points.isEmpty, length > 0 else {
      return
    }
    for y in 0..<canvas.subpixelHeight {
      for x in 0..<canvas.subpixelWidth {
        guard canvas.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4) else {
          continue
        }
        if !mask.isOn(at: position(nearestToX: x, y: y), trackLength: length) {
          canvas.clearPixel(x: x, y: y)
        }
      }
    }
  }
}

extension SampledStrokeTrack {
  private static func arc(
    centerX: Double, centerY: Double, radiusX: Double, radiusY: Double,
    from startAngle: Double, to endAngle: Double
  ) -> [Point] {
    // Angles increase toward +y, which is down, so they run clockwise on
    // screen, as SwiftUI's shapes do.
    let sweep = abs(endAngle - startAngle)
    let steps = max(4, Int((sweep * max(radiusX, radiusY, 1) / maximumStep).rounded(.up)))
    return (0...steps).map { step in
      let angle = startAngle + (endAngle - startAngle) * Double(step) / Double(steps)
      return Point(x: centerX + radiusX * cos(angle), y: centerY + radiusY * sin(angle))
    }
  }

  /// An ellipse, from its trailing point, clockwise.
  package static func ellipse(
    centerX: Int, centerY: Int, radiusX: Int, radiusY: Int, aspectRatio: Double
  ) -> SampledStrokeTrack {
    SampledStrokeTrack(
      polylines: [
        arc(
          centerX: Double(centerX), centerY: Double(centerY),
          radiusX: Double(radiusX), radiusY: Double(radiusY),
          from: 0, to: 2 * .pi)
      ],
      aspectRatio: aspectRatio)
  }

  /// A capsule, from the middle of its trailing edge, clockwise. The cap
  /// parameters are the ones `drawCapsule` strokes with.
  package static func capsule(
    subpixelWidth: Int, subpixelHeight: Int,
    isHorizontal: Bool, radiusX: Int, radiusY: Int,
    aspectRatio: Double
  ) -> SampledStrokeTrack {
    let rx = Double(radiusX)
    let ry = Double(radiusY)
    var outline: [Point] = []
    if isHorizontal {
      let cy = Double((subpixelHeight - 1) / 2)
      let leftCx = rx
      let rightCx = Double(subpixelWidth - 1) - rx
      // Trailing cap's lower quarter, the bottom edge, the leading cap, the top
      // edge, then the trailing cap's upper quarter back to the start.
      outline += arc(
        centerX: rightCx, centerY: cy, radiusX: rx, radiusY: ry, from: 0, to: .pi / 2)
      outline += arc(
        centerX: leftCx, centerY: cy, radiusX: rx, radiusY: ry, from: .pi / 2, to: 3 * .pi / 2)
      outline += arc(
        centerX: rightCx, centerY: cy, radiusX: rx, radiusY: ry, from: 3 * .pi / 2, to: 2 * .pi)
    } else {
      let cx = Double((subpixelWidth - 1) / 2)
      let topCy = ry
      let bottomCy = Double(subpixelHeight - 1) - ry
      // The trailing edge from its middle down, the bottom cap, the leading
      // edge, the top cap, then the trailing edge back down to the start.
      outline.append(Point(x: cx + rx, y: (topCy + bottomCy) / 2))
      outline += arc(
        centerX: cx, centerY: bottomCy, radiusX: rx, radiusY: ry, from: 0, to: .pi)
      outline += arc(
        centerX: cx, centerY: topCy, radiusX: rx, radiusY: ry, from: .pi, to: 2 * .pi)
      outline.append(Point(x: cx + rx, y: (topCy + bottomCy) / 2))
    }
    return SampledStrokeTrack(polylines: [outline], aspectRatio: aspectRatio)
  }

  /// A custom path, mapped onto the subpixel grid as `strokePath` maps it.
  package static func path(
    _ unitPath: Path, subpixelWidth: Int, subpixelHeight: Int, aspectRatio: Double
  ) -> SampledStrokeTrack {
    SampledStrokeTrack(
      polylines:
        unitPath
        .scaledBy(
          sx: Double(max(1, subpixelWidth - 1)), sy: Double(max(1, subpixelHeight - 1))
        )
        .flattened(tolerance: 0.3),
      aspectRatio: aspectRatio)
  }
}
