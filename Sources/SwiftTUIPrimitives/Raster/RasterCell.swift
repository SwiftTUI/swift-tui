/// A single terminal cell in a rasterized surface.
public struct RasterCell: Equatable, Sendable {
  public var character: Character
  public var spanWidth: Int
  public var continuationLeadX: Int?
  public var style: ResolvedTextStyle?
  public var hyperlink: String?

  public init(
    character: Character = " ",
    spanWidth: Int = 1,
    continuationLeadX: Int? = nil,
    style: ResolvedTextStyle? = nil,
    hyperlink: String? = nil
  ) {
    self.character = character
    self.spanWidth = spanWidth
    self.continuationLeadX = continuationLeadX
    self.style = style
    self.hyperlink = hyperlink
  }

  public static let empty = Self()

  public var isContinuation: Bool {
    continuationLeadX != nil
  }
}
