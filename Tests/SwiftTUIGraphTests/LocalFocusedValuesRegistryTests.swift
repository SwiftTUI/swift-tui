import Testing

@testable import SwiftTUIGraph

private enum PrimaryFocusedValueKey: FocusedValueKey {
  typealias Value = String
}

private enum SecondaryFocusedValueKey: FocusedValueKey {
  typealias Value = String
}

/// Pins `LocalFocusedValuesRegistry.restore`'s same-identity merge (F103).
/// `restore` was a bare `append(contentsOf:)` whose correctness relied on
/// callers always clearing before restoring — enforced nowhere — while
/// `register` merged same-identity entries explicitly. Focus-binding churn
/// really does restore over a live same-identity entry, so the two paths must
/// share one semantic: union the descendant sets, merge the values with the
/// incoming entry winning per key (the direction `register` uses), and never
/// grow a duplicate registration for one identity.
@MainActor
@Suite("LocalFocusedValuesRegistry")
struct LocalFocusedValuesRegistryTests {
  private func values(_ primary: String? = nil, secondary: String? = nil) -> FocusedValues {
    var values = FocusedValues()
    values[PrimaryFocusedValueKey.self] = primary
    values[SecondaryFocusedValueKey.self] = secondary
    return values
  }

  @Test("restore over a live same-identity entry merges instead of appending a duplicate")
  func restoreOverLiveEntryMerges() throws {
    let registry = LocalFocusedValuesRegistry()
    let identity = testIdentity("Root", "Pane")
    let liveDescendant = testIdentity("Root", "Pane", "Live")
    let restoredDescendant = testIdentity("Root", "Pane", "Restored")

    registry.register(
      identity: identity,
      descendantIdentities: [identity, liveDescendant],
      values: values("live", secondary: "live-only")
    )
    registry.restore([
      FocusedValuesRegistrationSnapshot(
        identity: identity,
        descendantIdentities: [restoredDescendant],
        values: values("restored")
      )
    ])

    let registrations = registry.snapshot()
    #expect(registrations.count == 1, "one identity must never hold two registrations")
    let merged = try #require(registrations.first)
    #expect(
      merged.descendantIdentities == [identity, liveDescendant, restoredDescendant],
      "descendant sets union"
    )
    #expect(
      merged.values[PrimaryFocusedValueKey.self] == "restored",
      "the incoming entry wins per key, matching register's merge direction"
    )
    #expect(
      merged.values[SecondaryFocusedValueKey.self] == "live-only",
      "keys absent from the incoming entry survive the merge"
    )
  }

  @Test("restore into an empty registry appends every snapshot entry")
  func restoreIntoEmptyRegistryAppends() {
    let registry = LocalFocusedValuesRegistry()
    let first = testIdentity("Root", "A")
    let second = testIdentity("Root", "B")

    registry.restore([
      FocusedValuesRegistrationSnapshot(
        identity: first, descendantIdentities: [first], values: values("a")
      ),
      FocusedValuesRegistrationSnapshot(
        identity: second, descendantIdentities: [second], values: values("b")
      ),
    ])

    let registrations = registry.snapshot()
    #expect(registrations.count == 2)
    #expect(registry.focusedValues(for: first)[PrimaryFocusedValueKey.self] == "a")
    #expect(registry.focusedValues(for: second)[PrimaryFocusedValueKey.self] == "b")
  }

  @Test("consumption after a churn-then-restore sees exactly the merged values")
  func consumptionAfterChurnRestoreSeesMergedValues() {
    let registry = LocalFocusedValuesRegistry()
    let identity = testIdentity("Root", "Pane")
    let focused = testIdentity("Root", "Pane", "Field")

    registry.register(
      identity: identity,
      descendantIdentities: [identity, focused],
      values: values("churned", secondary: "kept")
    )
    registry.restore([
      FocusedValuesRegistrationSnapshot(
        identity: identity,
        descendantIdentities: [focused],
        values: values("stale")
      )
    ])

    let resolved = registry.focusedValues(for: focused)
    #expect(resolved[PrimaryFocusedValueKey.self] == "stale")
    #expect(resolved[SecondaryFocusedValueKey.self] == "kept")
  }
}
