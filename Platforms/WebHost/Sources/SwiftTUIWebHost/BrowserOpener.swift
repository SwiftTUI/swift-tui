package import Foundation

#if os(Windows)
  import WinSDK
#endif

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
    #elseif os(Windows)
      let address = Array(url.absoluteString.utf16) + [0]
      let result = address.withUnsafeBufferPointer { buffer in
        unsafe ShellExecuteW(nil, nil, buffer.baseAddress, nil, nil, SW_SHOWNORMAL)
      }
      let code = Int(bitPattern: result)
      guard code > 32 else { throw BrowserOpenerError.launchFailed(code) }
    #else
      throw BrowserOpenerError.unsupportedPlatform
    #endif
  }
}

package enum BrowserOpenerError: Error, Equatable, Sendable, CustomStringConvertible {
  case unsupportedPlatform
  case launchFailed(Int)

  package var description: String {
    switch self {
    case .unsupportedPlatform:
      return "Opening a browser is not supported on this platform."
    case .launchFailed(let code):
      return
        "The default browser could not be opened (Windows error \(code)). Open the printed URL manually."
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
