public import SwiftTUICore

/// Namespace that mirrors SwiftUI's `VerticalEdge` API over `VerticalEdgeSet`.
public enum VerticalEdge {
  /// Option set containing one or both vertical edges.
  public typealias Set = VerticalEdgeSet
}

/// Column metadata used by `Table`.
public struct TableColumn: Hashable, Sendable {
  public var title: String
  public var width: Int?
  public var alignment: TableColumnAlignment
  public var titleAlignment: TableColumnAlignment

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
