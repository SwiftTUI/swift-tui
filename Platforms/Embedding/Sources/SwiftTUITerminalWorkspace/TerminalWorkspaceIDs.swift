/// A stable identifier for one terminal pane in a workspace.
public struct TerminalPaneID: Hashable, Codable, Sendable, ExpressibleByStringLiteral,
  CustomStringConvertible
{
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  public var description: String {
    rawValue
  }
}

/// A stable identifier for one tab in a terminal workspace.
public struct TerminalWorkspaceTabID: Hashable, Codable, Sendable, ExpressibleByStringLiteral,
  CustomStringConvertible
{
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  public var description: String {
    rawValue
  }
}

/// A directional focus request inside a terminal workspace pane tree.
public enum TerminalWorkspaceDirection: Hashable, Codable, Sendable {
  case left
  case right
  case up
  case down
}

/// The axis of a workspace split.
public enum TerminalSplitAxis: Hashable, Codable, Sendable {
  /// Places child panes side by side.
  case horizontal
  /// Places child panes above and below one another.
  case vertical
}
