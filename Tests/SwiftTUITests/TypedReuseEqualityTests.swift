import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private struct EqualValueWithDivergentDebugText: Equatable, Sendable,
  CustomDebugStringConvertible
{
  var value: Int
  var debugToken: String

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.value == rhs.value
  }

  var debugDescription: String {
    "EqualValueWithDivergentDebugText(\(debugToken))"
  }
}

private struct OpaqueValueWithCollidingDebugText: Sendable, CustomDebugStringConvertible {
  var value: Int

  var debugDescription: String {
    "OpaqueValueWithCollidingDebugText(constant)"
  }
}

private enum EqualDebugEnvironmentKey: EnvironmentKey {
  static let defaultValue = EqualValueWithDivergentDebugText(value: 0, debugToken: "default")
}

private enum OpaqueDebugEnvironmentKey: EnvironmentKey {
  static let defaultValue = OpaqueValueWithCollidingDebugText(value: 0)
}

private enum EqualDebugPreferenceKey: PreferenceKey {
  static let defaultValue = EqualValueWithDivergentDebugText(value: 0, debugToken: "default")

  static func reduce(
    value: inout EqualValueWithDivergentDebugText,
    nextValue: () -> EqualValueWithDivergentDebugText
  ) {
    value = nextValue()
  }
}

private enum OpaqueDebugPreferenceKey: PreferenceKey {
  static let defaultValue = OpaqueValueWithCollidingDebugText(value: 0)

  static func reduce(
    value: inout OpaqueValueWithCollidingDebugText,
    nextValue: () -> OpaqueValueWithCollidingDebugText
  ) {
    value = nextValue()
  }
}

private enum DictionaryPreferenceKey: PreferenceKey {
  static let defaultValue: [String: Int] = [:]

  static func reduce(
    value: inout [String: Int],
    nextValue: () -> [String: Int]
  ) {
    value.merge(nextValue()) { _, next in next }
  }
}

private enum ClosurePreferenceKey: PreferenceKey {
  static let defaultValue: @Sendable () -> Int = { 0 }

  static func reduce(
    value: inout @Sendable () -> Int,
    nextValue: () -> @Sendable () -> Int
  ) {
    value = nextValue()
  }
}

@MainActor
@Suite
struct TypedReuseEqualityTests {
  @Test("environment snapshots compare Equatable values, not their debug text")
  func environmentSnapshotsUseTypedEquatableValues() {
    let left = environmentSnapshot(
      EqualDebugEnvironmentKey.self,
      value: .init(value: 7, debugToken: "left")
    )
    let right = environmentSnapshot(
      EqualDebugEnvironmentKey.self,
      value: .init(value: 7, debugToken: "right")
    )

    #expect(left.values != right.values)
    #expect(left == right)
  }

  @Test("environment snapshots conservatively reject opaque reflection collisions")
  func environmentSnapshotsRejectOpaqueReflectionCollisions() {
    let left = environmentSnapshot(
      OpaqueDebugEnvironmentKey.self,
      value: .init(value: 1)
    )
    let right = environmentSnapshot(
      OpaqueDebugEnvironmentKey.self,
      value: .init(value: 2)
    )

    #expect(left.values == right.values)
    #expect(left != right)
  }

  @Test("EnvironmentValues conservatively reject opaque reflection collisions")
  func environmentValuesRejectOpaqueReflectionCollisions() {
    var left = EnvironmentValues()
    left[OpaqueDebugEnvironmentKey.self] = .init(value: 1)
    let copy = left
    var right = EnvironmentValues()
    right[OpaqueDebugEnvironmentKey.self] = .init(value: 2)

    #expect(left == copy)
    #expect(left != right)
  }

  @Test("stable framework action carriers preserve reuse across rebuilt closures")
  func stableFrameworkActionsCompareEqual() {
    var left = EnvironmentValues()
    left.resetFocus = ResetFocusAction(
      snapshotLabel: "ResetFocusAction.runtime",
      isPlaceholder: false,
      handler: { _ in true }
    )
    var right = EnvironmentValues()
    right.resetFocus = ResetFocusAction(
      snapshotLabel: "ResetFocusAction.runtime",
      isPlaceholder: false,
      handler: { _ in false }
    )

    #expect(left == right)
    #expect(
      environmentSnapshot(from: left)
        == environmentSnapshot(from: right)
    )
  }

  @Test("rebuilt stateless framework style erasers preserve environment reuse")
  func rebuiltFrameworkStylesCompareEqual() {
    var left = EnvironmentValues()
    left.buttonStyle = .automatic
    left.pickerStyle = .automatic
    left.textFieldStyle = .automatic
    left.tabViewStyle = .automatic
    var right = EnvironmentValues()
    right.buttonStyle = .automatic
    right.pickerStyle = .automatic
    right.textFieldStyle = .automatic
    right.tabViewStyle = .automatic

    #expect(left == right)
    #expect(
      environmentSnapshot(from: left)
        == environmentSnapshot(from: right)
    )
  }

  @Test("public custom actions never compare equal by their shared debug label")
  func customActionsCompareUnequal() {
    var left = EnvironmentValues()
    left.openLinkAction = OpenLinkAction { _ in true }
    var right = EnvironmentValues()
    right.openLinkAction = OpenLinkAction { _ in false }

    #expect(left != right)
    #expect(
      environmentSnapshot(from: left)
        != environmentSnapshot(from: right)
    )
  }

  @Test("preference equality compares Equatable values, not their debug text")
  func preferenceValuesUseTypedEquatableValues() {
    var left = PreferenceValues()
    left[EqualDebugPreferenceKey.self] = .init(value: 7, debugToken: "left")
    var right = PreferenceValues()
    right[EqualDebugPreferenceKey.self] = .init(value: 7, debugToken: "right")

    #expect(left == right)
  }

  @Test("preference equality conservatively rejects opaque reflection collisions")
  func preferenceValuesRejectOpaqueReflectionCollisions() {
    var left = PreferenceValues()
    left[OpaqueDebugPreferenceKey.self] = .init(value: 1)
    let copy = left
    var right = PreferenceValues()
    right[OpaqueDebugPreferenceKey.self] = .init(value: 2)

    #expect(left == copy)
    #expect(left != right)
  }

  @Test("equal dictionaries do not deny preference reuse")
  func equalDictionaryPreferencesCompareEqual() {
    var left = PreferenceValues()
    left[DictionaryPreferenceKey.self] = ["one": 1, "two": 2, "three": 3]
    var right = PreferenceValues()
    right[DictionaryPreferenceKey.self] = ["three": 3, "one": 1, "two": 2]

    #expect(left == right)
  }

  @Test("changed dictionaries invalidate preference reuse")
  func changedDictionaryPreferencesCompareUnequal() {
    var left = PreferenceValues()
    left[DictionaryPreferenceKey.self] = ["one": 1, "two": 2]
    var right = PreferenceValues()
    right[DictionaryPreferenceKey.self] = ["one": 1, "two": 9]

    #expect(left != right)
  }

  @Test("closure preferences never compare equal by reflected Function text")
  func closurePreferencesCompareUnequal() {
    var left = PreferenceValues()
    left[ClosurePreferenceKey.self] = { 1 }
    let copy = left
    var right = PreferenceValues()
    right[ClosurePreferenceKey.self] = { 2 }

    #expect(left == copy)
    #expect(left != right)
  }

  @Test("toolbar preferences compare semantic fields while handlers refresh separately")
  func toolbarPreferencesUseExplicitSemanticEquality() {
    var left = PreferenceValues()
    left[ToolbarItemsPreferenceKey.self] = [
      ToolbarItemConfig(title: "Save", systemHint: "S", action: {})
    ]
    var right = PreferenceValues()
    right[ToolbarItemsPreferenceKey.self] = [
      ToolbarItemConfig(title: "Save", systemHint: "S", action: {})
    ]
    var changed = PreferenceValues()
    changed[ToolbarItemsPreferenceKey.self] = [
      ToolbarItemConfig(title: "Reset", systemHint: "R", action: {})
    ]

    #expect(left == right)
    #expect(left != changed)
  }

  private func environmentSnapshot<K: EnvironmentKey>(
    _ key: K.Type,
    value: K.Value
  ) -> EnvironmentSnapshot {
    var values = EnvironmentValues()
    values[key] = value
    return environmentSnapshot(from: values)
  }

  private func environmentSnapshot(
    from values: EnvironmentValues
  ) -> EnvironmentSnapshot {
    return ResolveContext(
      identity: testIdentity("TypedReuseEquality"),
      environmentValues: values
    ).environment
  }
}
