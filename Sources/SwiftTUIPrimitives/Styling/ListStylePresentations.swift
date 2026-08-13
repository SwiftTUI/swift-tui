/// Resolved list presentation carried by list payloads.
///
/// Split from the former combined collection presentation: a list's chrome,
/// insets, and separators are list concerns only. Table treatments live in
/// ``TableStylePresentation``.
public struct ListStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var snapshotLabel: String
  public var container: CollectionContainerChromePresentation?
  public var chromeScope: ListChromeScope
  public var contentInsets: EdgeInsets
  public var showsRowSeparators: Bool
  public var showsSectionSeparators: Bool

  public init(
    snapshotLabel: String = "",
    container: CollectionContainerChromePresentation? = nil,
    chromeScope: ListChromeScope = .wholeList,
    contentInsets: EdgeInsets = .zero,
    showsRowSeparators: Bool = true,
    showsSectionSeparators: Bool = true
  ) {
    self.snapshotLabel = snapshotLabel
    self.container = container
    self.chromeScope = chromeScope
    self.contentInsets = contentInsets
    self.showsRowSeparators = showsRowSeparators
    self.showsSectionSeparators = showsSectionSeparators
  }

  public var description: String {
    snapshotLabel.isEmpty ? "ListStylePresentation" : snapshotLabel
  }

  public var debugDescription: String {
    description
  }

  public static var plain: Self {
    .init(
      snapshotLabel: "ListStylePresentation.plain",
      container: nil,
      contentInsets: .zero,
      showsRowSeparators: true,
      showsSectionSeparators: true
    )
  }

  public static var insetGrouped: Self {
    .init(
      snapshotLabel: "ListStylePresentation.insetGrouped",
      container: .insetGrouped,
      chromeScope: .eachSection,
      contentInsets: .init(top: 1, leading: 1, bottom: 1, trailing: 1),
      showsRowSeparators: false,
      showsSectionSeparators: false
    )
  }
}
