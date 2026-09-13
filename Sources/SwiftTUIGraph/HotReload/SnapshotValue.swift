/// Detached, Foundation-free Codable currency. No application objects or type metadata.
package indirect enum SnapshotValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case signed(Int64)
  case unsigned(UInt64)
  case wideInteger(String)
  case double(Double)
  case string(String)
  case array([SnapshotValue])
  case object([String: SnapshotValue])

  package static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null): return true
    case (.bool(let a), .bool(let b)): return a == b
    case (.signed(let a), .signed(let b)): return a == b
    case (.unsigned(let a), .unsigned(let b)): return a == b
    case (.wideInteger(let a), .wideInteger(let b)): return a == b
    case (.double(let a), .double(let b)): return a.bitPattern == b.bitPattern
    case (.string(let a), .string(let b)): return a == b
    case (.array(let a), .array(let b)): return a == b
    case (.object(let a), .object(let b)): return a == b
    default: return false
    }
  }
}

package struct SnapshotCodingLimits: Sendable {
  package var maximumDepth: Int = 128
  package var maximumValues: Int = 65_536
  package var maximumUTF8Bytes: Int = 4_194_304
  package init(
    maximumDepth: Int = 128, maximumValues: Int = 65_536, maximumUTF8Bytes: Int = 4_194_304
  ) {
    self.maximumDepth = maximumDepth
    self.maximumValues = maximumValues
    self.maximumUTF8Bytes = maximumUTF8Bytes
  }
}

package enum SnapshotCodingError: Error, Equatable {
  case limitExceeded
  case incompatibleContainer
  case missingValue
}

package enum SnapshotCoding {
  package static func encode<T: Encodable>(
    _ value: T, limits: SnapshotCodingLimits = .init()
  ) throws -> SnapshotValue {
    let budget = SnapshotEncodingBudget(limits: limits)
    let encoder = SnapshotEncoder(budget: budget)
    try encoder.encode(value)
    if let error = budget.error { throw error }
    return try encoder.node.freeze()
  }

  package static func decode<T: Decodable>(
    _ type: T.Type, from value: SnapshotValue, limits: SnapshotCodingLimits = .init()
  ) throws -> T {
    var remaining = limits.maximumValues
    var bytes = limits.maximumUTF8Bytes
    try validate(value, depth: 0, remaining: &remaining, bytes: &bytes, limits: limits)
    return try SnapshotDecoder(
      value: value, budget: SnapshotDecodingBudget(maximumDepth: limits.maximumDepth)
    ).decode(type)
  }

  private static func validate(
    _ value: SnapshotValue, depth: Int, remaining: inout Int, bytes: inout Int,
    limits: SnapshotCodingLimits
  ) throws {
    guard depth <= limits.maximumDepth, remaining > 0, bytes >= 0 else {
      throw SnapshotCodingError.limitExceeded
    }
    remaining -= 1
    switch value {
    case .array(let children):
      for child in children {
        try validate(child, depth: depth + 1, remaining: &remaining, bytes: &bytes, limits: limits)
      }
    case .object(let children):
      for (key, child) in children {
        guard key.utf8.count <= bytes else { throw SnapshotCodingError.limitExceeded }
        bytes -= key.utf8.count
        try validate(child, depth: depth + 1, remaining: &remaining, bytes: &bytes, limits: limits)
      }
    case .string(let text), .wideInteger(let text):
      guard text.utf8.count <= bytes else { throw SnapshotCodingError.limitExceeded }
      bytes -= text.utf8.count
    default: break
    }
  }
}

struct SnapshotCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?
  init(_ string: String) {
    stringValue = string
    intValue = nil
  }
  init(index: Int) {
    stringValue = "Index \(index)"
    intValue = index
  }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) { self.init(index: intValue) }
}
