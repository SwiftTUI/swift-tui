final class SnapshotEncodingBudget {
  let limits: SnapshotCodingLimits
  var values = 1
  var calls = 0
  var bytes = 0
  var error: SnapshotCodingError?
  init(limits: SnapshotCodingLimits) {
    self.limits = limits
    if limits.maximumValues < 1 || limits.maximumDepth < 0 { error = .limitExceeded }
  }

  func reserve(_ text: String) {
    guard text.utf8.count <= limits.maximumUTF8Bytes - bytes else {
      error = .limitExceeded
      return
    }
    bytes += text.utf8.count
  }
}

final class SnapshotEncodingNode {
  enum Storage {
    case empty
    case scalar(SnapshotValue)
    case keyed
    case unkeyed
  }
  var storage: Storage = .empty
  var keyed: [String: SnapshotEncodingNode] = [:]
  var unkeyed: [SnapshotEncodingNode] = []

  func freeze() throws -> SnapshotValue {
    switch storage {
    case .empty: throw SnapshotCodingError.missingValue
    case .scalar(let value): return value
    case .keyed: return .object(try keyed.mapValues { try $0.freeze() })
    case .unkeyed: return .array(try unkeyed.map { try $0.freeze() })
    }
  }
}

final class SnapshotEncoder: Encoder, SingleValueEncodingContainer {
  let budget: SnapshotEncodingBudget
  let node: SnapshotEncodingNode
  let codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  init(
    budget: SnapshotEncodingBudget,
    node: SnapshotEncodingNode = SnapshotEncodingNode(),
    codingPath: [any CodingKey] = []
  ) {
    self.budget = budget
    self.node = node
    self.codingPath = codingPath
  }

  func child(_ key: any CodingKey, node: SnapshotEncodingNode) -> SnapshotEncoder {
    guard budget.error == nil,
      codingPath.count < budget.limits.maximumDepth,
      budget.values < budget.limits.maximumValues
    else {
      budget.error = .limitExceeded
      return self
    }
    budget.values += 1
    return SnapshotEncoder(budget: budget, node: node, codingPath: codingPath + [key])
  }

  func keyedChild(_ key: any CodingKey) -> SnapshotEncoder {
    guard budget.error == nil, case .keyed = node.storage else {
      budget.error = budget.error ?? .incompatibleContainer
      return self
    }
    let childNode = node.keyed[key.stringValue] ?? SnapshotEncodingNode()
    budget.reserve(key.stringValue)
    node.keyed[key.stringValue] = childNode
    return child(key, node: childNode)
  }

  func unkeyedChild() -> SnapshotEncoder {
    guard budget.error == nil, case .unkeyed = node.storage else {
      budget.error = budget.error ?? .incompatibleContainer
      return self
    }
    let key = SnapshotCodingKey(index: node.unkeyed.count)
    let childNode = SnapshotEncodingNode()
    node.unkeyed.append(childNode)
    return child(key, node: childNode)
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    switch node.storage {
    case .empty: node.storage = .keyed
    case .keyed: break
    default: budget.error = .incompatibleContainer
    }
    return KeyedEncodingContainer(SnapshotKeyedEncoder<Key>(encoder: self))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    switch node.storage {
    case .empty: node.storage = .unkeyed
    case .unkeyed: break
    default: budget.error = .incompatibleContainer
    }
    return SnapshotUnkeyedEncoder(encoder: self)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer { self }

  func store(_ value: SnapshotValue) throws {
    if case .string(let text) = value { budget.reserve(text) }
    if case .wideInteger(let text) = value { budget.reserve(text) }
    if let error = budget.error { throw error }
    guard case .empty = node.storage else { throw SnapshotCodingError.incompatibleContainer }
    node.storage = .scalar(value)
  }
  func encodeNil() throws { try store(.null) }
  func encode(_ value: Int128) throws { try store(.wideInteger(String(value))) }
  func encode(_ value: UInt128) throws { try store(.wideInteger(String(value))) }
  func encode(_ value: Bool) throws { try store(.bool(value)) }
  func encode(_ value: String) throws { try store(.string(value)) }
  func encode(_ value: Double) throws { try store(.double(value)) }
  func encode(_ value: Float) throws { try store(.double(Double(value))) }
  func encode(_ value: Int) throws { try store(.signed(Int64(value))) }
  func encode(_ value: Int8) throws { try store(.signed(Int64(value))) }
  func encode(_ value: Int16) throws { try store(.signed(Int64(value))) }
  func encode(_ value: Int32) throws { try store(.signed(Int64(value))) }
  func encode(_ value: Int64) throws { try store(.signed(Int64(value))) }
  func encode(_ value: UInt) throws { try store(.unsigned(UInt64(value))) }
  func encode(_ value: UInt8) throws { try store(.unsigned(UInt64(value))) }
  func encode(_ value: UInt16) throws { try store(.unsigned(UInt64(value))) }
  func encode(_ value: UInt32) throws { try store(.unsigned(UInt64(value))) }
  func encode(_ value: UInt64) throws { try store(.unsigned(UInt64(value))) }

  func encode<T: Encodable>(_ value: T) throws {
    if let error = budget.error { throw error }
    guard budget.calls <= budget.limits.maximumDepth else {
      throw SnapshotCodingError.limitExceeded
    }
    budget.calls += 1
    defer { budget.calls -= 1 }
    // Dispatch primitives here too: keyed and unkeyed generic entry points
    // must not recurse through a primitive's own single-value implementation.
    if let value = value as? Int128, T.self == Int128.self {
      try store(.wideInteger(String(value)))
      return
    }
    if let value = value as? UInt128, T.self == UInt128.self {
      try store(.wideInteger(String(value)))
      return
    }
    if let value = value as? Bool, T.self == Bool.self {
      try store(.bool(value))
      return
    }
    if let value = value as? String, T.self == String.self {
      try store(.string(value))
      return
    }
    if let value = value as? Double, T.self == Double.self {
      try store(.double(value))
      return
    }
    if let value = value as? Float, T.self == Float.self {
      try store(.double(Double(value)))
      return
    }
    if let value = value as? Int, T.self == Int.self {
      try store(.signed(Int64(value)))
      return
    }
    if let value = value as? Int8, T.self == Int8.self {
      try store(.signed(Int64(value)))
      return
    }
    if let value = value as? Int16, T.self == Int16.self {
      try store(.signed(Int64(value)))
      return
    }
    if let value = value as? Int32, T.self == Int32.self {
      try store(.signed(Int64(value)))
      return
    }
    if let value = value as? Int64, T.self == Int64.self {
      try store(.signed(Int64(value)))
      return
    }
    if let value = value as? UInt, T.self == UInt.self {
      try store(.unsigned(UInt64(value)))
      return
    }
    if let value = value as? UInt8, T.self == UInt8.self {
      try store(.unsigned(UInt64(value)))
      return
    }
    if let value = value as? UInt16, T.self == UInt16.self {
      try store(.unsigned(UInt64(value)))
      return
    }
    if let value = value as? UInt32, T.self == UInt32.self {
      try store(.unsigned(UInt64(value)))
      return
    }
    if let value = value as? UInt64, T.self == UInt64.self {
      try store(.unsigned(UInt64(value)))
      return
    }
    try value.encode(to: self)
  }
}

private struct SnapshotKeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let encoder: SnapshotEncoder
  var codingPath: [any CodingKey] { encoder.codingPath }
  mutating func encodeNil(forKey key: Key) throws { try encoder.keyedChild(key).encodeNil() }
  mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    try encoder.keyedChild(key).encode(value)
  }
  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type, forKey key: Key
  ) -> KeyedEncodingContainer<NestedKey> {
    encoder.keyedChild(key).container(keyedBy: type)
  }
  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    encoder.keyedChild(key).unkeyedContainer()
  }
  mutating func superEncoder() -> any Encoder { encoder.keyedChild(SnapshotCodingKey("super")) }
  mutating func superEncoder(forKey key: Key) -> any Encoder { encoder.keyedChild(key) }
}

private struct SnapshotUnkeyedEncoder: UnkeyedEncodingContainer {
  let encoder: SnapshotEncoder
  var codingPath: [any CodingKey] { encoder.codingPath }
  var count: Int {
    if case .unkeyed = encoder.node.storage { return encoder.node.unkeyed.count }
    return 0
  }
  mutating func encodeNil() throws { try encoder.unkeyedChild().encodeNil() }
  mutating func encode<T: Encodable>(_ value: T) throws { try encoder.unkeyedChild().encode(value) }
  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type
  ) -> KeyedEncodingContainer<NestedKey> {
    encoder.unkeyedChild().container(keyedBy: type)
  }
  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    encoder.unkeyedChild().unkeyedContainer()
  }
  mutating func superEncoder() -> any Encoder { encoder.unkeyedChild() }
}
