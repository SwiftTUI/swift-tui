import Testing

@testable import SwiftTUIRuntime

@_spi(Testing) @testable import SwiftTUICore

/// F153 — `ImageLookupKey` hashes `.data` sources by sampling (count +
/// head/tail bytes) instead of hashing the full payload per lookup, while
/// `==` stays byte-exact. These tests pin that contract, including the
/// forced-collision case the sampling deliberately allows.
@Suite
struct ImageLookupKeySamplingTests {
  private static let cellPixelSize = PixelSize(width: 10, height: 20)

  private static func key(bytes: [UInt8]) -> ImageLookupKey {
    ImageLookupKey(
      source: .data(bytes),
      resourceRoots: [],
      cellPixelSize: cellPixelSize
    )
  }

  @Test("equal data payloads produce equal keys and equal hashes")
  func equalPayloadsHashEqually() {
    let bytes = (0..<512).map { UInt8($0 % 256) }
    let first = Self.key(bytes: bytes)
    let second = Self.key(bytes: bytes)
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
  }

  @Test("mid-payload differences collide by construction but stay unequal")
  func forcedCollisionStaysSeparable() {
    // Same count, same first/last 64 bytes, different middle: the sampled
    // hash cannot see the difference (the deliberate trade), so both keys
    // land in one bucket — `==` must keep them apart.
    var a = [UInt8](repeating: 7, count: 512)
    var b = a
    a[256] = 1
    b[256] = 2
    let keyA = Self.key(bytes: a)
    let keyB = Self.key(bytes: b)
    #expect(keyA.hashValue == keyB.hashValue)
    #expect(keyA != keyB)

    var bucket: [ImageLookupKey: Int] = [:]
    bucket[keyA] = 1
    bucket[keyB] = 2
    #expect(bucket[keyA] == 1)
    #expect(bucket[keyB] == 2)
  }

  @Test("head and tail differences change the sampled hash")
  func sampledRegionsStayDiscriminating() {
    let base = [UInt8](repeating: 7, count: 512)
    var headEdited = base
    headEdited[0] = 1
    var tailEdited = base
    tailEdited[511] = 1
    #expect(Self.key(bytes: base).hashValue != Self.key(bytes: headEdited).hashValue)
    #expect(Self.key(bytes: base).hashValue != Self.key(bytes: tailEdited).hashValue)
    #expect(Self.key(bytes: base).hashValue != Self.key(bytes: Array(base.dropLast())).hashValue)
  }

  @Test("small payloads hash in full")
  func smallPayloadsHashFully() {
    var small = [UInt8](repeating: 7, count: 96)
    var smallEdited = small
    small[48] = 1
    smallEdited[48] = 2
    // Below the sampling threshold a mid-payload difference must still
    // change the hash (the full-bytes path).
    #expect(Self.key(bytes: small).hashValue != Self.key(bytes: smallEdited).hashValue)
  }
}
