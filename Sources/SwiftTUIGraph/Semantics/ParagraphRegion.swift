/// The visible layout bounds of one explicitly authored text paragraph.
///
/// This is presentation metadata, independent of accessibility visibility and
/// control roles. It carries no copy of the source text or editable values.
package struct ParagraphRegion: Equatable, Sendable {
  /// Stable identity of the authored Text.
  package var identity: Identity
  /// Placed cell bounds, clipped by containing scroll viewports.
  package var rect: CellRect

  /// Creates presentation metadata for one authored paragraph.
  package init(identity: Identity, rect: CellRect) {
    self.identity = identity
    self.rect = rect
  }
}
