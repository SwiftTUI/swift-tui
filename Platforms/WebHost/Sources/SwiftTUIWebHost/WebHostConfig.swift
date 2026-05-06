public import SwiftTUI

public struct WebHostConfig: Equatable, Sendable {
  public var bind: String
  public var port: Int
  public var openBrowser: Bool

  public init(
    bind: String = "127.0.0.1",
    port: Int = 0,
    openBrowser: Bool = false
  ) {
    self.bind = bind
    self.port = port
    self.openBrowser = openBrowser
  }

  public init(_ webConfig: RuntimeConfiguration.WebConfig) {
    self.init(
      bind: webConfig.bind,
      port: webConfig.port,
      openBrowser: webConfig.openBrowser
    )
  }
}
