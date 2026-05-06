package import Foundation

package protocol BrowserOpening: Sendable {
  func open(_ url: URL) throws
}

package struct SystemBrowserOpener: BrowserOpening {
  package init() {}

  package func open(
    _ url: URL
  ) throws {
    #if canImport(Darwin)
      try launchBrowserCommand("/usr/bin/open", arguments: [url.absoluteString])
    #elseif os(Linux)
      try launchBrowserCommand("/usr/bin/xdg-open", arguments: [url.absoluteString])
    #else
      throw BrowserOpenerError.unsupportedPlatform
    #endif
  }
}

package enum BrowserOpenerError: Error, Equatable, Sendable, CustomStringConvertible {
  case unsupportedPlatform

  package var description: String {
    switch self {
    case .unsupportedPlatform:
      return "Opening a browser is not supported on this platform."
    }
  }
}

private func launchBrowserCommand(
  _ executablePath: String,
  arguments: [String]
) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executablePath)
  process.arguments = arguments
  try process.run()
}
