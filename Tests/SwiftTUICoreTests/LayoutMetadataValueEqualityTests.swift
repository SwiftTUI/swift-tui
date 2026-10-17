import Testing

@testable import SwiftTUICore

@Suite struct LayoutMetadataValueEqualityTests {
  private struct Typed: Sendable, Equatable, CustomStringConvertible {
    var offset: Int
    var description: String { "opaque" }
  }
  private struct Opaque: Sendable { var offset: Int }

  private func metadata<Value: Sendable>(_ value: Value) -> LayoutMetadata {
    LayoutMetadata().settingLayoutValue(
      value, for: ObjectIdentifier(Value.self),
      debugName: "key", debugValue: "opaque")
  }

  @Test func typedEqualityDetectsChangesHiddenByDescriptions() {
    let first = metadata(Typed(offset: 1))
    let same = metadata(Typed(offset: 1))
    let changed = metadata(Typed(offset: 2))
    #expect(first == same)
    #expect(first != changed)
    #expect(!first.isKnownToDiffer(from: same))
    #expect(first.isKnownToDiffer(from: changed))
  }

  @Test func unknownEqualityDeniesReuseWithoutInventingASoundnessFailure() {
    let first = metadata(Opaque(offset: 1))
    let reauthored = metadata(Opaque(offset: 1))
    #expect(first == first)
    #expect(first != reauthored)
    #expect(!first.isKnownToDiffer(from: reauthored))
    var changed = reauthored
    changed.minimumWidth = 9
    #expect(first.isKnownToDiffer(from: changed))
  }
}
