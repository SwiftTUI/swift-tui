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

extension BorderSet {
  public func topGlyph(at index: Int) -> Character? { Self.cycle(top, at: index) }
  public func bottomGlyph(at index: Int) -> Character? { Self.cycle(bottom, at: index) }
  public func leftGlyph(at index: Int) -> Character? { Self.cycle(left, at: index) }
  public func rightGlyph(at index: Int) -> Character? { Self.cycle(right, at: index) }

  private static func cycle(_ edge: String, at index: Int) -> Character? {
    guard index >= 0, !edge.isEmpty else { return nil }
    let chars = Array(edge)
    return chars[index % chars.count]
  }
}

extension BorderSet {
  public static let single = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘",
    middleLeading: "├", middleTrailing: "┤",
    middle: "┼", middleTop: "┬", middleBottom: "┴")

  public static let rounded = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "╭", topTrailing: "╮",
    bottomLeading: "╰", bottomTrailing: "╯",
    middleLeading: "├", middleTrailing: "┤",
    middle: "┼", middleTop: "┬", middleBottom: "┴")

  public static let double = BorderSet(
    top: "═", bottom: "═", left: "║", right: "║",
    topLeading: "╔", topTrailing: "╗",
    bottomLeading: "╚", bottomTrailing: "╝",
    middleLeading: "╠", middleTrailing: "╣",
    middle: "╬", middleTop: "╦", middleBottom: "╩")

  public static let heavy = BorderSet(
    top: "━", bottom: "━", left: "┃", right: "┃",
    topLeading: "┏", topTrailing: "┓",
    bottomLeading: "┗", bottomTrailing: "┛",
    middleLeading: "┣", middleTrailing: "┫",
    middle: "╋", middleTop: "┳", middleBottom: "┻")

  public static let block = BorderSet(
    top: "█", bottom: "█", left: "█", right: "█",
    topLeading: "█", topTrailing: "█",
    bottomLeading: "█", bottomTrailing: "█")

  /// A decorative half-block border drawn on the view's own frame edges,
  /// overlaying content rather than reserving extra layout space.
  public static let outerHalfBlock = BorderSet(
    top: "▀", bottom: "▄", left: "▌", right: "▐",
    topLeading: "▛", topTrailing: "▜",
    bottomLeading: "▙", bottomTrailing: "▟",
    placement: .decorative)

  /// An inset half-block border that draws into the view's outermost rows and
  /// columns, trimming a cell off content on every side rather than expanding.
  public static let innerHalfBlock = BorderSet(
    top: "▄", bottom: "▀", left: "▐", right: "▌",
    topLeading: "▗", topTrailing: "▖",
    bottomLeading: "▝", bottomTrailing: "▘",
    placement: .inset)

  public static let singleDouble = BorderSet(
    top: "─", bottom: "─", left: "║", right: "║",
    topLeading: "╓", topTrailing: "╖",
    bottomLeading: "╙", bottomTrailing: "╜")

  public static let doubleSingle = BorderSet(
    top: "═", bottom: "═", left: "│", right: "│",
    topLeading: "╒", topTrailing: "╕",
    bottomLeading: "╘", bottomTrailing: "╛")

  public static let ascii = BorderSet(
    top: "-", bottom: "-", left: "|", right: "|",
    topLeading: "+", topTrailing: "+",
    bottomLeading: "+", bottomTrailing: "+",
    middleLeading: "+", middleTrailing: "+",
    middle: "+", middleTop: "+", middleBottom: "+")

  /// A border that contributes layout space (one cell per side) but draws
  /// invisible space glyphs. Use when you want consistent sizing while
  /// toggling border visibility.
  public static let hidden = BorderSet(
    top: " ", bottom: " ", left: " ", right: " ",
    topLeading: " ", topTrailing: " ",
    bottomLeading: " ", bottomTrailing: " ")

  /// A border with zero frame contribution and no glyphs. The "no border"
  /// value — **not** to be confused with `Optional<BorderSet>.none`.
  public static let none = BorderSet(
    top: "", bottom: "", left: "", right: "",
    topLeading: "", topTrailing: "",
    bottomLeading: "", bottomTrailing: "")

  public static let dashed = BorderSet(
    top: "─·", bottom: "─·", left: "│·", right: "│·",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘")

  public static let dashedHeavy = BorderSet(
    top: "━┅", bottom: "━┅", left: "┃┇", right: "┃┇",
    topLeading: "┏", topTrailing: "┓",
    bottomLeading: "┗", bottomTrailing: "┛")

  public static let markdown = BorderSet(
    top: "-", bottom: "-", left: "|", right: "|",
    topLeading: "|", topTrailing: "|",
    bottomLeading: "|", bottomTrailing: "|")
}
