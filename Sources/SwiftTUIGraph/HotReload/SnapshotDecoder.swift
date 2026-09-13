final class SnapshotDecodingBudget {
  var calls = 0
  let maximumDepth: Int
  init(maximumDepth: Int) { self.maximumDepth = maximumDepth }
}

struct SnapshotDecoder: Decoder, SingleValueDecodingContainer {
  let value: SnapshotValue
  var codingPath: [any CodingKey] = []
  var budget = SnapshotDecodingBudget(maximumDepth: 128)
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  func child(_ value: SnapshotValue, key: any CodingKey) -> SnapshotDecoder {
    SnapshotDecoder(value: value, codingPath: codingPath + [key], budget: budget)
  }
  func mismatch<T>(_ type: T.Type) -> DecodingError {
    .typeMismatch(
      type, .init(codingPath: codingPath, debugDescription: "Incompatible hot-reload value"))
  }
  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard case .object(let children) = value else { throw mismatch([String: SnapshotValue].self) }
    return KeyedDecodingContainer(SnapshotKeyedDecoder<Key>(decoder: self, children: children))
  }
  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard case .array(let children) = value else { throw mismatch([SnapshotValue].self) }
    return SnapshotUnkeyedDecoder(decoder: self, children: children)
  }
  func singleValueContainer() throws -> any SingleValueDecodingContainer { self }
  func decodeNil() -> Bool { value == .null }
  func decode(_ type: Bool.Type) throws -> Bool {
    guard case .bool(let result) = value else { throw mismatch(type) }
    return result
  }
  func decode(_ type: String.Type) throws -> String {
    guard case .string(let result) = value else { throw mismatch(type) }
    return result
  }
  func decode(_ type: Double.Type) throws -> Double {
    guard case .double(let result) = value else { throw mismatch(type) }
    return result
  }
  func decode(_ type: Float.Type) throws -> Float {
    let result = try decode(Double.self)
    // Finite Float encodings are exactly representable as Double.
    guard !result.isFinite || Float(exactly: result) != nil else { throw mismatch(type) }
    return Float(result)
  }
  func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    let result: T?
    switch value {
    case .signed(let integer): result = T(exactly: integer)
    case .unsigned(let integer): result = T(exactly: integer)
    default: result = nil
    }
    guard let result else { throw mismatch(type) }
    return result
  }
  func decode(_ type: Int128.Type) throws -> Int128 {
    guard case .wideInteger(let text) = value, let result = Int128(text) else {
      throw mismatch(type)
    }
    return result
  }
  func decode(_ type: UInt128.Type) throws -> UInt128 {
    guard case .wideInteger(let text) = value, let result = UInt128(text) else {
      throw mismatch(type)
    }
    return result
  }
  func decode(_ type: Int.Type) throws -> Int { try integer(type) }
  func decode(_ type: Int8.Type) throws -> Int8 { try integer(type) }
  func decode(_ type: Int16.Type) throws -> Int16 { try integer(type) }
  func decode(_ type: Int32.Type) throws -> Int32 { try integer(type) }
  func decode(_ type: Int64.Type) throws -> Int64 { try integer(type) }
  func decode(_ type: UInt.Type) throws -> UInt { try integer(type) }
  func decode(_ type: UInt8.Type) throws -> UInt8 { try integer(type) }
  func decode(_ type: UInt16.Type) throws -> UInt16 { try integer(type) }
  func decode(_ type: UInt32.Type) throws -> UInt32 { try integer(type) }
  func decode(_ type: UInt64.Type) throws -> UInt64 { try integer(type) }
  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    guard budget.calls <= budget.maximumDepth else { throw SnapshotCodingError.limitExceeded }
    budget.calls += 1
    defer { budget.calls -= 1 }
    return try T(from: self)
  }
}

private struct SnapshotKeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let decoder: SnapshotDecoder
  let children: [String: SnapshotValue]
  var codingPath: [any CodingKey] { decoder.codingPath }
  var allKeys: [Key] { children.keys.sorted().compactMap(Key.init(stringValue:)) }
  func contains(_ key: Key) -> Bool { children[key.stringValue] != nil }
  func child(_ key: any CodingKey) throws -> SnapshotDecoder {
    guard let value = children[key.stringValue] else {
      throw DecodingError.keyNotFound(
        key, .init(codingPath: codingPath, debugDescription: "Missing hot-reload key")
      )
    }
    return decoder.child(value, key: key)
  }
  func decodeNil(forKey key: Key) throws -> Bool { try child(key).decodeNil() }
  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    try child(key).decode(type)
  }
  func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type, forKey key: Key
  ) throws -> KeyedDecodingContainer<NestedKey> { try child(key).container(keyedBy: type) }
  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    try child(key).unkeyedContainer()
  }
  func superDecoder() throws -> any Decoder { try child(SnapshotCodingKey("super")) }
  func superDecoder(forKey key: Key) throws -> any Decoder { try child(key) }
}

private struct SnapshotUnkeyedDecoder: UnkeyedDecodingContainer {
  let decoder: SnapshotDecoder
  let children: [SnapshotValue]
  var codingPath: [any CodingKey] { decoder.codingPath }
  var count: Int? { children.count }
  var currentIndex = 0
  var isAtEnd: Bool { currentIndex == children.count }
  func next() throws -> SnapshotDecoder {
    guard !isAtEnd else {
      throw DecodingError.valueNotFound(
        SnapshotValue.self,
        .init(codingPath: codingPath, debugDescription: "End of hot-reload array")
      )
    }
    return decoder.child(children[currentIndex], key: SnapshotCodingKey(index: currentIndex))
  }
  mutating func decodeNil() throws -> Bool {
    if try next().decodeNil() {
      currentIndex += 1
      return true
    }
    return false
  }
  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let result = try next().decode(type)
    currentIndex += 1
    return result
  }
  mutating func nestedContainer<NestedKey: CodingKey>(
    keyedBy type: NestedKey.Type
  ) throws -> KeyedDecodingContainer<NestedKey> {
    let result = try next().container(keyedBy: type)
    currentIndex += 1
    return result
  }
  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    let result = try next().unkeyedContainer()
    currentIndex += 1
    return result
  }
  mutating func superDecoder() throws -> any Decoder {
    let result = try next()
    currentIndex += 1
    return result
  }
}
