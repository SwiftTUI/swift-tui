import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Proves the reader-attribution model (``ReaderAttributionConfiguration``) is
/// active and correct: when a view only PROJECTS a binding (`$flag`) and a
/// distinct descendant consumes it, the state-slot dependency is attributed to
/// the projecting owner in legacy mode (owner-anchored + eager projection read)
/// but to the genuine downstream reader in reader-attributed mode. That shift is
/// what lets a `@State` toggle spare disjoint subtrees instead of re-resolving
/// the owner's whole subtree.
///
/// Serialized because it flips the process-level configuration flag.
@MainActor
@Suite(.serialized)
struct ReaderAttributionTests {
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

  /// Resolves the probe and returns the set of identities recorded as
  /// dependents of any `@State` slot (the reverse dependency index).
  private func slotDependentIdentities(readerAttributed: Bool) -> Set<String> {
    let previous = ReaderAttributionConfiguration.isEnabled
    ReaderAttributionConfiguration.isEnabled = readerAttributed
    defer { ReaderAttributionConfiguration.isEnabled = previous }

    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(ProjectingOwnerProbe(), in: context)

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

  @Test("legacy mode: the projecting owner is a state-slot dependent")
  func legacyOwnerIsDependent() {
    let dependents = slotDependentIdentities(readerAttributed: false)
    #expect(dependents.contains(testIdentity("Root").description))
  }

  @Test("reader-attributed mode: the projecting owner is spared; the reader depends")
  func readerAttributedSparesOwner() {
    let dependents = slotDependentIdentities(readerAttributed: true)
    // The owner only projected `$flag`, so it must NOT be a dependent...
    #expect(!dependents.contains(testIdentity("Root").description))
    // ...but the genuine downstream reader must be (the dependency moved, not lost).
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
    // owner node and ordinal regardless of attribution mode.
    guard let key = graph.debugTotalStateSnapshot().stateSlotDependents.keys.first,
      let owner = graph.nodeForViewNodeID(key.owner)
    else {
      return nil
    }
    return (owner, key.ordinal)
  }

  @Test("reader-attributed mode: a @State WRITE invalidates the genuine reader, not the owner")
  func readerAttributedWriteInvalidatesReader() throws {
    let previous = ReaderAttributionConfiguration.isEnabled
    ReaderAttributionConfiguration.isEnabled = true
    defer { ReaderAttributionConfiguration.isEnabled = previous }

    let slot = try #require(resolvedStateSlot())
    let spy = StateWriteRecordingInvalidator()
    slot.owner.invalidator = spy

    // Mimic `State.setValue`: the write passes the owner's view identity
    // explicitly. Reader attribution must override it with the genuine reader.
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

  @Test("legacy mode: a @State WRITE invalidates the owner (whole-subtree re-resolve)")
  func legacyWriteInvalidatesOwner() throws {
    let previous = ReaderAttributionConfiguration.isEnabled
    ReaderAttributionConfiguration.isEnabled = false
    defer { ReaderAttributionConfiguration.isEnabled = previous }

    let slot = try #require(resolvedStateSlot())
    let spy = StateWriteRecordingInvalidator()
    slot.owner.invalidator = spy

    slot.owner.setStateSlot(
      ordinal: slot.ordinal,
      value: true,
      invalidationIdentity: slot.owner.identity
    )

    let invalidated = spy.requests.reduce(into: Set<Identity>()) { $0.formUnion($1) }
    #expect(
      invalidated.contains(slot.owner.identity),
      "legacy attribution must invalidate the owner identity it was given"
    )
  }
}

private final class StateWriteRecordingInvalidator: Invalidating {
  private(set) var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}
