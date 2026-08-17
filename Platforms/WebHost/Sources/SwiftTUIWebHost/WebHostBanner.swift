// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
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
#endif
