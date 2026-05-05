public import Foundation

public struct PreviewCommand: Sendable {
  public var executable: String
  public var arguments: @Sendable (URL) -> [String]

  public init(
    executable: String,
    arguments: @escaping @Sendable (URL) -> [String]
  ) {
    self.executable = executable
    self.arguments = arguments
  }
}

public struct PreviewerRegistry: Sendable {
  public var byExtension: [String: PreviewCommand]
  public var fallback: PreviewCommand

  public init(
    byExtension: [String: PreviewCommand],
    fallback: PreviewCommand
  ) {
    self.byExtension = Dictionary(
      uniqueKeysWithValues: byExtension.map { key, value in
        (key.lowercased(), value)
      }
    )
    self.fallback = fallback
  }

  public func command(for url: URL) -> PreviewCommand {
    let ext = url.pathExtension.lowercased()
    return byExtension[ext] ?? fallback
  }
}

extension PreviewerRegistry {
  public static let defaults = PreviewerRegistry(
    byExtension: [
      "md": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["glow", "-s", "dark", $0.path] }
      ),
      "json": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["jq", "-C", ".", $0.path] }
      ),
      "yaml": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["bat", "--color=always", $0.path] }
      ),
      "yml": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["bat", "--color=always", $0.path] }
      ),
      "toml": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["bat", "--color=always", $0.path] }
      ),
      "swift": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["bat", "--color=always", $0.path] }
      ),
      "png": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["chafa", "--symbols=block", $0.path] }
      ),
      "jpg": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["chafa", "--symbols=block", $0.path] }
      ),
      "jpeg": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["chafa", "--symbols=block", $0.path] }
      ),
      "gif": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["chafa", "--symbols=block", $0.path] }
      ),
      "zip": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["unzip", "-l", $0.path] }
      ),
      "tar": PreviewCommand(
        executable: "/usr/bin/env",
        arguments: { ["tar", "-tvf", $0.path] }
      ),
    ],
    fallback: PreviewCommand(
      executable: "/usr/bin/env",
      arguments: { ["bat", "--color=always", $0.path] }
    )
  )
}
