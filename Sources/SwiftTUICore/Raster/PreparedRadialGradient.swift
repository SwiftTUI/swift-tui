/// A radial gradient with its per-paint invariants computed once
/// (plan 2026-09-24-001 §4C, STUI-618).
///
/// The reference sampler,
/// ``Rasterizer/sample(_:in:aspectRatio:x:y:)``, recomputes the center, the
/// radius normalization, and both stop colors' Oklab conversions on every
/// cell. All of those are functions of the gradient, its bounds, and the
/// cell aspect ratio alone, so this type computes them at style resolution
/// and ``color(atCellX:y:segmentHint:)`` performs only the per-cell work — in
/// the same order, on the same doubles, so every cell resolves to the same
/// `Color` the reference produces. The raster equivalence tests hold that
/// contract by rendering scenes both ways.
///
/// It also derives the gradient's *support*: the annulus outside which every
/// sample has zero alpha and therefore writes nothing. `paintFill` uses it to
/// walk only contributing cells; see ``Support``.
internal struct PreparedRadialGradient: Sendable {
  internal struct Stop: Sendable {
    let location: Double
    let endpoint: PreparedPerceptualMixEndpoint
    var color: Color { endpoint.color }
  }

  /// Radii, in the sampler's aspect-corrected distance units (horizontal
  /// cells), bounding where a sample can have positive alpha.
  ///
  /// Alpha is interpolated linearly between stops and the sampler clamps the
  /// normalized location `t` to `[0, 1]`, so with sorted stops alpha is
  /// positive only strictly between the *last* leading zero-alpha stop and
  /// the *first* trailing zero-alpha stop:
  ///
  /// - inside the last leading transparent stop (`t ≤ its location`) the
  ///   segments mix two zero alphas, or the `t ≤ first.location` shortcut
  ///   returns the first color, and `lerp(0, a, 0)` / `lerp(a, 0, 1)` are
  ///   exactly `0` in IEEE arithmetic;
  /// - at or beyond the first trailing transparent stop the same holds, and
  ///   `t ≥ last.location` returns the last color.
  ///
  /// Converting that open `t` interval to distances gives an open annulus
  /// `(innerRadius, outerRadius)`. A cell whose center distance lies outside
  /// it samples to zero alpha and the reference path skips it *after*
  /// sampling; the support walk skips it before.
  internal struct Support: Sendable {
    /// Distance at or inside which alpha is zero (`0` when the first stop
    /// is opaque, i.e. no hole).
    let innerRadius: Double
    /// Distance at or beyond which alpha is zero.
    let outerRadius: Double
  }

  /// The gradient as authored, for re-preparation after `.opacity` fading
  /// and for the reference sampler under the equivalence switch.
  let gradient: RadialGradient
  let aspectRatio: Double
  let bounds: CellRect
  let stops: [Stop]
  let centerX: Double
  let centerY: Double
  let startRadius: Double
  /// `max(0.0001, endRadius - startRadius)`, kept as a divisor — a reciprocal
  /// multiply would not be bit-exact.
  let denominator: Double
  let hasArea: Bool
  /// Stop locations are non-decreasing. `Gradient.init(stops:)` sorts them,
  /// but `stops` is a public `var`, so a mutated gradient can be unsorted;
  /// the segment search then falls back to the reference's linear scan.
  let isSorted: Bool
  /// `nil` when the gradient is not eligible for the support walk: fewer
  /// than two stops, empty bounds, unsorted or out-of-range locations,
  /// non-finite or non-increasing radii, an opaque last stop (unbounded
  /// support), or an unusable aspect ratio.
  let support: Support?

  init(_ gradient: RadialGradient, aspectRatio: Double, bounds: CellRect) {
    self.gradient = gradient
    self.aspectRatio = aspectRatio
    self.bounds = bounds
    let stops = gradient.gradient.stops.map {
      Stop(location: $0.location, endpoint: PreparedPerceptualMixEndpoint($0.color))
    }
    self.stops = stops
    hasArea = bounds.size.width > 0 && bounds.size.height > 0
    // Center in cell-space coordinates (not normalized); identical to the
    // reference sampler's expression.
    centerX = Double(bounds.origin.x) + gradient.center.x * Double(bounds.size.width)
    centerY = Double(bounds.origin.y) + gradient.center.y * Double(bounds.size.height)
    startRadius = gradient.startRadius
    denominator = max(0.0001, gradient.endRadius - gradient.startRadius)

    var sorted = true
    var locationsInRange = true
    for index in stops.indices {
      let location = stops[index].location
      if !(location >= 0 && location <= 1) {
        locationsInRange = false
      }
      if index > 0, stops[index - 1].location > location {
        sorted = false
      }
    }
    isSorted = sorted

    support = Self.deriveSupport(
      stops: stops,
      isSorted: sorted,
      locationsInRange: locationsInRange,
      hasArea: hasArea,
      startRadius: gradient.startRadius,
      endRadius: gradient.endRadius,
      denominator: denominator,
      aspectRatio: aspectRatio
    )
  }

  private static func deriveSupport(
    stops: [Stop],
    isSorted: Bool,
    locationsInRange: Bool,
    hasArea: Bool,
    startRadius: Double,
    endRadius: Double,
    denominator: Double,
    aspectRatio: Double
  ) -> Support? {
    guard stops.count > 1, hasArea, isSorted, locationsInRange,
      startRadius.isFinite, endRadius.isFinite, endRadius > startRadius,
      aspectRatio.isFinite, aspectRatio > 0,
      let last = stops.last, last.color.alpha == 0
    else {
      return nil
    }
    // Last index of the leading zero-alpha run, if the first stop is
    // transparent.
    var leadingEnd: Int?
    for index in stops.indices where stops[index].color.alpha == 0 {
      if index == 0 || leadingEnd == index - 1 {
        leadingEnd = index
      } else {
        break
      }
    }
    // First index of the trailing zero-alpha run.
    var trailingStart = stops.count - 1
    while trailingStart > 0, stops[trailingStart - 1].color.alpha == 0 {
      trailingStart -= 1
    }
    if let leadingEnd, leadingEnd + 1 >= trailingStart {
      // Every stop is transparent: no sample can write. An empty annulus
      // culls the fill.
      return Support(innerRadius: 0, outerRadius: 0)
    }
    let innerRadius = leadingEnd.map { max(0, startRadius + stops[$0].location * denominator) } ?? 0
    let outerRadius = startRadius + stops[trailingStart].location * denominator
    return Support(innerRadius: innerRadius, outerRadius: max(0, outerRadius))
  }

  /// The color at cell `(x, y)`, bit-identical to the reference sampler.
  ///
  /// `segmentHint` carries the previously matched segment index between
  /// adjacent cells so the stop search resumes near where it last landed
  /// instead of from the first stop. For sorted stops the reference's "first
  /// segment containing `t`" is exactly the smallest index `j` with
  /// `stops[j + 1].location ≥ t` (the `t ≤ first.location` shortcut has
  /// already excluded `t` below the first stop), and the backward-then-forward
  /// scan below lands on that index from any starting hint. For unsorted stops
  /// the search is the reference's linear scan.
  func color(atCellX x: Int, y: Int, segmentHint: inout Int) -> Color? {
    guard let first = stops.first else {
      return nil
    }
    guard stops.count > 1, hasArea else {
      return first.color
    }

    let px = Double(x) + 0.5
    let py = Double(y) + 0.5
    let dx = px - centerX
    let dy = (py - centerY) * aspectRatio
    let distance = (dx * dx + dy * dy).squareRoot()
    let tRaw = (distance - startRadius) / denominator
    let t = min(1, max(0, tRaw))

    if t <= first.location {
      return first.color
    }
    if let last = stops.last, t >= last.location {
      return last.color
    }

    if isSorted {
      var index = min(max(segmentHint, 0), stops.count - 2)
      while index > 0, stops[index].location >= t {
        index -= 1
      }
      while index < stops.count - 2, stops[index + 1].location < t {
        index += 1
      }
      segmentHint = index
      return mix(segment: index, t: t)
    }

    for index in 0..<(stops.count - 1) {
      let lower = stops[index]
      let upper = stops[index + 1]
      guard t >= lower.location, t <= upper.location else {
        continue
      }
      return mix(segment: index, t: t)
    }

    return stops.last?.color
  }

  func color(atCellX x: Int, y: Int) -> Color? {
    var hint = 0
    return color(atCellX: x, y: y, segmentHint: &hint)
  }

  private func mix(segment index: Int, t: Double) -> Color {
    let lower = stops[index]
    let upper = stops[index + 1]
    let range = max(0.0001, upper.location - lower.location)
    let localT = (t - lower.location) / range
    return Color.perceptualMix(lower.endpoint, upper.endpoint, progress: localT)
  }

  /// The aspect-corrected distance from the center to the farthest cell
  /// center of `rect`. The distance is convex in the cell coordinates, so its
  /// maximum over the rectangle's cell centers is attained at a corner cell.
  func farthestCellCenterDistance(in rect: CellRect) -> Double {
    let minX = Double(rect.origin.x) + 0.5
    let maxX = Double(rect.origin.x + rect.size.width - 1) + 0.5
    let minY = Double(rect.origin.y) + 0.5
    let maxY = Double(rect.origin.y + rect.size.height - 1) + 0.5
    var farthest = 0.0
    for (px, py) in [(minX, minY), (maxX, minY), (minX, maxY), (maxX, maxY)] {
      let dx = px - centerX
      let dy = (py - centerY) * aspectRatio
      farthest = max(farthest, (dx * dx + dy * dy).squareRoot())
    }
    return farthest
  }
}
