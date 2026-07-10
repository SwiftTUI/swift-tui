import Testing

@testable import SwiftTUIGraph

/// Direct units for the commit-side invalidation summary (F123): the
/// direct/descendant/ancestor classification steers the commit fallback
/// paths and previously had zero test mentions.
@Suite("Invalidation summary")
struct InvalidationSummaryTests {
  private let invalidated = testIdentity("Root", "Section", "Leaf")

  private var summary: InvalidationSummary {
    InvalidationSummary(invalidatedIdentities: [invalidated])
  }

  @Test("direct invalidation is exact-identity only")
  func directInvalidationIsExact() {
    #expect(summary.isDirectlyInvalidated(invalidated))
    #expect(!summary.isDirectlyInvalidated(testIdentity("Root", "Section")))
    #expect(!summary.isDirectlyInvalidated(testIdentity("Root", "Section", "Leaf", "Deeper")))
  }

  @Test("every strict ancestor gains an invalidated descendant")
  func ancestorsGainInvalidatedDescendants() {
    #expect(summary.containsInvalidatedDescendant(of: testIdentity("Root", "Section")))
    #expect(summary.containsInvalidatedDescendant(of: testIdentity("Root")))
    #expect(
      !summary.containsInvalidatedDescendant(of: invalidated),
      "the invalidated identity itself is direct, not a descendant holder"
    )
    #expect(!summary.containsInvalidatedDescendant(of: testIdentity("Root", "Other")))
  }

  @Test("descendants of an invalidated identity see an invalidated ancestor")
  func descendantsSeeInvalidatedAncestor() {
    #expect(summary.hasInvalidatedAncestor(of: testIdentity("Root", "Section", "Leaf", "Inner")))
    #expect(!summary.hasInvalidatedAncestor(of: invalidated), "self is not its own ancestor")
    #expect(!summary.hasInvalidatedAncestor(of: testIdentity("Root", "Other", "Inner")))
  }

  @Test("subtree intersection covers self, ancestors, and descendants — and nothing else")
  func subtreeIntersectionIsTotalOverTheAxis() {
    #expect(summary.intersectsSubtree(at: invalidated))
    #expect(summary.intersectsSubtree(at: testIdentity("Root", "Section")))
    #expect(summary.intersectsSubtree(at: testIdentity("Root", "Section", "Leaf", "Inner")))
    #expect(!summary.intersectsSubtree(at: testIdentity("Root", "Other")))
  }

  @Test("an empty summary is empty and intersects nothing")
  func emptySummary() {
    let empty = InvalidationSummary(invalidatedIdentities: [])
    #expect(empty.isEmpty)
    #expect(!empty.intersectsSubtree(at: testIdentity("Root")))
  }
}
