public struct BorderSet: Equatable, Sendable {
  public var top: String
  public var bottom: String
  public var left: String
  public var right: String

  public var topLeading: String
  public var topTrailing: String
  public var bottomLeading: String
  public var bottomTrailing: String

  public var middleLeading: String
  public var middleTrailing: String
  public var middle: String
  public var middleTop: String
  public var middleBottom: String

  public var placement: Placement

  public enum Placement: Equatable, Sendable {
    case outset
    case inset
    case decorative
  }

  public init(
    top: String, bottom: String, left: String, right: String,
    topLeading: String, topTrailing: String,
    bottomLeading: String, bottomTrailing: String,
    middleLeading: String = "",
    middleTrailing: String = "",
    middle: String = "",
    middleTop: String = "",
    middleBottom: String = "",
    placement: Placement = .outset
  ) {
    self.top = top
    self.bottom = bottom
    self.left = left
    self.right = right
    self.topLeading = topLeading
    self.topTrailing = topTrailing
    self.bottomLeading = bottomLeading
    self.bottomTrailing = bottomTrailing
    self.middleLeading = middleLeading
    self.middleTrailing = middleTrailing
    self.middle = middle
    self.middleTop = middleTop
    self.middleBottom = middleBottom
    self.placement = placement
  }
}

extension BorderSet {
  public var topDisplayWidth: Int { Self.maxCellWidth(of: top) }
  public var bottomDisplayWidth: Int { Self.maxCellWidth(of: bottom) }
  public var leftDisplayWidth: Int { Self.maxCellWidth(of: left) }
  public var rightDisplayWidth: Int { Self.maxCellWidth(of: right) }

  private static func maxCellWidth(of edge: String) -> Int {
    guard !edge.isEmpty else { return 0 }
    return edge.reduce(0) { max($0, cellWidth(of: $1)) }
  }
}
