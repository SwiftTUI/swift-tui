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
}
