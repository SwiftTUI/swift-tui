/// Scroll-specific appearance carried from authoring into layout, semantics,
/// and draw extraction without introducing a dependency on view styles.
package struct ScrollIndicatorAppearance: Equatable, Sendable {
  package var contentInsets: EdgeInsets
  package var verticalGlyph: String
  package var horizontalGlyph: String
  package var foregroundStyle: AnyShapeStyle
  package var focusedForegroundStyle: AnyShapeStyle
  package var reservesSpace: Bool

  package init(
    contentInsets: EdgeInsets = .zero,
    verticalGlyph: String = "▐", horizontalGlyph: String = "▂",
    foregroundStyle: AnyShapeStyle = .semantic(.muted),
    focusedForegroundStyle: AnyShapeStyle = .semantic(.tint),
    reservesSpace: Bool = true
  ) {
    self.contentInsets = contentInsets
    self.verticalGlyph = verticalGlyph
    self.horizontalGlyph = horizontalGlyph
    self.foregroundStyle = foregroundStyle
    self.focusedForegroundStyle = focusedForegroundStyle
    self.reservesSpace = reservesSpace
  }

  /// Bounds shared by indicator drawing and hit regions, before track reservation.
  package func insetBounds(_ bounds: CellRect) -> CellRect {
    .init(
      origin: .init(
        x: bounds.origin.x + contentInsets.leading,
        y: bounds.origin.y + contentInsets.top),
      size: .init(
        width: max(0, bounds.size.width - contentInsets.horizontal),
        height: max(0, bounds.size.height - contentInsets.vertical)))
  }
}
