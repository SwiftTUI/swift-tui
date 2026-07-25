import Testing

@testable import SwiftTUIGraph

// Pure value tests for the CommittedFreshness transitions: each transition's
// exact stamp effects, and the service-query divergence that encodes the memo
// exemption. These pin the module's contract so the reuse gates and the
// upward staleness walks can rely on it without re-stating stamp semantics.
@Suite("CommittedFreshness transitions")
struct CommittedFreshnessTests {
  @Test("initial state serves nothing and denies as stale-snapshot")
  func initialState() {
    let freshness = CommittedFreshness()
    #expect(!freshness.isCommittedSnapshotFresh)
    #expect(!freshness.hasStaleIslandDescendant)
    #expect(!freshness.hasForeignParentedChild)
    #expect(!freshness.canServeValueBlind)
    #expect(!freshness.canServeMemo)
    #expect(!freshness.hasFreshCommittedSnapshot)
    #expect(freshness.valueBlindDenialReason == "stale-snapshot")
  }

  @Test("commitApplied re-adjudicates all three stamps")
  func commitAppliedResetsEverything() {
    var freshness = CommittedFreshness()
    freshness.markChildReseated()
    freshness.markDescendantChanged(crossingIslandSeam: true)
    freshness.markDescendantChanged(crossingIslandSeam: false)

    freshness.commitApplied()

    #expect(freshness.isCommittedSnapshotFresh)
    #expect(!freshness.hasStaleIslandDescendant)
    #expect(!freshness.hasForeignParentedChild)
    #expect(freshness.canServeValueBlind)
    #expect(freshness.canServeMemo)
    #expect(freshness.valueBlindDenialReason == nil)
  }

  @Test("snapshotRefreshed restores freshness WITHOUT re-adjudicating verdicts")
  func snapshotRefreshedPreservesVerdicts() {
    var freshness = CommittedFreshness()
    freshness.markChildReseated()
    freshness.markDescendantChanged(crossingIslandSeam: true)

    freshness.snapshotRefreshed()

    // Freshness returns; the island and foreign-parented verdicts carry
    // forward — a refresh is not a body re-run and proves neither.
    #expect(freshness.isCommittedSnapshotFresh)
    #expect(freshness.hasStaleIslandDescendant)
    #expect(freshness.hasForeignParentedChild)
    #expect(!freshness.canServeValueBlind)
    #expect(!freshness.canServeMemo)
  }

  @Test("the ownership claim needs freshness AND an unrecorded re-seat")
  func ownershipClaimPredicate() {
    var freshness = CommittedFreshness()
    // Never committed: the listing is not load-bearing, so there is no claim.
    #expect(!freshness.claimsOwnershipOfListedChildren)

    freshness.commitApplied()
    #expect(freshness.claimsOwnershipOfListedChildren)

    // An island-stale descendant denies service on its own but does not
    // withdraw the ownership claim — the stranded-listing sweep must keep
    // watching such a node, since its missing re-seat mark is the defect.
    freshness.markDescendantChanged(crossingIslandSeam: true)
    #expect(freshness.claimsOwnershipOfListedChildren)
    #expect(!freshness.canServeValueBlind)

    // A recorded re-seat is what withdraws it.
    freshness.markChildReseated()
    #expect(!freshness.claimsOwnershipOfListedChildren)
  }

  @Test("the memo exemption: foreign-parented denies value-blind but not memo")
  func memoExemptionDivergence() {
    var freshness = CommittedFreshness()
    freshness.commitApplied()
    freshness.markChildReseated()

    #expect(!freshness.canServeValueBlind)
    #expect(freshness.canServeMemo)
    #expect(freshness.valueBlindDenialReason == "foreign-parented-child")
  }

  @Test("descendant change below the island seam clears freshness only")
  func descendantChangedBelowSeam() {
    var freshness = CommittedFreshness()
    freshness.commitApplied()

    freshness.markDescendantChanged(crossingIslandSeam: false)

    #expect(!freshness.isCommittedSnapshotFresh)
    #expect(!freshness.hasStaleIslandDescendant)
    #expect(!freshness.hasFreshCommittedSnapshot)
    #expect(freshness.valueBlindDenialReason == "stale-snapshot")
  }

  @Test("descendant change across the island seam records the island verdict only")
  func descendantChangedAcrossSeam() {
    var freshness = CommittedFreshness()
    freshness.commitApplied()

    freshness.markDescendantChanged(crossingIslandSeam: true)

    // Freshness stays set: the committed mirror is still rebuildable from
    // live children on THIS side of the seam; only reuse is denied.
    #expect(freshness.isCommittedSnapshotFresh)
    #expect(freshness.hasStaleIslandDescendant)
    #expect(freshness.hasFreshCommittedSnapshot)
    #expect(!freshness.canServeValueBlind)
    #expect(!freshness.canServeMemo)
    #expect(freshness.valueBlindDenialReason == "stale-island-descendant")
  }

  @Test("retained write-back admissibility ignores freshness itself")
  func retainedWriteBackAdmissibility() {
    // The write-back restores freshness, so a stale snapshot is exactly the
    // case it exists to fix and must not deny. Only the two verdicts the
    // refresh carries forward unchanged can deny.
    var freshness = CommittedFreshness()
    #expect(freshness.admitsRetainedWriteBack)
    #expect(freshness.retainedWriteBackDenialReason == nil)

    freshness.markDescendantChanged(crossingIslandSeam: false)
    #expect(!freshness.isCommittedSnapshotFresh)
    #expect(freshness.admitsRetainedWriteBack)

    freshness.markDescendantChanged(crossingIslandSeam: true)
    #expect(!freshness.admitsRetainedWriteBack)
    #expect(freshness.retainedWriteBackDenialReason == "stale-island-descendant")
  }

  @Test("a foreign-parented listing denies a retained write-back")
  func foreignParentedDeniesWriteBack() {
    var freshness = CommittedFreshness()
    freshness.markChildReseated()
    #expect(!freshness.admitsRetainedWriteBack)
    #expect(freshness.retainedWriteBackDenialReason == "foreign-parented-child")

    // Sticky until the node's own apply re-owns its children.
    freshness.commitApplied()
    #expect(freshness.admitsRetainedWriteBack)
  }

  @Test("write-back admissibility follows the value-blind verdicts, minus freshness")
  func admissibilityMirrorsValueBlindMinusFreshness() {
    // The invariant the write-back assert encodes: once freshness is restored,
    // admitting the write-back and admitting value-blind service are the same
    // question. If these ever diverge, the assert is guarding the wrong thing.
    for island in [false, true] {
      for foreign in [false, true] {
        var freshness = CommittedFreshness()
        if island { freshness.markDescendantChanged(crossingIslandSeam: true) }
        if foreign { freshness.markChildReseated() }
        let admits = freshness.admitsRetainedWriteBack
        freshness.snapshotRefreshed()
        #expect(admits == freshness.canServeValueBlind)
      }
    }
  }

  @Test("denial reasons report in the load-bearing trace order")
  func denialReasonOrder() {
    var freshness = CommittedFreshness()
    freshness.markChildReseated()
    freshness.markDescendantChanged(crossingIslandSeam: true)
    // Not fresh + island + foreign: staleness wins.
    #expect(freshness.valueBlindDenialReason == "stale-snapshot")

    freshness.snapshotRefreshed()
    // Fresh + island + foreign: island wins over foreign.
    #expect(freshness.valueBlindDenialReason == "stale-island-descendant")

    freshness.commitApplied()
    freshness.markChildReseated()
    // Fresh + foreign only.
    #expect(freshness.valueBlindDenialReason == "foreign-parented-child")

    freshness.commitApplied()
    #expect(freshness.valueBlindDenialReason == nil)
  }
}
