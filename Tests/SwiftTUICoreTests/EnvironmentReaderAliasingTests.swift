import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Regression for the environment-reader reverse-scan aliasing bug.
///
/// `environmentDependents` resolves which `@Environment` readers to invalidate
/// when an environment key changes. It started from the precise reader
/// `ViewNodeID`s but used to throw them away — mapping each to its `Identity`,
/// then recovering a node with a nondeterministic `identityByNodeID.first(where:)`
/// reverse scan. Under identity aliasing (duplicate `.id`, unstable `ForEach`
/// ids) two live nodes share one `Identity`, so the reverse scan returned an
/// arbitrary aliased sibling and silently dropped the genuine reader, leaving it
/// on stale environment. The fix keeps the original IDs and uses only the
/// forward O(1) lookup for subtree scoping.
@MainActor
@Suite("Environment-reader dependents under identity aliasing")
struct EnvironmentReaderAliasingTests {
  /// A stand-in for an `EnvironmentKey` type identity; the resolver only uses it
  /// as a dictionary key.
  private let changedKey = ObjectIdentifier(Int.self)

  @Test("every aliased reader of a changed key is invalidated (no reverse-scan drop)")
  func aliasedReadersAreAllInvalidated() {
    let nodeA = ViewNodeID(rawValue: 1)
    let nodeB = ViewNodeID(rawValue: 2)
    // Two distinct live nodes sharing one identity — the aliasing case.
    let aliased = testIdentity("Root", "Reader")

    let dirtied = ViewGraphDependencyIndex.environmentDependents(
      within: [testIdentity("Root")],
      changedKeys: [changedKey],
      environmentDependents: [changedKey: [nodeA, nodeB]],
      identityByNodeID: [nodeA: aliased, nodeB: aliased]
    )

    // Both genuine readers must be dirtied. The old reverse scan collapsed them
    // to one identity and recovered a single arbitrary node, dropping the other.
    #expect(dirtied == [nodeA, nodeB])
  }

  @Test("readers outside the changed subtree are excluded")
  func outOfScopeReadersExcluded() {
    let inScope = ViewNodeID(rawValue: 10)
    let outOfScope = ViewNodeID(rawValue: 11)

    let dirtied = ViewGraphDependencyIndex.environmentDependents(
      within: [testIdentity("Root")],
      changedKeys: [changedKey],
      environmentDependents: [changedKey: [inScope, outOfScope]],
      identityByNodeID: [
        inScope: testIdentity("Root", "A"),
        outOfScope: testIdentity("Other", "B"),
      ]
    )

    #expect(dirtied == [inScope])
  }

  @Test("a reader whose identity is unknown is not invalidated")
  func unmappedReaderIsExcluded() {
    let mapped = ViewNodeID(rawValue: 20)
    let unmapped = ViewNodeID(rawValue: 21)

    let dirtied = ViewGraphDependencyIndex.environmentDependents(
      within: [testIdentity("Root")],
      changedKeys: [changedKey],
      environmentDependents: [changedKey: [mapped, unmapped]],
      identityByNodeID: [mapped: testIdentity("Root", "A")]
    )

    #expect(dirtied == [mapped])
  }
}
