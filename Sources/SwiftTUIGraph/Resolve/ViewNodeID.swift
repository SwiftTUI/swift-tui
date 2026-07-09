package struct ViewNodeID: Hashable, Comparable, Sendable, Codable,
  CustomStringConvertible
{
  package let rawValue: UInt64

  package init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  package var description: String {
    "ViewNodeID(\(rawValue))"
  }

  package static func < (lhs: ViewNodeID, rhs: ViewNodeID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
