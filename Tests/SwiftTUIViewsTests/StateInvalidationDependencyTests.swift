import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Proves the `@State` invalidation dependency model (reader attribution, now
/// unconditional):
///
/// - projecting `$state` is not a read — the projecting owner records nothing;
/// - genuine `wrappedValue` reads are attributed to the evaluating reader;
/// - a `@State` write retargets to the recorded readers, sparing the owner;
/// - a write with no recorded readers falls back to the owner (a conservative
///   safety net for deferred / conditional reads).
@MainActor
struct StateInvalidationDependencyTests {
  /// Owns `@State` and only PROJECTS it to a distinct descendant; it never reads
  /// `wrappedValue` in its own body. A sibling keeps the reader from collapsing
  /// onto the owner's identity.
  private struct ProjectingOwnerProbe: View {
    @State private var flag = false

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("static-sibling")
        BindingValueReader(flag: $flag)
      }
    }
  }

  /// The genuine reader: consumes `wrappedValue` of the projected binding.
  private struct BindingValueReader: View {
    @Binding var flag: Bool

    var body: some View {
      Text(flag ? "on" : "off")
    }
  }

  private struct BindingForwarder: View {
    @Binding var flag: Bool

    var body: some View {
      BindingValueReader(flag: $flag)
    }
  }

  private struct ForwardingOwnerProbe: View {
    @State private var flag = false

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("static-sibling")
        BindingForwarder(flag: $flag)
      }
    }
  }

  private struct ConditionalStateReaderProbe: View {
    static let valueOrdinal = 1

    @State private var value: Int
    let showReader: Bool

    init(showReader: Bool) {
      _value = State(initialValue: 1, line: 0, column: UInt(Self.valueOrdinal))
      self.showReader = showReader
    }

    var body: some View {
      if showReader {
        Text("Value \(value)")
      } else {
        Text("Hidden")
      }
    }
  }

  private struct DeferredBindingOwnerProbe: View {
    @State private var flag = false

    var body: some View {
      EnvironmentReader(\.terminalSize) { _ in
        BindingValueReader(flag: $flag)
          .id(testIdentity("DeferredBindingReader"))
      }
    }
  }

  /// Resolves the probe and returns the set of identities recorded as
  /// dependents of any `@State` slot (the reverse dependency index).
  private func slotDependentIdentities<V: View>(
    for view: V
  ) -> Set<String> {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(view, in: context)

    let snapshot = graph.debugTotalStateSnapshot()
    var identities: Set<String> = []
    for (_, dependents) in snapshot.stateSlotDependents {
      for nodeID in dependents {
        if let identity = snapshot.identityByNodeID[nodeID] {
          identities.insert(identity.description)
        }
      }
    }
    return identities
  }

  @Test("the projecting owner is spared; the genuine reader depends")
  func readerAttributedSparesOwner() {
    let dependents = slotDependentIdentities(for: ProjectingOwnerProbe())
    // The owner only projected `$flag`, so it must NOT be a dependent...
    #expect(!dependents.contains(testIdentity("Root").description))
    // ...but the genuine downstream reader must be (the dependency moved, not lost).
    #expect(!dependents.isEmpty)
  }

  @Test("pass-through binding projection still spares the owner")
  func passThroughProjectionSparesOwner() {
    let dependents = slotDependentIdentities(for: ForwardingOwnerProbe())

    #expect(!dependents.contains(testIdentity("Root").description))
    #expect(!dependents.isEmpty)
  }

  @Test("conditional @State reads record dependencies only after the branch reads")
  func conditionalStateReadsRecordOnlyWhenBranchReads() {
    let hiddenDependents = slotDependentIdentities(
      for: ConditionalStateReaderProbe(showReader: false)
    )
    let shownDependents = slotDependentIdentities(
      for: ConditionalStateReaderProbe(showReader: true)
    )

    #expect(hiddenDependents.isEmpty)
    #expect(!shownDependents.isEmpty)
  }

  @Test("a hidden conditional @State write falls back to the owner")
  func hiddenConditionalStateWriteFallsBackToOwner() throws {
    let graph = ViewGraph()
    let ownerIdentity = testIdentity("Root")
    graph.beginFrame()
    var context = ResolveContext(
      identity: ownerIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(
      ConditionalStateReaderProbe(showReader: false),
      in: context
    )

    let owner = try #require(graph.nodeForIdentity(ownerIdentity))
    let unreadKey = StateSlotKey(
      owner: owner.viewNodeID,
      ordinal: ConditionalStateReaderProbe.valueOrdinal
    )
    #expect(graph.stateDependentIdentities(for: unreadKey).isEmpty)

    let spy = StateWriteRecordingInvalidator()
    owner.invalidator = spy
    owner.setStateSlot(
      ordinal: ConditionalStateReaderProbe.valueOrdinal,
      value: 2,
      invalidationIdentity: ownerIdentity
    )

    let invalidated = spy.requests.reduce(into: Set<Identity>()) { $0.formUnion($1) }
    #expect(invalidated == [ownerIdentity])
  }

  @Test("scoped builder binding reads land on the descendant")
  func scopedBuilderBindingReadsLandOnDescendant() {
    let dependents = slotDependentIdentities(for: DeferredBindingOwnerProbe())

    #expect(!dependents.contains(testIdentity("Root").description))
    #expect(!dependents.isEmpty)
  }

  /// Resolves the probe in a fresh graph, then locates the actual `@State` slot
  /// from the dependency index and returns the owner node holding it plus the
  /// slot's ordinal. Driving off the recorded key (rather than a guessed
  /// ordinal) makes the write target exactly the slot the reader depends on.
  private func resolvedStateSlot() -> (owner: SwiftTUICore.ViewNode, ordinal: Int)? {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(ProjectingOwnerProbe(), in: context)

    // Exactly one `@State` slot exists (the probe's `flag`). The key carries the
    // owner node and ordinal.
    guard let key = graph.debugTotalStateSnapshot().stateSlotDependents.keys.first,
      let owner = graph.nodeForViewNodeID(key.owner)
    else {
      return nil
    }
    return (owner, key.ordinal)
  }

  @Test("a @State WRITE invalidates the genuine reader, not the owner")
  func writeInvalidatesReader() throws {
    let slot = try #require(resolvedStateSlot())
    let spy = StateWriteRecordingInvalidator()
    slot.owner.invalidator = spy

    // Mimic `State.setValue`: the write passes the owner's view identity
    // explicitly. Reader attribution overrides it with the genuine reader.
    slot.owner.setStateSlot(
      ordinal: slot.ordinal,
      value: true,
      invalidationIdentity: slot.owner.identity
    )

    let invalidated = spy.requests.reduce(into: Set<Identity>()) { $0.formUnion($1) }
    #expect(!invalidated.isEmpty, "the change must still schedule a frame")
    #expect(
      !invalidated.contains(slot.owner.identity),
      "the projecting owner is an ancestor of disjoint subtrees; invalidating it defeats reuse"
    )
  }

  @Test("a no-reader @State slot write falls back to the owner")
  func noReaderStateWriteFallsBackToOwner() throws {
    let graph = ViewGraph()
    let ownerIdentity = testIdentity("Root")
    graph.beginFrame()
    let owner = graph.beginEvaluation(identity: ownerIdentity, invalidator: nil)
    graph.finishEvaluation(
      owner,
      resolved: ResolvedNode(identity: ownerIdentity, kind: .root),
      accessedStateSlots: 0
    )

    owner.setStateSlot(
      ordinal: 0,
      value: false,
      invalidationIdentity: ownerIdentity
    )
    let unreadKey = StateSlotKey(owner: owner.viewNodeID, ordinal: 0)
    #expect(graph.stateDependentIdentities(for: unreadKey).isEmpty)

    let spy = StateWriteRecordingInvalidator()
    owner.invalidator = spy
    owner.setStateSlot(
      ordinal: 0,
      value: true,
      invalidationIdentity: ownerIdentity
    )

    let invalidated = spy.requests.reduce(into: Set<Identity>()) { $0.formUnion($1) }
    #expect(invalidated == [ownerIdentity])
  }
}

private final class StateWriteRecordingInvalidator: Invalidating {
  private(set) var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}
