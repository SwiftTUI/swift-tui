import Testing

@testable import SwiftTUICore

@Suite
struct ActionScopeTests {
  @Test("AnyID wraps Hashable & Sendable values and round-trips equality")
  func anyIDRoundTrip() {
    let a = AnyID(42)
    let b = AnyID(42)
    let c = AnyID("forty-two")
    #expect(a == b)
    #expect(a != c)
    #expect(a.hashValue == b.hashValue)
  }

  @Test("AnyID distinguishes values of different types with equal raw representations")
  func anyIDTypeSensitivity() {
    let intID = AnyID(1)
    let stringID = AnyID("1")
    #expect(intID != stringID)
  }
}
