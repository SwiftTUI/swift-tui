import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private enum ProjectionThemeKey: EnvironmentKey {
  static let defaultValue = "plain"
}

private enum ProjectionCountKey: EnvironmentKey {
  static let defaultValue = 0
}

/// Pins the diagnostic `values` projection contract across typed environment
/// writes: typed entries appear under their reflected key names, untyped
/// entries pass through, and the projection stays a faithful round-trip
/// currency for the public `values` setter's typed-retention rule.
@MainActor
@Suite
struct EnvironmentSnapshotDebugProjectionTests {
  private func snapshotWithTypedWrites() -> EnvironmentSnapshot {
    var environmentValues = EnvironmentValues()
    environmentValues[ProjectionThemeKey.self] = "midnight"
    environmentValues[ProjectionCountKey.self] = 3
    return environmentValues.applying(to: EnvironmentSnapshot())
  }

  @Test("typed writes project into values under reflected key names")
  func typedWritesProjectIntoValues() {
    let snapshot = snapshotWithTypedWrites()

    #expect(
      snapshot.values[String(reflecting: ProjectionThemeKey.self)]
        == String(reflecting: "midnight")
    )
    #expect(
      snapshot.values[String(reflecting: ProjectionCountKey.self)]
        == String(reflecting: 3)
    )
  }

  @Test("untyped entries survive typed writes and both appear in the projection")
  func untypedEntriesSurviveTypedWrites() {
    let base = EnvironmentSnapshot(
      debugSignature: "session",
      values: ["surface": "primary", "session": "demo"]
    )
    var environmentValues = EnvironmentValues()
    environmentValues[ProjectionThemeKey.self] = "midnight"
    let snapshot = environmentValues.applying(to: base)

    #expect(snapshot.values["surface"] == "primary")
    #expect(snapshot.values["session"] == "demo")
    #expect(
      snapshot.values[String(reflecting: ProjectionThemeKey.self)]
        == String(reflecting: "midnight")
    )
  }

  @Test("identically built snapshots with typed and untyped entries compare equal")
  func identicallyBuiltSnapshotsCompareEqual() {
    let base = EnvironmentSnapshot(values: ["surface": "primary"])
    var leftValues = EnvironmentValues()
    leftValues[ProjectionThemeKey.self] = "midnight"
    var rightValues = EnvironmentValues()
    rightValues[ProjectionThemeKey.self] = "midnight"

    let left = leftValues.applying(to: base)
    let right = rightValues.applying(to: base)

    #expect(left == right)
  }

  @Test("typed value difference denies snapshot equality")
  func typedValueDifferenceDeniesEquality() {
    var leftValues = EnvironmentValues()
    leftValues[ProjectionThemeKey.self] = "midnight"
    var rightValues = EnvironmentValues()
    rightValues[ProjectionThemeKey.self] = "noon"

    let left = leftValues.applying(to: EnvironmentSnapshot())
    let right = rightValues.applying(to: EnvironmentSnapshot())

    #expect(left != right)
    #expect(
      left.differingValueDebugNames(from: right)
        == [String(reflecting: ProjectionThemeKey.self)]
    )
  }

  @Test("untyped value difference denies snapshot equality")
  func untypedValueDifferenceDeniesEquality() {
    var environmentValues = EnvironmentValues()
    environmentValues[ProjectionThemeKey.self] = "midnight"

    let left = environmentValues.applying(
      to: EnvironmentSnapshot(values: ["surface": "primary"])
    )
    let right = environmentValues.applying(
      to: EnvironmentSnapshot(values: ["surface": "secondary"])
    )

    #expect(left != right)
    #expect(left.differingValueDebugNames(from: right) == ["surface"])
  }

  @Test("replacing values with the identical projection retains typed equality")
  func settingIdenticalProjectionRetainsTypedEquality() {
    let original = snapshotWithTypedWrites()
    var replaced = original
    replaced.values = original.values

    #expect(replaced == original)
    #expect(replaced.values == original.values)
  }

  @Test("replacing values with a changed projection falls back to string equality")
  func settingChangedProjectionChangesEquality() {
    let original = snapshotWithTypedWrites()
    var projection = original.values
    projection[String(reflecting: ProjectionThemeKey.self)] = String(reflecting: "noon")
    var replaced = original
    replaced.values = projection

    #expect(replaced != original)
    #expect(replaced.values == projection)
  }
}
