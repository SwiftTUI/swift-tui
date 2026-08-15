import CoreFoundation
import Foundation

enum HostWireConformanceError: Error, CustomStringConvertible {
  case invalid(String)

  var description: String {
    switch self {
    case .invalid(let message):
      return message
    }
  }
}

indirect enum HostWireConformanceJSON: Equatable {
  case object([String: HostWireConformanceJSON])
  case array([HostWireConformanceJSON])
  case string(String)
  case integer(Int)
  case number(Double)
  case bool(Bool)
  case null

  /// Keys whose wire values are genuinely fractional. Every other number on the
  /// host wire must stay host-`Int`-representable so Kotlin and TypeScript hosts
  /// can decode it without widening. `opacity` is a `Double` on both hosts.
  static let fractionalKeys: Set<String> = ["opacity"]

  static func parse(
    _ data: Data,
    context: String
  ) throws -> Self {
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw HostWireConformanceError.invalid("\(context): invalid JSON: \(error)")
    }
    return try convert(object, context: context)
  }

  private static func convert(
    _ value: Any,
    context: String,
    key: String? = nil
  ) throws -> Self {
    if value is NSNull {
      return .null
    }
    if let string = value as? String {
      return .string(string)
    }
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return .bool(number.boolValue)
      }
      return try convertNumber(number, context: context, key: key)
    }
    if let array = value as? [Any] {
      return .array(
        try array.enumerated().map { index, element in
          try convert(element, context: "\(context)[\(index)]", key: key)
        })
    }
    if let object = value as? [String: Any] {
      var converted: [String: Self] = [:]
      converted.reserveCapacity(object.count)
      for (key, element) in object {
        converted[key] = try convert(element, context: "\(context).\(key)", key: key)
      }
      return .object(converted)
    }
    throw HostWireConformanceError.invalid("\(context): unsupported JSON value")
  }

  /// Classifies a wire number by its *value*, never by `NSNumber.stringValue`.
  /// Darwin renders an integral `Double` as `1` while swift-corelibs-foundation
  /// renders `1.0`, so a string-based test accepts `"opacity":1.0` on macOS and
  /// rejects the identical bytes on Linux.
  private static func convertNumber(
    _ number: NSNumber,
    context: String,
    key: String?
  ) throws -> Self {
    // Exact integers first, so values beyond `Double`'s 2^53 precision survive.
    if let integer = Int(number.stringValue) {
      return .integer(integer)
    }
    let double = number.doubleValue
    if let integer = Int(exactly: double) {
      return .integer(integer)
    }
    guard let key, fractionalKeys.contains(key), double.isFinite else {
      throw HostWireConformanceError.invalid(
        "\(context): every number must be a host-Int-representable integer")
    }
    return .number(double)
  }

  func object(
    keys expectedKeys: Set<String>,
    context: String
  ) throws -> [String: Self] {
    guard case .object(let object) = self else {
      throw HostWireConformanceError.invalid("\(context): expected object")
    }
    let actualKeys = Set(object.keys)
    guard actualKeys == expectedKeys else {
      throw HostWireConformanceError.invalid(
        "\(context): expected keys \(expectedKeys.sorted()), got \(actualKeys.sorted())")
    }
    return object
  }

  func array(
    context: String
  ) throws -> [Self] {
    guard case .array(let array) = self else {
      throw HostWireConformanceError.invalid("\(context): expected array")
    }
    return array
  }

  func string(
    context: String
  ) throws -> String {
    guard case .string(let string) = self else {
      throw HostWireConformanceError.invalid("\(context): expected string")
    }
    return string
  }

  func integer(
    context: String
  ) throws -> Int {
    guard case .integer(let integer) = self else {
      throw HostWireConformanceError.invalid("\(context): expected integer")
    }
    return integer
  }

  /// Accepts either wire spelling of a fractional field: an integral value
  /// arrives as `.integer` so integer-only consumers keep matching.
  func number(
    context: String
  ) throws -> Double {
    switch self {
    case .number(let double):
      return double
    case .integer(let integer):
      return Double(integer)
    default:
      throw HostWireConformanceError.invalid("\(context): expected number")
    }
  }

  func bool(
    context: String
  ) throws -> Bool {
    guard case .bool(let bool) = self else {
      throw HostWireConformanceError.invalid("\(context): expected Boolean")
    }
    return bool
  }
}

enum HostWireConformanceSHA256 {
  static func hexDigest(
    _ data: Data
  ) -> String {
    let digits = Array("0123456789abcdef".utf8)
    let bytes = digest(Array(data))
    var result = [UInt8]()
    result.reserveCapacity(bytes.count * 2)
    for byte in bytes {
      result.append(digits[Int(byte >> 4)])
      result.append(digits[Int(byte & 0x0F)])
    }
    return String(decoding: result, as: UTF8.self)
  }

  private static func digest(
    _ bytes: [UInt8]
  ) -> [UInt8] {
    var message = bytes
    let bitCount = UInt64(message.count) &* 8
    message.append(0x80)
    while message.count % 64 != 56 {
      message.append(0)
    }
    for shift in stride(from: 56, through: 0, by: -8) {
      message.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
    }

    var hash: [UInt32] = [
      0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
      0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]
    let constants: [UInt32] = [
      0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5,
      0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
      0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
      0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
      0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc,
      0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
      0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
      0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
      0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
      0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
      0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3,
      0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
      0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5,
      0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
      0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
      0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    for offset in stride(from: 0, to: message.count, by: 64) {
      var words = [UInt32](repeating: 0, count: 64)
      for index in 0..<16 {
        let start = offset + index * 4
        words[index] =
          UInt32(message[start]) << 24
          | UInt32(message[start + 1]) << 16
          | UInt32(message[start + 2]) << 8
          | UInt32(message[start + 3])
      }
      for index in 16..<64 {
        let a = words[index - 15]
        let b = words[index - 2]
        let s0 = rotateRight(a, by: 7) ^ rotateRight(a, by: 18) ^ (a >> 3)
        let s1 = rotateRight(b, by: 17) ^ rotateRight(b, by: 19) ^ (b >> 10)
        words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
      }

      var a = hash[0]
      var b = hash[1]
      var c = hash[2]
      var d = hash[3]
      var e = hash[4]
      var f = hash[5]
      var g = hash[6]
      var h = hash[7]
      for index in 0..<64 {
        let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
        let choice = (e & f) ^ ((~e) & g)
        let temporary1 = h &+ sum1 &+ choice &+ constants[index] &+ words[index]
        let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
        let majority = (a & b) ^ (a & c) ^ (b & c)
        let temporary2 = sum0 &+ majority
        h = g
        g = f
        f = e
        e = d &+ temporary1
        d = c
        c = b
        b = a
        a = temporary1 &+ temporary2
      }
      hash[0] &+= a
      hash[1] &+= b
      hash[2] &+= c
      hash[3] &+= d
      hash[4] &+= e
      hash[5] &+= f
      hash[6] &+= g
      hash[7] &+= h
    }

    return hash.flatMap { word in
      [
        UInt8(truncatingIfNeeded: word >> 24),
        UInt8(truncatingIfNeeded: word >> 16),
        UInt8(truncatingIfNeeded: word >> 8),
        UInt8(truncatingIfNeeded: word),
      ]
    }
  }

  private static func rotateRight(
    _ value: UInt32,
    by count: UInt32
  ) -> UInt32 {
    (value >> count) | (value << (32 - count))
  }
}
