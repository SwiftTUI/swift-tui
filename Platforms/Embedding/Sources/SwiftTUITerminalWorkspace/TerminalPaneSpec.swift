import Foundation
public import SwiftTUICore

/// The serializable process metadata for a terminal pane.
public struct TerminalPaneSpec: Identifiable, Hashable, Codable, Sendable {
  public var id: TerminalPaneID
  public var title: String
  public var command: String
  public var arguments: [String]
  public var environment: [String: String]?
  public var workingDirectory: String?
  public var initialSize: CellSize

  public init(
    id: TerminalPaneID,
    title: String,
    command: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: String? = nil,
    initialSize: CellSize = CellSize(width: 80, height: 24)
  ) {
    self.id = id
    self.title = title
    self.command = command
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
    self.initialSize = initialSize
  }

  /// Creates a pane that starts the user's default shell.
  public static func shell(
    id: TerminalPaneID,
    title: String = "shell",
    workingDirectory: String? = nil,
    command: String = Self.defaultShellCommand(),
    initialSize: CellSize = CellSize(width: 80, height: 24)
  ) -> Self {
    Self(
      id: id,
      title: title,
      command: command,
      workingDirectory: workingDirectory,
      initialSize: initialSize
    )
  }

  /// Returns the host shell used by default shell panes.
  public static func defaultShellCommand() -> String {
    ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case command
    case arguments
    case environment
    case workingDirectory
    case initialWidth
    case initialHeight
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(TerminalPaneID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    command = try container.decode(String.self, forKey: .command)
    arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
    environment = try container.decodeIfPresent([String: String].self, forKey: .environment)
    workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
    initialSize = CellSize(
      width: try container.decode(Int.self, forKey: .initialWidth),
      height: try container.decode(Int.self, forKey: .initialHeight)
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(command, forKey: .command)
    try container.encode(arguments, forKey: .arguments)
    try container.encodeIfPresent(environment, forKey: .environment)
    try container.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
    try container.encode(initialSize.width, forKey: .initialWidth)
    try container.encode(initialSize.height, forKey: .initialHeight)
  }
}
