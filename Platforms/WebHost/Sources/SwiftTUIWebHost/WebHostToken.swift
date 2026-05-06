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
