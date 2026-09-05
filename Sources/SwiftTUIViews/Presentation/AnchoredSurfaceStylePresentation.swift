public import SwiftTUICore

/// Insets, sizing, and paint for an anchored menu or popover surface.
public struct AnchoredSurfaceStylePresentation: Sendable, Equatable {
  public var contentInsets: EdgeInsets
  public var minimumWidth: Int
  public var maximumWidth: Int?
  /// Maximum content viewport height, before insets. `Int.max` is unbounded.
  public var maximumHeight: Int
  public var backgroundStyle: AnyShapeStyle
  public var borderStroke: StrokeStyle
  /// Border paint. A nil value uses the theme's accent border.
  public var borderStyle: AnyShapeStyle?

  public init(
    contentInsets: EdgeInsets = .init(horizontal: 1, vertical: 1),
    minimumWidth: Int = 0,
    maximumWidth: Int? = nil,
    maximumHeight: Int = .max,
    backgroundStyle: AnyShapeStyle = AnyShapeStyle(.terminalSurfaceBackground),
    borderStroke: StrokeStyle = StrokeStyle(borderSet: .innerHalfBlock, placement: .outset),
    borderStyle: AnyShapeStyle? = nil
  ) {
    self.contentInsets = contentInsets
    self.minimumWidth = minimumWidth
    self.maximumWidth = maximumWidth
    self.maximumHeight = maximumHeight
    self.backgroundStyle = backgroundStyle
    self.borderStroke = borderStroke
    self.borderStyle = borderStyle
  }
}

extension AnchoredSurfaceStylePresentation {
  package var validationProblems: [String] {
    var problems: [String] = []
    if minimumWidth < 0 { problems.append("minimumWidth must not be negative") }
    if let maximumWidth, maximumWidth <= 0 || maximumWidth < minimumWidth {
      problems.append("maximumWidth must be positive and at least minimumWidth")
    }
    if maximumHeight <= 0 { problems.append("maximumHeight must be positive") }
    let insets = [
      contentInsets.top, contentInsets.leading, contentInsets.bottom, contentInsets.trailing,
    ]
    if insets.contains(where: { $0 < 0 }) {
      problems.append("contentInsets must not be negative")
    }
    if contentInsets.leading.addingReportingOverflow(contentInsets.trailing).overflow
      || contentInsets.top.addingReportingOverflow(contentInsets.bottom).overflow
    {
      problems.append("contentInsets must fit within the cell coordinate range")
    }
    return problems
  }
}
