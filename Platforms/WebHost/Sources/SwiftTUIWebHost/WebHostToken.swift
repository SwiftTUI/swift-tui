// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
  import Foundation

  package struct WebHostToken: RawRepresentable, Equatable, Sendable, CustomStringConvertible {
    package var rawValue: String

    package init(rawValue: String) {
      self.rawValue = rawValue
    }

    package init() {
      rawValue = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    package var description: String {
      rawValue
    }
  }
#endif
