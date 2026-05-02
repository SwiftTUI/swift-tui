import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct EnvironmentSnapshotFastPathTests {
  @Test("snapshots with equal contents compare equal even when stored separately")
  func equalSnapshotsCompareEqual() {
    let left = EnvironmentSnapshot(
      debugSignature: "demo",
      values: ["theme": "dark", "mode": "compact"],
      style: .init(
        appearance: .fallback,
        isEnabled: true
      )
    )
    let right = EnvironmentSnapshot(
      debugSignature: "demo",
      values: ["mode": "compact", "theme": "dark"],
      style: .init(
        appearance: .fallback,
        isEnabled: true
      )
    )

    #expect(left == right)
  }

  @Test("copying a snapshot preserves value semantics when one copy changes")
  func copiedSnapshotsRemainIndependentAfterMutation() {
    var left = EnvironmentSnapshot(
      debugSignature: "demo",
      values: ["theme": "dark"],
      style: .init(isEnabled: true)
    )
    let right = left

    #expect(left == right)

    left.debugSignature = "updated"
    left.values = ["theme": "light"]

    #expect(left != right)
    #expect(right.debugSignature == "demo")
    #expect(right.values == ["theme": "dark"])
    #expect(right.style.isEnabled)
  }

  @Test("resolve context snapshots continue to compare equal for matching environments")
  func resolveContextSnapshotsCompareEqual() {
    var environmentValues = EnvironmentValues()
    environmentValues.isEnabled = false

    let left = ResolveContext(
      identity: testIdentity("Root"),
      environment: .init(
        debugSignature: "session",
        values: ["surface": "benchmark"],
        style: .init(isEnabled: false)
      ),
      environmentValues: environmentValues
    )
    let right = ResolveContext(
      identity: testIdentity("Root"),
      environment: .init(
        debugSignature: "session",
        values: ["surface": "benchmark"],
        style: .init(isEnabled: false)
      ),
      environmentValues: environmentValues
    )

    #expect(left.environment == right.environment)
    #expect(left.environmentValues == right.environmentValues)
  }
}
