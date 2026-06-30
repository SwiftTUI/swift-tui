import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Proves Phase 3 slice 2's focused-value reader attribution: a `@FocusedValue`
/// (or `@FocusedBinding`) read is recorded against the evaluating reader node, so
/// a *pure* focused-value change can invalidate exactly those readers instead of
/// the whole tree. This is the precision the single-pass focus-sync path depends
/// on (`RunLoop.processFocusSyncIteration` → `focusedValuesDependentIdentities()`).
///
/// The complementary runtime behavior — that the change actually propagates to the
/// reader one frame later — is covered by `AppRuntimeTests`' focused-value suite.
@MainActor
struct FocusedValueReaderAttributionTests {
  /// Resolves a probe in a fresh graph and returns the identities recorded as
  /// dependents of the focused-values environment key (the reverse index the run
  /// loop queries to invalidate readers precisely).
  private func focusedValuesDependents<V: View>(
    for view: V
  ) -> Set<Identity> {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(view, in: context)
    return graph.environmentDependentIdentities(
      for: EnvironmentValues.focusedValuesDependencyKeys
    )
  }

  private func covers(_ dependents: Set<Identity>, _ root: Identity) -> Bool {
    dependents.contains { $0 == root || $0.isDescendant(of: root) }
  }

  @Test("a @FocusedValue read attributes to the reader, sparing a static sibling")
  func focusedValueReadAttributesToReaderOnly() {
    let dependents = focusedValuesDependents(for: FocusedTitleReaderProbe())

    #expect(
      covers(dependents, testIdentity("FocusedValueProbe", "Reader")),
      "the @FocusedValue reader must be recorded as a focused-values dependent"
    )
    #expect(
      !covers(dependents, testIdentity("FocusedValueProbe", "Sibling")),
      "a static sibling that never reads a focused value must not be invalidated"
    )
  }

  @Test("a @FocusedBinding read attributes to the reader, sparing a static sibling")
  func focusedBindingReadAttributesToReaderOnly() {
    let dependents = focusedValuesDependents(for: FocusedNumberReaderProbe())

    #expect(
      covers(dependents, testIdentity("FocusedBindingProbe", "Reader")),
      "the @FocusedBinding reader must be recorded as a focused-values dependent"
    )
    #expect(
      !covers(dependents, testIdentity("FocusedBindingProbe", "Sibling")),
      "a static sibling that never reads a focused binding must not be invalidated"
    )
  }

  @Test("a tree with no focused-value readers records no focused-values dependents")
  func noReaderRecordsNoDependents() {
    let dependents = focusedValuesDependents(for: StaticOnlyProbe())

    #expect(
      dependents.isEmpty,
      "with no reader, the pure-value path invalidates nothing — there is nothing to update"
    )
  }
}

private enum AttributionFocusedTitleKey: FocusedValueKey {
  typealias Value = String
}

private enum AttributionFocusedNumberKey: FocusedValueKey {
  typealias Value = Binding<Int>
}

extension FocusedValues {
  fileprivate var attributionFocusedTitle: String? {
    get { self[AttributionFocusedTitleKey.self] }
    set { self[AttributionFocusedTitleKey.self] = newValue }
  }

  fileprivate var attributionFocusedNumber: Binding<Int>? {
    get { self[AttributionFocusedNumberKey.self] }
    set { self[AttributionFocusedNumberKey.self] = newValue }
  }
}

private struct FocusedTitleReaderProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("static")
        .id(testIdentity("FocusedValueProbe", "Sibling"))
      FocusedTitleReader()
        .id(testIdentity("FocusedValueProbe", "Reader"))
    }
  }
}

private struct FocusedTitleReader: View {
  @FocusedValue(\.attributionFocusedTitle) private var title

  var body: some View {
    Text("title: \(title ?? "none")")
  }
}

private struct FocusedNumberReaderProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("static")
        .id(testIdentity("FocusedBindingProbe", "Sibling"))
      FocusedNumberReader()
        .id(testIdentity("FocusedBindingProbe", "Reader"))
    }
  }
}

private struct FocusedNumberReader: View {
  @FocusedBinding(\.attributionFocusedNumber) private var number

  var body: some View {
    Text("number: \(number ?? -1)")
  }
}

private struct StaticOnlyProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("one")
        .id(testIdentity("StaticOnlyProbe", "One"))
      Text("two")
        .id(testIdentity("StaticOnlyProbe", "Two"))
    }
  }
}
