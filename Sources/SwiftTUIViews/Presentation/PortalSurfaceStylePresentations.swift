public import SwiftTUICore

/// Paint and dimensions shared by alert and confirmation-dialog surfaces.
///
/// Alignment, accessibility, default actions, and dismissal belong to the
/// declaration and are intentionally absent from this value.
public struct PromptSurfaceStylePresentation: Sendable, Equatable {
  public var backdropOpacity: Double
  public var headerTone: TerminalTone
  public var minimumWidth: Int
  public var maximumWidth: Int?
  public var scrollMinimumHeight: Int
  public var scrollIdealHeight: Int
  public var scrollMaximumHeight: Int
  public var contentInsets: EdgeInsets
  public var backgroundStyle: AnyShapeStyle?
  public var borderStroke: StrokeStyle
  public var borderStyle: AnyShapeStyle?

  public init(
    backdropOpacity: Double = 0,
    headerTone: TerminalTone = .neutral,
    minimumWidth: Int = 24,
    maximumWidth: Int? = 48,
    scrollMinimumHeight: Int = 2,
    scrollIdealHeight: Int = 6,
    scrollMaximumHeight: Int = 10,
    contentInsets: EdgeInsets = .init(horizontal: 1, vertical: 1),
    backgroundStyle: AnyShapeStyle? = nil,
    borderStroke: StrokeStyle = .single,
    borderStyle: AnyShapeStyle? = nil
  ) {
    self.backdropOpacity = backdropOpacity
    self.headerTone = headerTone
    self.minimumWidth = minimumWidth
    self.maximumWidth = maximumWidth
    self.scrollMinimumHeight = scrollMinimumHeight
    self.scrollIdealHeight = scrollIdealHeight
    self.scrollMaximumHeight = scrollMaximumHeight
    self.contentInsets = contentInsets
    self.backgroundStyle = backgroundStyle
    self.borderStroke = borderStroke
    self.borderStyle = borderStyle
  }
}

/// Insets and paint for a surface that always fills the terminal.
///
/// A full-screen cover has no framework header or border.
public struct FullScreenSurfaceStylePresentation: Sendable, Equatable {
  public var contentInsets: EdgeInsets
  public var backgroundStyle: AnyShapeStyle

  public init(
    contentInsets: EdgeInsets = .zero,
    backgroundStyle: AnyShapeStyle = AnyShapeStyle(.terminalSurfaceBackground)
  ) {
    self.contentInsets = contentInsets
    self.backgroundStyle = backgroundStyle
  }
}

extension PromptSurfaceStylePresentation {
  package var validationProblems: [String] {
    portalSurfaceValidationProblems(
      backdropOpacity: backdropOpacity, minimumWidth: minimumWidth, maximumWidth: maximumWidth,
      scrollMinimumHeight: scrollMinimumHeight, scrollIdealHeight: scrollIdealHeight,
      scrollMaximumHeight: scrollMaximumHeight, contentInsets: contentInsets)
  }
}

extension SheetSurfaceStylePresentation {
  package var validationProblems: [String] {
    portalSurfaceValidationProblems(
      backdropOpacity: backdropOpacity, minimumWidth: minimumWidth, maximumWidth: maximumWidth,
      scrollMinimumHeight: scrollMinimumHeight, scrollIdealHeight: scrollIdealHeight,
      scrollMaximumHeight: scrollMaximumHeight, contentInsets: contentInsets)
  }
}

extension FullScreenSurfaceStylePresentation {
  package var validationProblems: [String] {
    AnchoredSurfaceStylePresentation(contentInsets: contentInsets).validationProblems
  }
}

private func portalSurfaceValidationProblems(
  backdropOpacity: Double, minimumWidth: Int, maximumWidth: Int?,
  scrollMinimumHeight: Int, scrollIdealHeight: Int, scrollMaximumHeight: Int,
  contentInsets: EdgeInsets
) -> [String] {
  var problems = AnchoredSurfaceStylePresentation(
    contentInsets: contentInsets, minimumWidth: minimumWidth, maximumWidth: maximumWidth
  ).validationProblems
  if !backdropOpacity.isFinite || !(0...1).contains(backdropOpacity) {
    problems.append("backdropOpacity must be finite and between zero and one")
  }
  if scrollMinimumHeight < 0 || scrollIdealHeight < scrollMinimumHeight
    || scrollMaximumHeight < scrollIdealHeight
  {
    problems.append("scroll heights must be nonnegative and ordered minimum, ideal, maximum")
  }
  return problems
}
