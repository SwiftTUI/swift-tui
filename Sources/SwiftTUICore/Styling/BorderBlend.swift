/// A 1D gradient sampled continuously around a border's perimeter.
///
/// `BorderBlend` drives border foreground colors by walking the
/// rectangle's edge cells clockwise (top L→R, right T→B, bottom R→L,
/// left B→T) and interpolating between `stops` based on the cell's
/// position around the perimeter. The `phase` parameter rotates the
/// gradient start point around the perimeter, enabling chasing-light
/// animation when driven by the animation pipeline in a later task.
///
/// Stops use the same `(location, color)` shape as ``Gradient/Stop``
/// where `location` is in `[0, 1]`. To produce a closed loop (the
/// typical chasing-light effect), repeat the first color as the last
/// stop: `BorderBlend([.red, .blue, .red])` fades red → blue → red
/// smoothly around the perimeter.
public struct BorderBlend: Equatable, Sendable {
  public var stops: [Gradient.Stop]

  public init(stops: [Gradient.Stop]) {
    self.stops = stops.sorted { $0.location < $1.location }
  }

  /// Evenly-spaced stops built from a color list. The first and
  /// last colors are placed at locations 0 and 1 respectively; to
  /// close the loop, pass the first color again at the end.
  public init(_ colors: [Color]) {
    guard !colors.isEmpty else {
      self.stops = []
      return
    }
    if colors.count == 1 {
      self.stops = [.init(color: colors[0], location: 0)]
      return
    }
    let denominator = Double(colors.count - 1)
    self.stops = colors.enumerated().map { index, color in
      .init(color: color, location: Double(index) / denominator)
    }
  }
}

extension BorderBlend {
  /// Returns the color for a cell at normalized position `t in [0, 1]`
  /// along the gradient, interpolating between adjacent stops using
  /// ``Color/interpolated(to:progress:method:)``.
  ///
  /// Out-of-range `t` is clamped. Empty stops returns nil.
  public func color(at t: Double) -> Color? {
    guard let first = stops.first else { return nil }
    guard stops.count > 1 else { return first.color }

    let clamped = min(1, max(0, t))
    if clamped <= first.location { return first.color }
    if let last = stops.last, clamped >= last.location { return last.color }

    for index in 0..<(stops.count - 1) {
      let lower = stops[index]
      let upper = stops[index + 1]
      guard clamped >= lower.location, clamped <= upper.location else { continue }
      let range = max(0.0001, upper.location - lower.location)
      let localT = (clamped - lower.location) / range
      return lower.color.interpolated(to: upper.color, progress: localT)
    }
    return stops.last?.color
  }

  /// Samples a color for every cell on the perimeter of a rectangle
  /// with dimensions `(width × height)`, walking clockwise:
  ///   top edge L→R, right edge T→B, bottom edge R→L, left edge B→T.
  ///
  /// The total number of perimeter cells is `2*(width + height) - 4`
  /// for `width ≥ 2 && height ≥ 2`. Degenerate sizes return a flat
  /// array sized to whatever perimeter exists:
  ///  - `1×1` → 1 cell
  ///  - `N×1` → N cells
  ///  - `1×N` → N cells
  ///
  /// `phase` rotates the start point around the perimeter: a phase of
  /// `0.25` shifts the gradient start by 25% of the perimeter length.
  public func samplePerimeter(
    width: Int,
    height: Int,
    phase: Double = 0
  ) -> [Color] {
    guard !stops.isEmpty, width > 0, height > 0 else {
      return []
    }

    let total: Int
    if width == 1 && height == 1 {
      total = 1
    } else if width == 1 {
      total = height
    } else if height == 1 {
      total = width
    } else {
      total = 2 * (width + height) - 4
    }

    guard total > 0 else { return [] }

    var colors: [Color] = []
    colors.reserveCapacity(total)
    let phaseRemainder = phase.truncatingRemainder(dividingBy: 1)
    let normalizedPhase = phaseRemainder < 0 ? phaseRemainder + 1 : phaseRemainder
    // The perimeter is treated as a circle: cell 0 is at t = 0 and
    // cell (total - 1) is at t = (total - 1) / total, one slot before
    // wrapping back to cell 0. Spacing each cell by exactly `1 / total`
    // gives uniform angular steps around the loop — required so that a
    // phase shift of `1 / total` advances every cell by exactly one
    // slot (chasing-light animation) and so that the cell immediately
    // before the seam does not collide with the cell at the seam.
    let totalD = Double(total)
    for i in 0..<total {
      let raw = (Double(i) / totalD) + normalizedPhase
      var t = raw.truncatingRemainder(dividingBy: 1)
      if t < 0 { t += 1 }
      let sampled = color(at: t) ?? stops[0].color
      colors.append(sampled)
    }
    return colors
  }
}
