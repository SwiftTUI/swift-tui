import Foundation

package protocol WebHostBannerWriting: Sendable {
  func write(_ message: String)
}

package struct StandardWebHostBannerWriter: WebHostBannerWriting {
  package init() {}

  package func write(
    _ message: String
  ) {
    print(message)
  }
}

package enum WebHostBanner {
  package static func message(
    for session: WebHostServerSession,
    configuration: WebHostConfig
  ) -> String {
    var message = "SwiftTUI WebHost listening at \(session.url(path: "/").absoluteString)"
    if configuration.bind == "0.0.0.0" {
      message += "\nWarning: WebHost is reachable from the local network."
    }
    return message
  }
}
