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

extension Rasterizer {
  /// - Parameter aspectRatio: Cell height divided by cell width, from the
  ///   resolved style environment's ``CellPixelMetrics``.
  internal func sample(
    _ gradient: AngularGradient,
    in bounds: CellRect,
    aspectRatio: Double,
    x: Int,
    y: Int
  ) -> Color? {
    let stops = gradient.gradient.stops
    guard let first = stops.first else {
      return nil
    }
    guard stops.count > 1, bounds.size.width > 0, bounds.size.height > 0 else {
      return first.color
    }

    let centerX = Double(bounds.origin.x) + gradient.center.x * Double(bounds.size.width)
    let centerY = Double(bounds.origin.y) + gradient.center.y * Double(bounds.size.height)

    // The angle is geometric, as SwiftUI's is: a vertical offset is scaled by
    // the cell aspect ratio, so a quarter turn is a quarter turn on screen and
    // not a quarter of the way round the shape's cell proportions. `y` points
    // down, so the angle increases clockwise, which is also as SwiftUI's does.
    let dx = Double(x) + 0.5 - centerX
    let dy = (Double(y) + 0.5 - centerY) * aspectRatio
    let location = gradient.location(atAngle: atan2(dy, dx))
    return Self.color(in: stops, at: location) ?? first.color
  }

  private static func color(in stops: [Gradient.Stop], at location: Double) -> Color? {
    guard let first = stops.first, let last = stops.last else {
      return nil
    }
    if location <= first.location {
      return first.color
    }
    if location >= last.location {
      return last.color
    }
    for index in 0..<(stops.count - 1) {
      let lower = stops[index]
      let upper = stops[index + 1]
      guard location >= lower.location, location <= upper.location else {
        continue
      }
      let range = max(0.0001, upper.location - lower.location)
      return lower.color.interpolated(
        to: upper.color, progress: (location - lower.location) / range)
    }
    return last.color
  }
}
