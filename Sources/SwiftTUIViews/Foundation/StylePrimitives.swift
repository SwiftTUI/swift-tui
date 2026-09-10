public import SwiftTUICore

/// Namespace that mirrors SwiftUI's `VerticalEdge` API over `VerticalEdgeSet`.
public enum VerticalEdge {
  /// Option set containing one or both vertical edges.
  public typealias Set = VerticalEdgeSet
}

/// Column metadata used by `Table`.
public struct TableColumn: Hashable, Sendable {
  /// The text drawn in this column's header cell.
  public var title: String
  /// The column's fixed width in cells, or `nil` to size it from the
  /// available width and the other columns.
  public var width: Int?
  /// How each body cell's content is aligned within the column.
  public var alignment: TableColumnAlignment
  /// How the header cell's title is aligned within the column.
  ///
  /// Defaults to the column's cell alignment when the initializer is not given
  /// one explicitly.
  public var titleAlignment: TableColumnAlignment

  /// Creates a table column.
  ///
  /// - Parameters:
  ///   - title: The header text, copied into a `String`.
  ///   - width: A fixed width in cells, or `nil` to size the column
  ///     automatically. Defaults to `nil`.
  ///   - alignment: How body cells align in the column. Defaults to
  ///     `.leading`.
  ///   - titleAlignment: How the header title aligns. Defaults to `nil`,
  ///     meaning it follows `alignment`.
  public init<S: StringProtocol>(
    _ title: S,
    width: Int? = nil,
    alignment: TableColumnAlignment = .leading,
    titleAlignment: TableColumnAlignment? = nil
  ) {
    self.title = String(title)
    self.width = width
    self.alignment = alignment
    self.titleAlignment = titleAlignment ?? alignment
  }
}

extension LinearGradient {
  /// Creates a linear gradient from explicit stops.
  ///
  /// Use this instead of the color-array form when the stops are unevenly
  /// spaced. The gradient runs from `startPoint` to `endPoint` in the unit
  /// space of the shape it fills.
  ///
  /// - Parameters:
  ///   - stops: The gradient stops, each pairing a color with a location.
  ///   - startPoint: Where the gradient begins, in unit space.
  ///   - endPoint: Where the gradient ends, in unit space.
  public init(
    stops: [Gradient.Stop],
    startPoint: UnitPoint,
    endPoint: UnitPoint
  ) {
    self.init(
      gradient: Gradient(stops: stops),
      startPoint: startPoint,
      endPoint: endPoint
    )
  }
}

extension ShapeStyle where Self == LinearGradient {
  /// A linear gradient interpolating evenly through the given colors.
  ///
  /// The dot-shorthand form, for use where a `ShapeStyle` is expected.
  ///
  /// - Parameters:
  ///   - colors: The colors to interpolate, spaced evenly from start to end.
  ///   - startPoint: Where the gradient begins, in unit space.
  ///   - endPoint: Where the gradient ends, in unit space.
  /// - Returns: The linear gradient.
  public static func linearGradient(
    colors: [Color],
    startPoint: UnitPoint,
    endPoint: UnitPoint
  ) -> Self {
    .init(
      colors: colors,
      startPoint: startPoint,
      endPoint: endPoint
    )
  }

  /// A linear gradient interpolating through explicitly located stops.
  ///
  /// The dot-shorthand form, for use where a `ShapeStyle` is expected.
  ///
  /// - Parameters:
  ///   - stops: The gradient stops, each pairing a color with a location.
  ///   - startPoint: Where the gradient begins, in unit space.
  ///   - endPoint: Where the gradient ends, in unit space.
  /// - Returns: The linear gradient.
  public static func linearGradient(
    stops: [Gradient.Stop],
    startPoint: UnitPoint,
    endPoint: UnitPoint
  ) -> Self {
    .init(
      stops: stops,
      startPoint: startPoint,
      endPoint: endPoint
    )
  }
}

extension RadialGradient {
  /// Creates a radial gradient from explicit stops.
  ///
  /// The gradient runs outward from `center`, starting at `startRadius` and
  /// reaching the last stop at `endRadius`.
  ///
  /// - Parameters:
  ///   - stops: The gradient stops, each pairing a color with a location.
  ///   - center: The center of the gradient in unit space. Defaults to the
  ///     shape's center.
  ///   - startRadius: The radius at which the first stop sits. Defaults to 0.
  ///   - endRadius: The radius at which the last stop sits.
  public init(
    stops: [Gradient.Stop],
    center: UnitPoint = .center,
    startRadius: Double = 0,
    endRadius: Double
  ) {
    self.init(
      gradient: Gradient(stops: stops),
      center: center,
      startRadius: startRadius,
      endRadius: endRadius
    )
  }
}

extension ShapeStyle where Self == RadialGradient {
  /// A radial gradient interpolating evenly through the given colors.
  ///
  /// The dot-shorthand form, for use where a `ShapeStyle` is expected.
  ///
  /// - Parameters:
  ///   - colors: The colors to interpolate, spaced evenly from the start
  ///     radius to the end radius.
  ///   - center: The center of the gradient in unit space. Defaults to the
  ///     shape's center.
  ///   - startRadius: The radius at which the first color sits. Defaults to 0.
  ///   - endRadius: The radius at which the last color sits.
  /// - Returns: The radial gradient.
  public static func radialGradient(
    colors: [Color],
    center: UnitPoint = .center,
    startRadius: Double = 0,
    endRadius: Double
  ) -> Self {
    .init(
      colors: colors,
      center: center,
      startRadius: startRadius,
      endRadius: endRadius
    )
  }

  /// A radial gradient interpolating through explicitly located stops.
  ///
  /// The dot-shorthand form, for use where a `ShapeStyle` is expected.
  ///
  /// - Parameters:
  ///   - stops: The gradient stops, each pairing a color with a location.
  ///   - center: The center of the gradient in unit space. Defaults to the
  ///     shape's center.
  ///   - startRadius: The radius at which the first stop sits. Defaults to 0.
  ///   - endRadius: The radius at which the last stop sits.
  /// - Returns: The radial gradient.
  public static func radialGradient(
    stops: [Gradient.Stop],
    center: UnitPoint = .center,
    startRadius: Double = 0,
    endRadius: Double
  ) -> Self {
    .init(
      stops: stops,
      center: center,
      startRadius: startRadius,
      endRadius: endRadius
    )
  }
}
