public import SwiftTUIRuntime

public struct WebHostConfig: Equatable, Sendable {
  package static let defaultPortRange = 9123...9132

  public var bind: String
  public var port: Int
  public var openBrowser: Bool
  public var sceneID: WindowIdentifier?
  /// App-owned browser assets; `nil` uses the bundled Canvas-only page.
  public var browserAssetsPath: String?

  public init(
    bind: String = "127.0.0.1",
    port: Int = 9123,
    openBrowser: Bool = false,
    sceneID: WindowIdentifier? = nil,
    browserAssetsPath: String? = nil
  ) {
    self.bind = bind
    self.port = port
    self.openBrowser = openBrowser
    self.sceneID = sceneID
    self.browserAssetsPath = browserAssetsPath
  }

  public init(_ webConfig: RuntimeConfiguration.WebConfig) {
    self.init(
      bind: webConfig.bind,
      port: webConfig.port,
      openBrowser: webConfig.openBrowser,
      sceneID: webConfig.sceneID
    )
  }

  package var candidatePorts: [Int] {
    if port == Self.defaultPortRange.lowerBound {
      return Array(Self.defaultPortRange)
    }
    return [port]
  }
}
