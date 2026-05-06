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
    for session: WebHostServerSession
  ) -> String {
    "SwiftTUI WebHost listening at \(session.url(path: "/").absoluteString)"
  }
}
