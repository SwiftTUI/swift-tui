import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Proves "Lever B" moves the `isPresented` state-read dependency off the
/// presenting view (an ancestor of the background) and onto the zero-size
/// sibling trigger leaf. This is the precondition for the background being a
/// disjoint sibling of the dirty node when `isPresented` toggles.
///
/// Serialized because it flips the process-level reader-attribution flag.
@MainActor
@Suite(.serialized)
struct PresentationTriggerAttributionTests {
  /// Owns `@State`, projects it into `.sheet`, and never reads `wrappedValue` in
  /// its own body. The static sibling keeps the owner from collapsing onto a
  /// single identity with its child.
  private struct SheetOwnerProbe: View {
    @State private var presented = false

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("static-sibling")
        Text("background")
          .sheet("Inspector", isPresented: $presented) {
            Text("sheet body")
          }
      }
    }
  }

  private func dependentIdentities(readerAttributed: Bool) -> [String] {
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
    _ = Resolver().resolve(SheetOwnerProbe(), in: context)

    let snapshot = graph.debugTotalStateSnapshot()
    var identities: [String] = []
    for (_, dependents) in snapshot.stateSlotDependents {
      for nodeID in dependents {
        if let identity = snapshot.identityByNodeID[nodeID] {
          identities.append(identity.description)
        }
      }
    }
    return identities.sorted()
  }

  @Test("reader-attributed: the isPresented dependency lands on the trigger leaf")
  func dependencyLandsOnTriggerLeaf() {
    let dependents = dependentIdentities(readerAttributed: true)
    // Every dependent of the `@State` slot is a trigger leaf — neither the owner
    // (`Root`) nor the background ("background" Text).
    #expect(!dependents.isEmpty)
    #expect(dependents.allSatisfy { $0.hasSuffix("__presentationTrigger") })
  }

  @Test("legacy: the isPresented dependency lands on the presenting-view subtree")
  func legacyDependencyLandsOnOwnerSubtree() {
    let dependents = dependentIdentities(readerAttributed: false)
    #expect(!dependents.isEmpty)
    // No trigger leaf exists in legacy mode; the dependency sits on the owner /
    // background root instead.
    #expect(dependents.allSatisfy { !$0.hasSuffix("__presentationTrigger") })
  }
}
