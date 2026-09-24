/// Native text-query metadata derived from the placed text input content.
/// Offsets use UTF-16 code units, as required by native accessibility APIs.
/// Secure inputs never publish this payload. The host wire continues to carry
/// its existing value and cursor anchor; this layout is for native snapshots.
public final class AccessibilityTextInput: Equatable, Sendable {
  /// A source grapheme and its bounds in the host's cell coordinate space.
  public struct Cluster: Equatable, Sendable {
    /// The grapheme's half-open UTF-16 range in the control's text value.
    public let range: Range<Int>
    /// Bounds after text wrapping, styling and scrolling have been placed.
    public let rect: CellRect

    /// Creates a placed source grapheme.
    public init(range: Range<Int>, rect: CellRect) {
      self.range = range
      self.rect = rect
    }
  }

  /// The selected UTF-16 range; an empty range represents a caret.
  public let selection: Range<Int>
  /// The UTF-16 offset of the selection's moving end, preserving direction.
  public let insertionOffset: Int
  /// Placed graphemes in source order, without synthetic caret/wrap markers.
  public let clusters: [Cluster]
  /// The cell position immediately after the text's final grapheme.
  public let endAnchor: CellPoint

  /// Creates native text-query metadata for a committed layout.
  public init(
    selection: Range<Int>, insertionOffset: Int, clusters: [Cluster], endAnchor: CellPoint
  ) {
    self.selection = selection
    self.insertionOffset = insertionOffset
    self.clusters = clusters
    self.endAnchor = endAnchor
  }

  /// Compares selection and placed text geometry.
  public static func == (lhs: AccessibilityTextInput, rhs: AccessibilityTextInput) -> Bool {
    lhs === rhs
      || (lhs.selection == rhs.selection && lhs.insertionOffset == rhs.insertionOffset
        && lhs.clusters == rhs.clusters && lhs.endAnchor == rhs.endAnchor)
  }
}

/// Primitive-owned source state. Selection offsets count grapheme clusters.
package struct TextInputAccessibilityText: Equatable, Sendable {
  package let text: String
  package let anchor: Int
  package let head: Int
  package let displayText: String?

  package init(text: String, anchor: Int, head: Int, displayText: String? = nil) {
    self.text = text
    self.anchor = anchor
    self.head = head
    self.displayText = displayText
  }
}
